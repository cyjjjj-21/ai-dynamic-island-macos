import SwiftUI

import AIIslandCore

struct PromotionContainerView: View {
    @ObservedObject var coordinator: IslandMotionCoordinator
    let codex: AgentState
    let claude: AgentState

    var body: some View {
        let presentation = coordinator.presentation
        let cardOpacity = max(0, min(1, (presentation.revealOpacity - 0.08) / 0.22))
        let cardOffset = (1 - cardOpacity) * -8

        ZStack(alignment: .top) {
            promotedShellBackdrop(presentation: presentation)
            promotedShellBody(presentation: presentation)

            if cardOpacity > 0 {
                ExpandedIslandCardView(codex: codex, claude: claude)
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

    @ViewBuilder
    private func promotedShellBackdrop(presentation: IslandMotionPresentation) -> some View {
        if presentation.chromeOpacity > 0 {
            PromotedShellBand()
            .scaleEffect(x: presentation.shellScale, y: 1.0, anchor: .center)
            .offset(y: presentation.shellYOffset)
            .blur(radius: presentation.blurRadius)
            .opacity(presentation.chromeOpacity)
        }
    }

    @ViewBuilder
    private func promotedShellBody(presentation: IslandMotionPresentation) -> some View {
        if presentation.revealOpacity > 0 {
            HStack(spacing: IslandPalette.physicalNotchWidth) {
                RoundedRectangle(cornerRadius: IslandPalette.shellHeight / 2, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                IslandPalette.codexTint.opacity(0.10),
                                Color.white.opacity(0.08)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: IslandPalette.lobeWidth, height: presentation.revealHeight)

                RoundedRectangle(cornerRadius: IslandPalette.shellHeight / 2, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                IslandPalette.claudeTint.opacity(0.10),
                                Color.white.opacity(0.08)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: IslandPalette.lobeWidth, height: presentation.revealHeight)
            }
            .padding(.top, IslandPalette.shellHeight - presentation.revealHeight)
            .blur(radius: presentation.blurRadius * 0.8)
            .opacity(presentation.revealOpacity)
            .scaleEffect(x: presentation.shellScale, y: 1.0, anchor: .center)
            .offset(y: presentation.shellYOffset)
            .blendMode(.screen)
        }
    }
}

private struct PromotedShellBand: View {
    var body: some View {
        ShellBandShape()
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.14),
                        Color.white.opacity(0.05),
                        Color.black.opacity(0.10)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                style: FillStyle(eoFill: true)
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: IslandPalette.shellHeight / 2,
                    style: .continuous
                )
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
            }
            .overlay(alignment: .top) {
                PhysicalNotchCutoutShape()
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
                    .frame(
                        width: IslandPalette.physicalNotchWidth,
                        height: IslandPalette.physicalNotchHeight
                    )
            }
            .frame(width: IslandPalette.shellWidth, height: IslandPalette.shellHeight)
    }
}
