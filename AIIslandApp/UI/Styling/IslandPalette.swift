import SwiftUI

enum IslandPalette {
    static let diagnosticsUserDefaultsKey = "AIIslandDiagnosticsEnabled"
    static let hardware = IslandHardwareMetrics.detectFromScreen()
    static let shellWidth: CGFloat = hardware.collapsedShellWidth
    static let shellHeight: CGFloat = hardware.collapsedShellHeight
    static let scaleOverflowMargin: CGFloat = 8
    static let canvasWidth: CGFloat = max(shellWidth, hardware.expandedCardWidth) + scaleOverflowMargin * 2
    static let canvasHeight: CGFloat = hardware.expandedCanvasHeight
    static let lobeWidth: CGFloat = hardware.lobeWidth
    static let physicalNotchWidth: CGFloat = hardware.notchWidth
    static let physicalNotchHeight: CGFloat = hardware.bandHeight
    static let lobeFrameWidth: CGFloat = lobeWidth
    static let lobeSpacing: CGFloat = physicalNotchWidth
    static let expandedCardWidth: CGFloat = shellWidth
    static let expandedCardTopSpacing: CGFloat = 4
    static var diagnosticsEnabled: Bool {
        if ProcessInfo.processInfo.environment["AIISLAND_DIAGNOSTICS"] == "1" {
            return true
        }
        return UserDefaults.standard.bool(forKey: diagnosticsUserDefaultsKey)
    }
    static let expandedCardHitHeight: CGFloat = canvasHeight - shellHeight - expandedCardTopSpacing

    static let notchCenterXCorrection: CGFloat = 0
    static let shellOuterPadding: CGFloat = 0
    static let collapsedContentHorizontalPadding: CGFloat = 12
    static let collapsedContentVerticalPadding: CGFloat = 8
    static let collapsedLabelSpacing: CGFloat = 7
    static let mascotScale: CGFloat = 0.56

    static let shellFill = LinearGradient(
        colors: [
            Color.black,
            Color.black,
            Color.black
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    static let cardFill = LinearGradient(
        colors: [
            Color(red: 0.126, green: 0.124, blue: 0.130),
            Color(red: 0.098, green: 0.096, blue: 0.103),
            Color(red: 0.072, green: 0.072, blue: 0.078)
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    static let sectionFill = LinearGradient(
        colors: [
            Color.white.opacity(0.045),
            Color.white.opacity(0.020)
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    static let shellStroke = Color.clear
    static let shellTopHighlight = Color.clear
    static let shellBottomSheen = Color.clear
    static let cardStroke = Color.white.opacity(0.11)
    static let cardInnerStroke = Color.white.opacity(0.055)
    static let sectionStroke = Color.white.opacity(0.065)
    static let divider = Color.white.opacity(0.055)
    static let shellEdgeHalo = Color.black.opacity(0.18)
    static let shellEdgeHaloRadius: CGFloat = 8
    static let shellEdgeHaloExpandedRadius: CGFloat = 14

    static let primaryText = Color.white.opacity(0.95)
    static let secondaryText = Color.white.opacity(0.64)
    static let tertiaryText = Color.white.opacity(0.42)

    static let codexTint = Color(red: 0.53, green: 0.77, blue: 0.85)
    static let claudeTint = Color(red: 0.83, green: 0.66, blue: 0.64)
    static let attentionTint = Color(red: 0.86, green: 0.73, blue: 0.46)
    static let idleTint = Color.white.opacity(0.62)
    static let quotaFiveHourTint = Color(red: 0.52, green: 0.74, blue: 0.58)
    static let quotaWeeklyTint = Color(red: 0.32, green: 0.52, blue: 0.34)

    static let sectionTitleFont = Font.system(size: 13, weight: .semibold, design: .rounded)
    static let sectionStatusFont = Font.system(size: 9, weight: .semibold, design: .rounded)
    static let taskTitleFont = Font.system(size: 11.5, weight: .semibold, design: .default)
    static let primaryThreadTitleFont = Font.system(size: 11.6, weight: .semibold, design: .default)
    static let secondaryThreadTitleFont = Font.system(size: 11.0, weight: .semibold, design: .default)
    static let metadataFont = Font.system(size: 9, weight: .medium, design: .rounded)
    static let metadataStrongFont = Font.system(size: 9.5, weight: .semibold, design: .rounded)
    static let titleFont = taskTitleFont
    static let collapsedTitleFont = Font.system(size: 10.5, weight: .semibold, design: .rounded)
    static let badgeFont = Font.system(size: 8.5, weight: .semibold, design: .rounded)
    static let collapsedStatusDotSize: CGFloat = 5
    static let primaryThreadVerticalPadding: CGFloat = 7
    static let secondaryThreadVerticalPadding: CGFloat = 6

    static let badgePaddingH: CGFloat = 6
    static let badgePaddingV: CGFloat = 2
}
