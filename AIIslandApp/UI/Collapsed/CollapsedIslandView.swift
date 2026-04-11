import SwiftUI

import AIIslandCore

struct CollapsedIslandView: View {
    let codex: AgentState
    let claude: AgentState

    var body: some View {
        ZStack {
            ShellBandChrome()

            HStack(spacing: IslandPalette.lobeSpacing) {
                AgentCollapsedLobe(
                    title: "Codex",
                    agent: codex,
                    tint: IslandPalette.codexTint,
                    mascot: AnyView(CodexMascotView(scale: IslandPalette.mascotScale))
                )

                AgentCollapsedLobe(
                    title: "Claude Code",
                    agent: claude,
                    tint: IslandPalette.claudeTint,
                    mascot: AnyView(ClaudeMascotView(scale: IslandPalette.mascotScale))
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
            .overlay {
                RoundedRectangle(
                    cornerRadius: IslandPalette.shellHeight / 2,
                    style: .continuous
                )
                .stroke(IslandPalette.shellStroke, lineWidth: 1)
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
            mascot
                .opacity(agent.globalState == .offline ? 0.55 : 1.0)

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
