import SwiftUI

import AIIslandCore

struct AgentSectionView: View {
    let presentation: AgentSectionPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(presentation.title)
                        .font(IslandPalette.sectionTitleFont)
                        .foregroundStyle(IslandPalette.primaryText)

                    Text(presentation.primaryStatusCopy)
                        .font(IslandPalette.sectionStatusFont)
                        .foregroundStyle(IslandPalette.secondaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                statusBadge
            }

            if let emptyStateCopy = presentation.emptyStateCopy {
                Text(emptyStateCopy)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(IslandPalette.secondaryText.opacity(0.88))
                    .padding(.top, 2)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(presentation.visibleThreads.enumerated()), id: \.element.id) { index, thread in
                        ThreadRowView(presentation: thread)

                        if index < presentation.visibleThreads.count - 1 {
                            Rectangle()
                                .fill(IslandPalette.divider)
                                .frame(height: 1)
                                .padding(.leading, 2)
                        }
                    }

                    if let overflowSummaryCopy = presentation.overflowSummaryCopy {
                        HStack {
                            Spacer(minLength: 0)
                            Text(overflowSummaryCopy)
                                .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                                .foregroundStyle(IslandPalette.tertiaryText)
                        }
                        .padding(.top, 5)
                    }
                }
            }

            if presentation.kind == .codex,
               let quotaPresentation = presentation.quotaPresentation {
                Rectangle()
                    .fill(IslandPalette.divider)
                    .frame(height: 1)

                QuotaStripView(presentation: quotaPresentation)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
    }

    private var statusBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(tint(for: presentation.globalState))
                .frame(width: 5, height: 5)

            Text(presentation.primaryStatusCopy)
                .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                .foregroundStyle(tint(for: presentation.globalState).opacity(0.92))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule(style: .continuous)
                .fill(tint(for: presentation.globalState).opacity(0.09))
        )
    }

    private func tint(for state: AgentGlobalState) -> Color {
        switch state {
        case .idle:
            return IslandPalette.idleTint
        case .thinking:
            return IslandPalette.claudeTint
        case .working:
            return IslandPalette.codexTint
        case .attention:
            return IslandPalette.attentionTint
        case .offline:
            return IslandPalette.secondaryText
        }
    }
}
