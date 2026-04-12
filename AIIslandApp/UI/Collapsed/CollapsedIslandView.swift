import SwiftUI

import AIIslandCore

struct CollapsedIslandView: View {
    let codex: AgentState
    let claude: AgentState

    var body: some View {
        let companionship = MascotCompanionship(
            leftBusy: codex.globalState.isBusyFamily,
            rightBusy: claude.globalState.isBusyFamily
        )

        ZStack {
            ShellBandChrome()

            HStack(spacing: IslandPalette.lobeSpacing) {
                AgentCollapsedLobe(
                    title: "Codex",
                    agent: codex,
                    tint: IslandPalette.codexTint,
                    mascot: AnyView(CodexMascotView(scale: IslandPalette.mascotScale)),
                    side: .left,
                    companionship: companionship
                )

                AgentCollapsedLobe(
                    title: "Claude Code",
                    agent: claude,
                    tint: IslandPalette.claudeTint,
                    mascot: AnyView(ClaudeMascotView(scale: IslandPalette.mascotScale)),
                    side: .right,
                    companionship: companionship
                )
            }
        }
        .frame(width: IslandPalette.shellWidth, height: IslandPalette.shellHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Codex and Claude Code status")
    }
}

private struct IslandCollapsedLobeChrome: View {
    var body: some View {
        EmptyView()
    }
}

private struct ShellBandChrome: View {
    var body: some View {
        ShellBandShape()
            .fill(IslandPalette.shellFill, style: FillStyle(eoFill: true))
            .overlay(alignment: .top) {
                PhysicalNotchCutoutShape()
                    .stroke(IslandPalette.shellStroke, lineWidth: 1)
                    .frame(
                        width: IslandPalette.physicalNotchWidth,
                        height: IslandPalette.physicalNotchHeight
                    )
            }
            .overlay(alignment: .top) {
                PhysicalNotchCutoutShape()
                    .stroke(IslandPalette.shellStroke, lineWidth: 1)
                    .frame(
                        width: IslandPalette.physicalNotchWidth,
                        height: IslandPalette.physicalNotchHeight
                    )
            }
            .overlay(alignment: .top) {
                HStack(spacing: IslandPalette.lobeSpacing) {
                    RoundedRectangle(cornerRadius: 0.5, style: .continuous)
                        .fill(IslandPalette.shellTopHighlight)
                        .frame(width: IslandPalette.lobeWidth - 18, height: 1)
                    RoundedRectangle(cornerRadius: 0.5, style: .continuous)
                        .fill(IslandPalette.shellTopHighlight)
                        .frame(width: IslandPalette.lobeWidth - 18, height: 1)
                }
                .padding(.top, 1)
            }
            .shadow(
                color: IslandPalette.shellEdgeHalo,
                radius: IslandPalette.shellEdgeHaloRadius,
                x: 0,
                y: 0
            )
            .frame(width: IslandPalette.shellWidth, height: IslandPalette.shellHeight)
    }
}

private struct AgentCollapsedLobe: View {
    let title: String
    let agent: AgentState
    let tint: Color
    let mascot: AnyView
    let side: MascotCompanionship.Side
    let companionship: MascotCompanionship

    private var badgeTint: Color {
        switch agent.globalState {
        case .idle:
            return tint.opacity(0.72)
        case .thinking:
            return tint.opacity(0.92)
        case .working:
            return tint.opacity(1.0)
        case .attention:
            return Color(red: 0.97, green: 0.80, blue: 0.45)
        case .offline:
            return IslandPalette.secondaryText
        }
    }

    var body: some View {
        HStack(spacing: IslandPalette.collapsedLabelSpacing) {
            TimelineView(.animation) { timeline in
                let style = companionship.style(for: side, timestamp: timeline.date.timeIntervalSinceReferenceDate)
                mascot
                    .opacity(agent.globalState == .offline ? 0.55 : style.opacity)
                    .offset(y: style.yOffset)
                    .scaleEffect(style.scale, anchor: .center)
            }
            .frame(width: 14, height: 14)

            Text(title)
                .font(IslandPalette.collapsedTitleFont)
                .foregroundStyle(
                    agent.globalState == .offline
                        ? IslandPalette.secondaryText
                        : IslandPalette.primaryText
                )
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer(minLength: 0)

            Circle()
                .fill(badgeTint)
                .frame(
                    width: IslandPalette.collapsedStatusDotSize,
                    height: IslandPalette.collapsedStatusDotSize
                )
        }
        .padding(.horizontal, IslandPalette.collapsedContentHorizontalPadding)
        .padding(.vertical, IslandPalette.collapsedContentVerticalPadding)
        .frame(width: IslandPalette.lobeWidth, height: IslandPalette.shellHeight)
    }
}

private struct MascotCompanionship {
    enum Side {
        case left
        case right
    }

    struct Style {
        let scale: CGFloat
        let yOffset: CGFloat
        let opacity: Double
    }

    let leftBusy: Bool
    let rightBusy: Bool

    func style(for side: Side, timestamp: TimeInterval) -> Style {
        let wave = (sin((timestamp * 2.2) + phaseOffset(for: side)) + 1) / 2

        if leftBusy && rightBusy {
            return Style(
                scale: 1.02 + (0.03 * wave),
                yOffset: -0.8 + (-0.4 * wave),
                opacity: 0.96
            )
        }

        if leftBusy || rightBusy {
            let sideBusy = side == .left ? leftBusy : rightBusy
            if sideBusy {
                return Style(
                    scale: 1.02 + (0.04 * wave),
                    yOffset: -0.9 + (-0.5 * wave),
                    opacity: 0.98
                )
            }

            return Style(
                scale: 1.0 + (0.015 * wave),
                yOffset: 0.1 - (0.3 * wave),
                opacity: 0.90
            )
        }

        return Style(
            scale: 1.0 + (0.015 * wave),
            yOffset: 0.2 - (0.4 * wave),
            opacity: 0.90
        )
    }

    private func phaseOffset(for side: Side) -> CGFloat {
        side == .left ? 0 : .pi
    }
}

private extension AgentGlobalState {
    var isBusyFamily: Bool {
        switch self {
        case .thinking, .working, .attention:
            return true
        case .idle, .offline:
            return false
        }
    }
}
