import SwiftUI

import AIIslandCore

struct ThreadRowView: View {
    let presentation: ThreadRowPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(presentation.taskLabel)
                    .font(IslandPalette.taskTitleFont)
                    .foregroundStyle(IslandPalette.primaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 0)

                Text(presentation.modelLabel)
                    .font(IslandPalette.metadataStrongFont)
                    .foregroundStyle(IslandPalette.primaryText.opacity(0.84))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: 92, alignment: .trailing)
            }

            HStack(alignment: .center, spacing: 8) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(stateTint(for: presentation.state))
                        .frame(width: 5, height: 5)

                    Text(presentation.stateCopy)
                        .font(IslandPalette.metadataFont)
                        .foregroundStyle(stateTint(for: presentation.state).opacity(0.92))
                        .lineLimit(1)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    Capsule(style: .continuous)
                        .fill(stateTint(for: presentation.state).opacity(0.08))
                )

                Spacer(minLength: 0)

                Text(presentation.contextCopy)
                    .font(IslandPalette.metadataFont)
                    .foregroundStyle(IslandPalette.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .padding(.vertical, 8)
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
            return IslandPalette.attentionTint
        case .offline:
            return IslandPalette.secondaryText
        }
    }
}
