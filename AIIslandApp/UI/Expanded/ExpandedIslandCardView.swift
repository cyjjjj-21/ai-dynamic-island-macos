import SwiftUI

import AIIslandCore

struct ExpandedIslandCardView: View {
    let codex: AgentState
    let claude: AgentState

    var body: some View {
        VStack(spacing: 0) {
            AgentSectionView(presentation: AgentSectionPresentation(state: codex))
            Divider()
                .overlay(Color.white.opacity(0.08))
            AgentSectionView(presentation: AgentSectionPresentation(state: claude))
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .frame(width: IslandPalette.expandedCardWidth)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.116, green: 0.116, blue: 0.124),
                            Color(red: 0.084, green: 0.084, blue: 0.092),
                            Color(red: 0.058, green: 0.058, blue: 0.064)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
        .shadow(
            color: IslandPalette.shellEdgeHalo.opacity(0.95),
            radius: IslandPalette.shellEdgeHaloExpandedRadius,
            x: 0,
            y: 0
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Codex and Claude Code expanded status")
    }
}
