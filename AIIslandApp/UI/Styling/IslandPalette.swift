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
    static let expandedCardHitHeight: CGFloat = 220

    static let notchCenterXCorrection: CGFloat = 0
    static let shellOuterPadding: CGFloat = 0
    static let collapsedContentHorizontalPadding: CGFloat = 12
    static let collapsedContentVerticalPadding: CGFloat = 8
    static let collapsedLabelSpacing: CGFloat = 7
    static let mascotScale: CGFloat = 0.56

    static let shellFill = LinearGradient(
        colors: [Color.black, Color.black],
        startPoint: .top,
        endPoint: .bottom
    )

    static let shellStroke = Color.white.opacity(0.08)
    static let shellTopHighlight = Color.clear
    static let shellEdgeHalo = Color.black.opacity(0.16)
    static let shellEdgeHaloRadius: CGFloat = 5
    static let shellEdgeHaloExpandedRadius: CGFloat = 6

    static let primaryText = Color.white.opacity(0.94)
    static let secondaryText = Color.white.opacity(0.60)

    static let codexTint = Color(red: 0.58, green: 0.86, blue: 0.96)
    static let claudeTint = Color(red: 0.94, green: 0.66, blue: 0.67)
    static let idleTint = Color.white.opacity(0.70)
    static let quotaFiveHourTint = Color(red: 0.62, green: 0.90, blue: 0.66)
    static let quotaWeeklyTint = Color(red: 0.18, green: 0.62, blue: 0.32)

    static let titleFont = Font.system(size: 11, weight: .semibold, design: .rounded)
    static let collapsedTitleFont = Font.system(size: 10.5, weight: .semibold, design: .rounded)
    static let badgeFont = Font.system(size: 8.5, weight: .semibold, design: .rounded)
    static let collapsedStatusDotSize: CGFloat = 5

    static let badgePaddingH: CGFloat = 6
    static let badgePaddingV: CGFloat = 2
}
