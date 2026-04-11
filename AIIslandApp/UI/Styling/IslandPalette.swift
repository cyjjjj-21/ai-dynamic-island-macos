import SwiftUI

enum IslandPalette {
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
    static let expandedCardHitHeight: CGFloat = 220

    static let notchCenterXCorrection: CGFloat = 0
    static let shellOuterPadding: CGFloat = 0
    static let collapsedContentHorizontalPadding: CGFloat = 12
    static let collapsedContentVerticalPadding: CGFloat = 8
    static let collapsedLabelSpacing: CGFloat = 7
    static let mascotScale: CGFloat = 0.56

    static let shellFill = LinearGradient(
        colors: [
            Color(red: 0.160, green: 0.160, blue: 0.168),
            Color(red: 0.094, green: 0.094, blue: 0.102),
            Color(red: 0.058, green: 0.058, blue: 0.063)
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    static let shellStroke = Color.white.opacity(0.10)
    static let shellTopHighlight = Color.white.opacity(0.06)
    static let shellEdgeHalo = Color.black.opacity(0.16)
    static let shellEdgeHaloRadius: CGFloat = 5
    static let shellEdgeHaloExpandedRadius: CGFloat = 6

    static let primaryText = Color.white.opacity(0.94)
    static let secondaryText = Color.white.opacity(0.60)

    static let codexTint = Color(red: 0.58, green: 0.86, blue: 0.96)
    static let claudeTint = Color(red: 0.94, green: 0.66, blue: 0.67)
    static let idleTint = Color.white.opacity(0.70)

    static let titleFont = Font.system(size: 11, weight: .semibold, design: .rounded)
    static let collapsedTitleFont = Font.system(size: 10.5, weight: .semibold, design: .rounded)
    static let badgeFont = Font.system(size: 8.5, weight: .semibold, design: .rounded)
    static let collapsedStatusDotSize: CGFloat = 5

    static let badgePaddingH: CGFloat = 6
    static let badgePaddingV: CGFloat = 2
}
