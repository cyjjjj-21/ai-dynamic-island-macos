import AppKit
import QuartzCore
import SwiftUI

import AIIslandCore

struct PromotionContainerView: View {
    @ObservedObject var coordinator: IslandMotionCoordinator
    let codex: AgentState
    let claude: AgentState
    let codexDiagnostics: AgentMonitorDiagnostics
    let claudeDiagnostics: AgentMonitorDiagnostics

    var body: some View {
        let presentation = coordinator.presentation
        let p = presentation.progress
        let cardOpacity = clamp((p - 0.34) / 0.58)
        let cardOffset = (1 - cardOpacity) * -10

        ZStack(alignment: .top) {
            CoreAnimationShellEffectsView(
                progress: p,
                interruptionPolicy: presentation.interruptionPolicy,
                codexState: codex.globalState,
                claudeState: claude.globalState
            )
            .frame(width: IslandPalette.canvasWidth, height: IslandPalette.canvasHeight, alignment: .top)

            if cardOpacity > 0 {
                ExpandedIslandCardView(
                    codex: codex,
                    claude: claude,
                    codexDiagnostics: codexDiagnostics,
                    claudeDiagnostics: claudeDiagnostics
                )
                .padding(.top, IslandPalette.shellHeight + IslandPalette.expandedCardTopSpacing)
                .offset(y: cardOffset)
                .opacity(cardOpacity)
            }

            CollapsedIslandView(codex: codex, claude: claude)
                .scaleEffect(x: presentation.shellScale, y: 1.0, anchor: .center)
                .offset(y: presentation.shellYOffset)
                .opacity(presentation.shellOpacity)
        }
        .frame(width: IslandPalette.canvasWidth, height: IslandPalette.canvasHeight, alignment: .top)
        .compositingGroup()
        .allowsHitTesting(false)
    }

    private func clamp(_ value: CGFloat) -> CGFloat {
        min(max(value, 0), 1)
    }
}

private struct CoreAnimationShellEffectsView: NSViewRepresentable {
    let progress: CGFloat
    let interruptionPolicy: IslandInterruptionPolicy
    let codexState: AgentGlobalState
    let claudeState: AgentGlobalState

    func makeNSView(context: Context) -> CoreAnimationShellEffectsNSView {
        CoreAnimationShellEffectsNSView(frame: NSRect(origin: .zero, size: CGSize(
            width: IslandPalette.canvasWidth,
            height: IslandPalette.canvasHeight
        )))
    }

    func updateNSView(_ view: CoreAnimationShellEffectsNSView, context: Context) {
        view.update(
            progress: progress,
            interruptionPolicy: interruptionPolicy,
            codexState: codexState,
            claudeState: claudeState
        )
    }
}

private final class CoreAnimationShellEffectsNSView: NSView {
    private let haloLayer = CAGradientLayer()
    private let leftRevealLayer = CAGradientLayer()
    private let rightRevealLayer = CAGradientLayer()
    private let bridgeGlowLayer = CAGradientLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = CALayer()
        layer?.masksToBounds = false
        configureLayers()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(
        progress: CGFloat,
        interruptionPolicy: IslandInterruptionPolicy,
        codexState: AgentGlobalState,
        claudeState: AgentGlobalState
    ) {
        let p = min(max(progress, 0), 1)
        let shellX = (IslandPalette.canvasWidth - IslandPalette.shellWidth) / 2
        let shellY = max(0, bounds.height - IslandPalette.shellHeight)
        let shellRect = CGRect(
            x: shellX,
            y: shellY,
            width: IslandPalette.shellWidth,
            height: IslandPalette.shellHeight
        )
        // reveal层只在expand接近完成时显示 (p > 0.8)，避免hover初期出现ghost条
        let glowActivation = p > 0.8 ? min(max((p - 0.8) / 0.2, 0), 1) : 0
        let maxRevealHeight: CGFloat = 10
        let revealHeight = maxRevealHeight * glowActivation
        // reveal层从壳顶部内部向下延伸，避免在壳外产生可见条
        let revealY = shellRect.minY
        let leftRect = CGRect(
            x: shellRect.minX,
            y: revealY,
            width: IslandPalette.lobeWidth,
            height: revealHeight
        )
        let rightRect = CGRect(
            x: shellRect.maxX - IslandPalette.lobeWidth,
            y: revealY,
            width: IslandPalette.lobeWidth,
            height: revealHeight
        )
        let bridgeRect = CGRect(
            x: shellRect.midX - 48,
            y: revealY + (revealHeight * 0.2),
            width: 96,
            height: max(1.5, revealHeight * 0.45)
        )

        let resonance = MascotResonanceMatrix.resolve(
            codexState: codexState,
            claudeState: claudeState,
            time: CACurrentMediaTime()
        )

        CATransaction.begin()
        CATransaction.setDisableActions(false)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        CATransaction.setAnimationDuration(animationDuration(for: interruptionPolicy))

        haloLayer.frame = shellRect.insetBy(dx: -4, dy: -2)
        haloLayer.opacity = Float(0.16 * p)

        leftRevealLayer.frame = leftRect
        leftRevealLayer.opacity = Float((0.42 * glowActivation) + (resonance.leftBoost * glowActivation))
        leftRevealLayer.cornerRadius = revealHeight > 0 ? IslandPalette.shellHeight / 2 : 0

        rightRevealLayer.frame = rightRect
        rightRevealLayer.opacity = Float((0.42 * glowActivation) + (resonance.rightBoost * glowActivation))
        rightRevealLayer.cornerRadius = revealHeight > 0 ? IslandPalette.shellHeight / 2 : 0

        bridgeGlowLayer.frame = bridgeRect
        bridgeGlowLayer.cornerRadius = bridgeRect.height / 2
        bridgeGlowLayer.opacity = Float((0.22 * glowActivation) * resonance.bridgeAlpha)

        CATransaction.commit()
    }

    private func configureLayers() {
        guard let layer else {
            return
        }

        haloLayer.colors = [
            NSColor.black.withAlphaComponent(0.30).cgColor,
            NSColor.black.withAlphaComponent(0.04).cgColor
        ]
        haloLayer.startPoint = CGPoint(x: 0.5, y: 0.0)
        haloLayer.endPoint = CGPoint(x: 0.5, y: 1.0)
        haloLayer.cornerRadius = IslandPalette.shellHeight / 2
        haloLayer.opacity = 0

        leftRevealLayer.colors = [
            NSColor(calibratedRed: 0.58, green: 0.86, blue: 0.96, alpha: 0.88).cgColor,
            NSColor.white.withAlphaComponent(0.10).cgColor
        ]
        leftRevealLayer.startPoint = CGPoint(x: 0.0, y: 0.0)
        leftRevealLayer.endPoint = CGPoint(x: 1.0, y: 1.0)
        leftRevealLayer.opacity = 0

        rightRevealLayer.colors = [
            NSColor(calibratedRed: 0.94, green: 0.66, blue: 0.67, alpha: 0.88).cgColor,
            NSColor.white.withAlphaComponent(0.10).cgColor
        ]
        rightRevealLayer.startPoint = CGPoint(x: 0.0, y: 0.0)
        rightRevealLayer.endPoint = CGPoint(x: 1.0, y: 1.0)
        rightRevealLayer.opacity = 0

        bridgeGlowLayer.colors = [
            NSColor.white.withAlphaComponent(0.35).cgColor,
            NSColor.white.withAlphaComponent(0.0).cgColor
        ]
        bridgeGlowLayer.startPoint = CGPoint(x: 0.5, y: 0.0)
        bridgeGlowLayer.endPoint = CGPoint(x: 0.5, y: 1.0)
        bridgeGlowLayer.opacity = 0

        layer.addSublayer(haloLayer)
        layer.addSublayer(leftRevealLayer)
        layer.addSublayer(rightRevealLayer)
        layer.addSublayer(bridgeGlowLayer)
    }

    private func animationDuration(for policy: IslandInterruptionPolicy) -> CFTimeInterval {
        switch policy {
        case .preserveMomentum:
            return 0.10
        case .gentleSnapBack:
            return 0.14
        case .holdPinned:
            return 0.09
        }
    }
}

private struct MascotResonanceMatrix {
    let leftBoost: Double
    let rightBoost: Double
    let bridgeAlpha: Double

    static func resolve(
        codexState: AgentGlobalState,
        claudeState: AgentGlobalState,
        time: CFTimeInterval
    ) -> Self {
        let codexBusy = codexState == .thinking || codexState == .working || codexState == .attention
        let claudeBusy = claudeState == .thinking || claudeState == .working || claudeState == .attention
        let wave = (sin(time * 2.4) + 1) / 2
        let counterWave = (sin((time * 2.4) + .pi) + 1) / 2

        if codexBusy && claudeBusy {
            let sync = 0.08 + (0.07 * wave)
            return Self(leftBoost: sync, rightBoost: sync, bridgeAlpha: 1.0)
        }

        if codexBusy {
            return Self(leftBoost: 0.10 + (0.06 * wave), rightBoost: 0.03 + (0.02 * counterWave), bridgeAlpha: 0.70)
        }

        if claudeBusy {
            return Self(leftBoost: 0.03 + (0.02 * wave), rightBoost: 0.10 + (0.06 * counterWave), bridgeAlpha: 0.70)
        }

        let rest = 0.02 + (0.015 * wave)
        return Self(leftBoost: rest, rightBoost: 0.02 + (0.015 * counterWave), bridgeAlpha: 0.45)
    }
}
