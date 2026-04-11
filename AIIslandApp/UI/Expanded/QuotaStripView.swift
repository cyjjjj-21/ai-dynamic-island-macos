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
                    ratio: presentation.fiveHourRatio,
                    tint: IslandPalette.codexTint
                )

                quotaBand(
                    title: "Weekly",
                    ratioCopy: presentation.weeklyCopy,
                    ratio: presentation.weeklyRatio,
                    tint: IslandPalette.claudeTint
                )
            }
        }
        .padding(.top, 1)
    }

    @ViewBuilder
    private func quotaBand(title: String, ratioCopy: String, ratio: Double?, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(IslandPalette.primaryText.opacity(0.92))

                Spacer(minLength: 0)

                Text(ratioCopy)
                    .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(IslandPalette.secondaryText)
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
