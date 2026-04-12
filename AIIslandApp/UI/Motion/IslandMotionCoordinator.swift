import Foundation
import SwiftUI

import AIIslandCore

public enum IslandExpansionOrigin: String, Sendable {
    case hover
    case pinned
}

public enum IslandInterruptionPolicy: String, Equatable, Sendable {
    case preserveMomentum
    case gentleSnapBack
    case holdPinned
}

public enum IslandMotionPhase: Equatable, Sendable {
    case collapsed
    case lifting(origin: IslandExpansionOrigin)
    case promoting(origin: IslandExpansionOrigin)
    case contentReveal(origin: IslandExpansionOrigin)
    case expanded(origin: IslandExpansionOrigin)
    case collapsing(origin: IslandExpansionOrigin?)

    public var origin: IslandExpansionOrigin? {
        switch self {
        case .collapsed:
            return nil
        case let .lifting(origin),
            let .promoting(origin),
            let .contentReveal(origin),
            let .expanded(origin):
            return origin
        case let .collapsing(origin):
            return origin
        }
    }
}

public struct IslandMotionProgress: Equatable, Sendable {
    public let progress: CGFloat
    public let target: CGFloat
    public let phase: IslandMotionPhase
    public let interruptionPolicy: IslandInterruptionPolicy

    public static let collapsed = IslandMotionProgress(
        progress: 0,
        target: 0,
        phase: .collapsed,
        interruptionPolicy: .gentleSnapBack
    )
}

public struct IslandMotionPresentation: Equatable, Sendable {
    public let phase: IslandMotionPhase
    public let shellScale: CGFloat
    public let shellYOffset: CGFloat
    public let shellOpacity: Double
    public let chromeOpacity: Double
    public let sheenOpacity: Double
    public let revealOpacity: Double
    public let revealHeight: CGFloat
    public let blurRadius: CGFloat
    public let progress: CGFloat
    public let interruptionPolicy: IslandInterruptionPolicy

    public static let collapsed = IslandMotionPresentation(
        phase: .collapsed,
        shellScale: 1.0,
        shellYOffset: 0,
        shellOpacity: 1.0,
        chromeOpacity: 0,
        sheenOpacity: 0,
        revealOpacity: 0,
        revealHeight: 0,
        blurRadius: 0,
        progress: 0,
        interruptionPolicy: .gentleSnapBack
    )
}

public struct IslandMotionTuning: Equatable, Sendable {
    public let tickInterval: TimeInterval
    public let hoverTargetProgress: CGFloat
    public let pinnedTargetProgress: CGFloat
    public let preserveMomentumGain: CGFloat
    public let snapBackGain: CGFloat
    public let reducedMotionGain: CGFloat

    public init(
        tickInterval: TimeInterval,
        hoverTargetProgress: CGFloat,
        pinnedTargetProgress: CGFloat,
        preserveMomentumGain: CGFloat,
        snapBackGain: CGFloat,
        reducedMotionGain: CGFloat
    ) {
        self.tickInterval = tickInterval
        self.hoverTargetProgress = hoverTargetProgress
        self.pinnedTargetProgress = pinnedTargetProgress
        self.preserveMomentumGain = preserveMomentumGain
        self.snapBackGain = snapBackGain
        self.reducedMotionGain = reducedMotionGain
    }

    public static let v02Default = IslandMotionTuning(
        tickInterval: 1.0 / 120.0,
        hoverTargetProgress: 0.86,
        pinnedTargetProgress: 1.0,
        preserveMomentumGain: 0.12,
        snapBackGain: 0.22,
        reducedMotionGain: 0.20
    )
}

@MainActor
public final class IslandMotionCoordinator: ObservableObject {
    @Published public private(set) var phase: IslandMotionPhase = .collapsed
    @Published public private(set) var targetShellState: ShellInteractionState = .collapsed
    @Published public private(set) var reducedMotionEnabled = false
    @Published public private(set) var motionProgress: IslandMotionProgress = .collapsed

    private let tuning: IslandMotionTuning
    private var motionTimer: Timer?
    private var targetProgress: CGFloat = 0
    private var currentProgress: CGFloat = 0
    private var expansionOrigin: IslandExpansionOrigin?
    private var interruptionPolicy: IslandInterruptionPolicy = .gentleSnapBack

    public init(tuning: IslandMotionTuning = .v02Default) {
        self.tuning = tuning
    }

    public func configure(reducedMotionEnabled: Bool) {
        self.reducedMotionEnabled = reducedMotionEnabled
    }

    public func apply(shellState: ShellInteractionState) {
        targetShellState = shellState

        let newOrigin: IslandExpansionOrigin? = {
            switch shellState {
            case .hoverExpanded:
                return .hover
            case .pinnedExpanded:
                return .pinned
            case .collapsed, .collapsing:
                return expansionOrigin
            }
        }()

        if let newOrigin {
            expansionOrigin = newOrigin
        }

        let nextTarget: CGFloat
        switch shellState {
        case .collapsed, .collapsing:
            nextTarget = 0
        case .hoverExpanded:
            nextTarget = tuning.hoverTargetProgress
        case .pinnedExpanded:
            nextTarget = tuning.pinnedTargetProgress
        }

        interruptionPolicy = resolveInterruptionPolicy(
            from: targetProgress,
            to: nextTarget,
            shellState: shellState
        )
        targetProgress = nextTarget
        updatePhaseForTargetChange()
        publishMotionProgress()
        startMotionTimerIfNeeded()
    }

    public func advanceForTesting(deltaTime: TimeInterval) {
        updateMotionFrame(deltaTime: deltaTime)
    }

    public var presentation: IslandMotionPresentation {
        let p = clamp(currentProgress)
        let maxScale = reducedMotionEnabled ? 0.010 : 0.016
        let chromeMax = reducedMotionEnabled ? 0.52 : 0.70
        let sheenMax = reducedMotionEnabled ? 0.22 : 0.34
        let blurMax: CGFloat = reducedMotionEnabled ? 0.55 : 1.0
        let revealMaxHeight: CGFloat = reducedMotionEnabled ? 6 : 10

        return IslandMotionPresentation(
            phase: phase,
            shellScale: 1 + (maxScale * p),
            shellYOffset: 0,
            shellOpacity: 1.0,
            chromeOpacity: chromeMax * p,
            sheenOpacity: sheenMax * p,
            revealOpacity: Double(p),
            revealHeight: revealMaxHeight * p,
            blurRadius: blurMax * p,
            progress: p,
            interruptionPolicy: interruptionPolicy
        )
    }

    nonisolated deinit {
        // Timer invalidation handled from main actor lifecycle.
    }

    private func startMotionTimerIfNeeded() {
        if motionTimer != nil {
            return
        }

        let timer = Timer(timeInterval: tuning.tickInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateMotionFrame(deltaTime: self?.tuning.tickInterval ?? (1.0 / 120.0))
            }
        }
        timer.tolerance = tuning.tickInterval * 0.25
        RunLoop.main.add(timer, forMode: .common)
        motionTimer = timer
    }

    private func stopMotionTimer() {
        motionTimer?.invalidate()
        motionTimer = nil
    }

    private func updateMotionFrame(deltaTime: TimeInterval) {
        let delta = targetProgress - currentProgress
        if abs(delta) < 0.0008 {
            currentProgress = targetProgress
            updatePhaseFromProgress()
            publishMotionProgress()
            if targetProgress == 0 {
                expansionOrigin = nil
            }
            stopMotionTimer()
            return
        }

        let gain = gainForCurrentPolicy()
        let step = delta * gain * CGFloat(max(deltaTime / tuning.tickInterval, 0.5))
        currentProgress = clamp(currentProgress + step)
        updatePhaseFromProgress()
        publishMotionProgress()
    }

    private func gainForCurrentPolicy() -> CGFloat {
        if reducedMotionEnabled {
            return tuning.reducedMotionGain
        }

        switch interruptionPolicy {
        case .preserveMomentum, .holdPinned:
            return tuning.preserveMomentumGain
        case .gentleSnapBack:
            return tuning.snapBackGain
        }
    }

    private func publishMotionProgress() {
        let next = IslandMotionProgress(
            progress: currentProgress,
            target: targetProgress,
            phase: phase,
            interruptionPolicy: interruptionPolicy
        )

        if next != motionProgress {
            motionProgress = next
        }
    }

    private func resolveInterruptionPolicy(
        from currentTarget: CGFloat,
        to nextTarget: CGFloat,
        shellState: ShellInteractionState
    ) -> IslandInterruptionPolicy {
        if shellState == .pinnedExpanded {
            return .holdPinned
        }

        if nextTarget < currentTarget {
            return .gentleSnapBack
        }

        return .preserveMomentum
    }

    private func updatePhaseForTargetChange() {
        if targetProgress <= 0.001, currentProgress > 0.01 {
            phase = .collapsing(origin: expansionOrigin)
            return
        }

        if targetProgress > currentProgress, currentProgress <= 0.01 {
            phase = .lifting(origin: expansionOrigin ?? .hover)
            return
        }

        updatePhaseFromProgress()
    }

    private func updatePhaseFromProgress() {
        let p = clamp(currentProgress)
        let origin = expansionOrigin ?? .hover

        if p <= 0.01 {
            phase = .collapsed
            return
        }

        if targetProgress <= 0.001, p > 0.01 {
            phase = .collapsing(origin: expansionOrigin)
            return
        }

        if p < 0.34 {
            phase = .lifting(origin: origin)
            return
        }

        if p < 0.68 {
            phase = .promoting(origin: origin)
            return
        }

        if p < 0.94 {
            phase = .contentReveal(origin: origin)
            return
        }

        phase = .expanded(origin: origin)
    }

    private func clamp(_ value: CGFloat) -> CGFloat {
        min(max(value, 0), 1)
    }
}
