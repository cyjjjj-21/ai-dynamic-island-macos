import SwiftUI

struct QuotaStripView: View {
    let presentation: QuotaStripPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let availabilityCopy = presentation.availabilityCopy {
                HStack(spacing: 8) {
                    Capsule(style: .continuous)
                        .fill(IslandPalette.codexTint.opacity(0.18))
                        .frame(width: 14, height: 6)

                    Text(availabilityCopy)
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
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
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 0) {
                Text(title)
                    .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(IslandPalette.primaryText.opacity(0.92))

                Spacer(minLength: 8)

                Text(ratioCopy)
                    .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(IslandPalette.secondaryText)

                if let refreshCopy = refreshCopy {
                    Spacer(minLength: 12)

                    Text(refreshCopy)
                        .font(.system(size: 8, weight: .medium, design: .rounded))
                        .foregroundStyle(IslandPalette.secondaryText.opacity(0.8))
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }

            GeometryReader { proxy in
                let trackWidth = proxy.size.width
                let fillWidth = max(8, trackWidth * CGFloat(ratio ?? 0))

                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.05))
                        .frame(height: 3)

                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    tint.opacity(0.95),
                                    tint.opacity(0.45)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: ratio == nil ? 8 : fillWidth, height: 3)
                }
            }
            .frame(height: 3)
        }
    }
}
