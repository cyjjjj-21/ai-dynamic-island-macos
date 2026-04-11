import SwiftUI

import AIIslandCore

struct AgentSectionView: View {
    let presentation: AgentSectionPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(presentation.title)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(IslandPalette.primaryText)

                    Text(presentation.primaryStatusCopy)
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(IslandPalette.secondaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }

            if presentation.kind == .codex,
               let quotaPresentation = presentation.quotaPresentation {
                QuotaStripView(presentation: quotaPresentation)
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
                            Divider()
                                .overlay(IslandPalette.shellStroke.opacity(0.32))
                        }
                    }

                    if let overflowSummaryCopy = presentation.overflowSummaryCopy {
                        HStack {
                            Spacer(minLength: 0)
                            Text(overflowSummaryCopy)
                                .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                                .foregroundStyle(IslandPalette.secondaryText)
                        }
                        .padding(.top, 5)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }
}
