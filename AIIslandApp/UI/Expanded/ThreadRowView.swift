import SwiftUI

import AIIslandCore

struct ThreadRowView: View {
    let presentation: ThreadRowPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(presentation.threadTitle)
                    .font(presentation.isPrimary ? IslandPalette.primaryThreadTitleFont : IslandPalette.secondaryThreadTitleFont)
                    .foregroundStyle(IslandPalette.primaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 0)

                Text(presentation.modelLabel)
                    .font(presentation.isPrimary ? IslandPalette.metadataStrongFont : IslandPalette.metadataFont)
                    .foregroundStyle(IslandPalette.primaryText.opacity(presentation.isPrimary ? 0.84 : 0.72))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: presentation.isPrimary ? 90 : 78, alignment: .trailing)
            }

            HStack(alignment: .center, spacing: 8) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(stateTint(for: presentation.state))
                        .frame(width: 5, height: 5)

                    Text(presentation.detailCopy)
                        .font(IslandPalette.metadataFont)
                        .foregroundStyle(stateTint(for: presentation.state).opacity(0.92))
                        .lineLimit(1)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    Capsule(style: .continuous)
                        .fill(stateTint(for: presentation.state).opacity(presentation.isPrimary ? 0.12 : 0.08))
                )

                Spacer(minLength: 0)

                HStack(spacing: 6) {
                    if let recencyCopy = presentation.recencyCopy {
                        Text(recencyCopy)
                            .font(IslandPalette.metadataFont)
                            .foregroundStyle(IslandPalette.tertiaryText)
                            .lineLimit(1)
                    }

                    Text(presentation.contextCopy)
                        .font(IslandPalette.metadataFont)
                        .foregroundStyle(IslandPalette.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
        }
        .padding(.horizontal, presentation.isPrimary ? 4 : 0)
        .padding(.vertical, presentation.isPrimary ? IslandPalette.primaryThreadVerticalPadding : IslandPalette.secondaryThreadVerticalPadding)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    presentation.isPrimary
                    ? stateTint(for: presentation.state).opacity(0.055)
                    : Color.clear
                )
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(presentation.threadTitle), \(presentation.detailCopy), \(presentation.modelLabel), \(presentation.contextCopy)\(presentation.recencyCopy.map { ", \($0)" } ?? "")"
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
