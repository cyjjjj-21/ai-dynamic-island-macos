import SwiftUI

struct QuotaStripView: View {
    let presentation: QuotaStripPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let availabilityCopy = presentation.availabilityCopy {
                HStack(spacing: 8) {
                    Capsule(style: .continuous)
                        .fill(IslandPalette.codexTint.opacity(0.18))
                        .frame(width: 14, height: 5)

                    Text(availabilityCopy)
                        .font(IslandPalette.metadataFont)
                        .foregroundStyle(IslandPalette.secondaryText)
                }
            } else {
                quotaBand(
                    title: "5h",
                    ratioCopy: presentation.fiveHourCopy,
                    refreshCopy: presentation.fiveHourRefreshCopy,
                    ratio: presentation.fiveHourRatio,
                    tint: IslandPalette.quotaFiveHourTint
                )

                quotaBand(
                    title: "Weekly",
                    ratioCopy: presentation.weeklyCopy,
                    refreshCopy: presentation.weeklyRefreshCopy,
                    ratio: presentation.weeklyRatio,
                    tint: IslandPalette.quotaWeeklyTint
                )
            }
        }
        .padding(.top, 1)
    }

    @ViewBuilder
    private func quotaBand(title: String, ratioCopy: String, refreshCopy: String?, ratio: Double?, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(IslandPalette.metadataStrongFont)
                    .foregroundStyle(IslandPalette.primaryText.opacity(0.9))
                    .frame(width: 44, alignment: .leading)

                Text(ratioCopy)
                    .font(IslandPalette.metadataStrongFont)
                    .foregroundStyle(IslandPalette.secondaryText)

                Spacer(minLength: 0)

                if let refreshCopy = refreshCopy {
                    Text(refreshCopy)
                        .font(.system(size: 8, weight: .medium, design: .rounded))
                        .foregroundStyle(IslandPalette.tertiaryText)
                        .lineLimit(1)
                }
            }

            GeometryReader { proxy in
                let trackWidth = proxy.size.width
                let fillWidth = max(8, trackWidth * CGFloat(ratio ?? 0))

                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.05))
                        .frame(height: 4)

                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    tint.opacity(0.88),
                                    tint.opacity(0.46)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: ratio == nil ? 8 : fillWidth, height: 4)
                }
            }
            .frame(height: 4)
        }
    }
}
