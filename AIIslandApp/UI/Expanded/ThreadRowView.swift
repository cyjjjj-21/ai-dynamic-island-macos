import SwiftUI

import AIIslandCore

struct ThreadRowView: View {
    let presentation: ThreadRowPresentation

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(presentation.taskLabel)
                    .font(IslandPalette.titleFont)
                    .foregroundStyle(IslandPalette.primaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(presentation.stateCopy)
                    .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(IslandPalette.secondaryText.opacity(0.82))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(presentation.modelLabel)
                .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                .foregroundStyle(IslandPalette.primaryText.opacity(0.88))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: 86, alignment: .leading)

            Text(presentation.contextCopy)
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(IslandPalette.secondaryText)
                .lineLimit(1)
                .frame(width: 74, alignment: .trailing)

            Circle()
                .fill(stateTint(for: presentation.state))
                .frame(width: 6, height: 6)
                .shadow(color: stateTint(for: presentation.state).opacity(0.18), radius: 2, x: 0, y: 0)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(presentation.taskLabel), \(presentation.modelLabel), \(presentation.contextCopy), \(presentation.stateCopy)"
        )
    }

    private func stateTint(for state: AgentGlobalState) -> Color {
        switch state {
        case .idle:
            return IslandPalette.idleTint
        case .thinking:
            return IslandPalette.claudeTint.opacity(0.95)
        case .working:
            return IslandPalette.codexTint.opacity(0.95)
        case .attention:
            return Color(red: 0.97, green: 0.80, blue: 0.45)
        case .offline:
            return IslandPalette.secondaryText
        }
    }
}
