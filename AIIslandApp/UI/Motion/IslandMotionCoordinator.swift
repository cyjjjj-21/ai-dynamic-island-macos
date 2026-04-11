import Combine
import Foundation
import SwiftUI

import AIIslandCore

public enum IslandExpansionOrigin: String, Sendable {
    case hover
    case pinned
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

    public var isExpandedFamily: Bool {
        switch self {
        case .collapsed, .collapsing:
            return false
        case .lifting, .promoting, .contentReveal, .expanded:
            return true
        }
    }
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

    public static let collapsed = IslandMotionPresentation(
        phase: .collapsed,
        shellScale: 1.0,
        shellYOffset: 0,
        shellOpacity: 1.0,
        chromeOpacity: 0.0,
        sheenOpacity: 0.0,
        revealOpacity: 0.0,
        revealHeight: 0,
        blurRadius: 0
    )
}

@MainActor
public final class IslandMotionCoordinator: ObservableObject {
    @Published public private(set) var phase: IslandMotionPhase = .collapsed
    @Published public private(set) var targetShellState: ShellInteractionState = .collapsed
    @Published public private(set) var reducedMotionEnabled = false

    private var expansionOrigin: IslandExpansionOrigin?
    private var transitionTask: Task<Void, Never>?

    public init() {}

    public func configure(reducedMotionEnabled: Bool) {
        guard self.reducedMotionEnabled != reducedMotionEnabled else {
            return
        }

        self.reducedMotionEnabled = reducedMotionEnabled
    }

    public func apply(shellState: ShellInteractionState) {
        targetShellState = shellState

        switch shellState {
        case .collapsed:
            beginCollapse()
        case .hoverExpanded:
            beginExpansion(origin: .hover)
        case .pinnedExpanded:
            beginExpansion(origin: .pinned)
        case .collapsing:
            beginCollapse()
        }
    }

    public var presentation: IslandMotionPresentation {
        switch phase {
        case .collapsed:
            return .collapsed
        case let .lifting(origin):
            return presentation(
                phase: phase,
                origin: origin,
                shellScale: reducedMotionEnabled ? 1.004 : 1.006,
                shellYOffset: 0,
                chromeOpacity: reducedMotionEnabled ? 0.10 : 0.18,
                sheenOpacity: reducedMotionEnabled ? 0.06 : 0.12,
                revealOpacity: reducedMotionEnabled ? 0.04 : 0.07,
                revealHeight: reducedMotionEnabled ? 3 : 4,
                blurRadius: reducedMotionEnabled ? 0.2 : 0.4
            )
        case let .promoting(origin):
            return presentation(
                phase: phase,
                origin: origin,
                shellScale: reducedMotionEnabled ? 1.006 : 1.010,
                shellYOffset: 0,
                chromeOpacity: reducedMotionEnabled ? 0.22 : 0.36,
                sheenOpacity: reducedMotionEnabled ? 0.10 : 0.18,
                revealOpacity: reducedMotionEnabled ? 0.10 : 0.16,
                revealHeight: reducedMotionEnabled ? 4 : 6,
                blurRadius: reducedMotionEnabled ? 0.4 : 0.7
            )
        case let .contentReveal(origin):
            return presentation(
                phase: phase,
                origin: origin,
                shellScale: reducedMotionEnabled ? 1.008 : 1.014,
                shellYOffset: 0,
                chromeOpacity: reducedMotionEnabled ? 0.34 : 0.55,
                sheenOpacity: reducedMotionEnabled ? 0.16 : 0.28,
                revealOpacity: reducedMotionEnabled ? 0.18 : 0.34,
                revealHeight: reducedMotionEnabled ? 5 : 8,
                blurRadius: reducedMotionEnabled ? 0.5 : 0.9
            )
        case let .expanded(origin):
            return presentation(
                phase: phase,
                origin: origin,
                shellScale: reducedMotionEnabled ? 1.010 : 1.016,
                shellYOffset: 0,
                chromeOpacity: reducedMotionEnabled ? 0.42 : 0.70,
                sheenOpacity: reducedMotionEnabled ? 0.22 : 0.34,
                revealOpacity: reducedMotionEnabled ? 0.30 : 0.48,
                revealHeight: reducedMotionEnabled ? 6 : 10,
                blurRadius: reducedMotionEnabled ? 0.6 : 1.0
            )
        case let .collapsing(origin):
            return presentation(
                phase: phase,
                origin: origin ?? .hover,
                shellScale: reducedMotionEnabled ? 1.003 : 1.007,
                shellYOffset: 0,
                chromeOpacity: reducedMotionEnabled ? 0.08 : 0.16,
                sheenOpacity: reducedMotionEnabled ? 0.04 : 0.10,
                revealOpacity: reducedMotionEnabled ? 0.03 : 0.06,
                revealHeight: reducedMotionEnabled ? 2 : 3,
                blurRadius: reducedMotionEnabled ? 0.1 : 0.25
            )
        }
    }

    private func presentation(
        phase: IslandMotionPhase,
        origin: IslandExpansionOrigin,
        shellScale: CGFloat,
        shellYOffset: CGFloat,
        chromeOpacity: Double,
        sheenOpacity: Double,
        revealOpacity: Double,
        revealHeight: CGFloat,
        blurRadius: CGFloat
    ) -> IslandMotionPresentation {
        _ = origin
        return IslandMotionPresentation(
            phase: phase,
            shellScale: shellScale,
            shellYOffset: shellYOffset,
            shellOpacity: 1.0,
            chromeOpacity: chromeOpacity,
            sheenOpacity: sheenOpacity,
            revealOpacity: revealOpacity,
            revealHeight: revealHeight,
            blurRadius: blurRadius
        )
    }

    private func beginExpansion(origin: IslandExpansionOrigin) {
        transitionTask?.cancel()
        transitionTask = nil

        expansionOrigin = origin

        if phase == .collapsed || phaseIsCollapsing {
            transition(to: .lifting(origin: origin))
            startExpansionTimeline(origin: origin)
            return
        }

        if let currentOrigin = phase.origin, currentOrigin != origin {
            transition(to: phase.replacingOrigin(with: origin))
        }
    }

    private func beginCollapse() {
        transitionTask?.cancel()
        transitionTask = nil

        guard phase != .collapsed else {
            expansionOrigin = nil
            return
        }

        let origin = expansionOrigin ?? phase.origin
        transition(to: .collapsing(origin: origin))

        transitionTask = Task { [weak self] in
            guard let self else {
                return
            }

            let delay = self.reducedMotionEnabled ? 0.08 : 0.12
            try? await Task.sleep(nanoseconds: Self.nanoseconds(for: delay))
            if Task.isCancelled {
                return
            }

            await MainActor.run {
                self.finishCollapse()
            }
        }
    }

    private func startExpansionTimeline(origin: IslandExpansionOrigin) {
        transitionTask = Task { [weak self] in
            guard let self else {
                return
            }

            let steps = self.reducedMotionEnabled
                ? self.reducedExpansionSteps(origin: origin)
                : self.standardExpansionSteps(origin: origin)

            for step in steps {
                try? await Task.sleep(nanoseconds: Self.nanoseconds(for: step.delay))
                if Task.isCancelled {
                    return
                }

                await MainActor.run {
                    self.transition(to: step.phase)
                }
            }
        }
    }

    private func reducedExpansionSteps(origin: IslandExpansionOrigin) -> [MotionStep] {
        [
            MotionStep(phase: .contentReveal(origin: origin), delay: 0.08),
            MotionStep(phase: .expanded(origin: origin), delay: 0.12),
        ]
    }

    private func standardExpansionSteps(origin: IslandExpansionOrigin) -> [MotionStep] {
        [
            MotionStep(phase: .promoting(origin: origin), delay: 0.08),
            MotionStep(phase: .contentReveal(origin: origin), delay: 0.09),
            MotionStep(phase: .expanded(origin: origin), delay: 0.11),
        ]
    }

    private func transition(to newPhase: IslandMotionPhase) {
        let animation = animation(for: newPhase)
        withAnimation(animation) {
            phase = newPhase
        }
    }

    private func finishCollapse() {
        transitionTask?.cancel()
        transitionTask = nil
        expansionOrigin = nil

        withAnimation(animation(for: .collapsed)) {
            phase = .collapsed
        }
    }

    private func animation(for phase: IslandMotionPhase) -> Animation {
        let duration: Double

        switch phase {
        case .collapsed:
            duration = reducedMotionEnabled ? 0.10 : 0.14
        case .lifting:
            duration = reducedMotionEnabled ? 0.08 : 0.14
        case .promoting:
            duration = reducedMotionEnabled ? 0.08 : 0.12
        case .contentReveal:
            duration = reducedMotionEnabled ? 0.08 : 0.10
        case .expanded:
            duration = reducedMotionEnabled ? 0.08 : 0.10
        case .collapsing:
            duration = reducedMotionEnabled ? 0.08 : 0.11
        }

        return .easeOut(duration: duration)
    }

    private var phaseIsCollapsing: Bool {
        if case .collapsing = phase {
            return true
        }

        return false
    }

    private struct MotionStep {
        let phase: IslandMotionPhase
        let delay: TimeInterval
    }

    private static func nanoseconds(for interval: TimeInterval) -> UInt64 {
        UInt64((interval * 1_000_000_000).rounded())
    }
}

private extension IslandMotionPhase {
    func replacingOrigin(with origin: IslandExpansionOrigin) -> IslandMotionPhase {
        switch self {
        case .collapsed:
            return .collapsed
        case .lifting:
            return .lifting(origin: origin)
        case .promoting:
            return .promoting(origin: origin)
        case .contentReveal:
            return .contentReveal(origin: origin)
        case .expanded:
            return .expanded(origin: origin)
        case .collapsing:
            return .collapsing(origin: origin)
        }
    }
}
