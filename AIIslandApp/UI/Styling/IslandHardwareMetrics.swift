import AppKit
import CoreGraphics

struct IslandHardwareMetrics: Equatable, Sendable {
    let notchWidth: CGFloat
    let bandHeight: CGFloat
    let lobeWidth: CGFloat
    let expandedCardWidth: CGFloat
    let expandedCanvasHeight: CGFloat

    var collapsedShellWidth: CGFloat {
        notchWidth + (lobeWidth * 2)
    }

    var collapsedShellHeight: CGFloat {
        bandHeight
    }

    static let macBookPro14 = IslandHardwareMetrics(
        notchWidth: 193.549,
        bandHeight: 32.5,
        lobeWidth: 124,
        expandedCardWidth: 392,
        expandedCanvasHeight: 340
    )

    /// Detect actual notch geometry from the primary screen's auxiliary areas.
    /// Falls back to the static `macBookPro14` constant when the API is unavailable.
    static func detectFromScreen() -> IslandHardwareMetrics {
        let fallback = macBookPro14

        guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) else {
            return fallback
        }

        if #available(macOS 12.0, *) {
            if
                let leftArea = screen.auxiliaryTopLeftArea,
                let rightArea = screen.auxiliaryTopRightArea,
                !leftArea.isEmpty,
                !rightArea.isEmpty
            {
                let detectedNotchWidth = rightArea.minX - leftArea.maxX
                let detectedBandHeight = max(screen.safeAreaInsets.top, 0)

                guard detectedNotchWidth > 0, detectedBandHeight > 0 else {
                    return fallback
                }

                return IslandHardwareMetrics(
                    notchWidth: detectedNotchWidth,
                    bandHeight: detectedBandHeight,
                    lobeWidth: fallback.lobeWidth,
                    expandedCardWidth: fallback.expandedCardWidth,
                    expandedCanvasHeight: fallback.expandedCanvasHeight
                )
            }
        }

        return fallback
    }
}
