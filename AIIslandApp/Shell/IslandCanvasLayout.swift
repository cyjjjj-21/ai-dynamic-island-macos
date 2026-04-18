import CoreGraphics

import AIIslandCore

struct IslandCanvasLayout {
    let canvasSize: CGSize
    let shellSize: CGSize
    let shellHitRegion: IslandShellHitRegion
    let expandedCardSize: CGSize
    let expandedTopSpacing: CGFloat

    static let `default` = IslandCanvasLayout(
        canvasSize: CGSize(width: IslandPalette.canvasWidth, height: IslandPalette.canvasHeight),
        shellSize: CGSize(width: IslandPalette.shellWidth, height: IslandPalette.shellHeight),
        shellHitRegion: IslandShellHitRegion(
            shellSize: CGSize(width: IslandPalette.shellWidth, height: IslandPalette.shellHeight),
            notchAvoidanceWidth: IslandPalette.physicalNotchWidth,
            notchAvoidanceHeight: IslandPalette.physicalNotchHeight
        ),
        expandedCardSize: CGSize(
            width: IslandPalette.expandedCardWidth,
            height: IslandPalette.expandedCardHitHeight
        ),
        expandedTopSpacing: IslandPalette.expandedCardTopSpacing
    )

    var shellFrame: CGRect {
        CGRect(
            x: (canvasSize.width - shellSize.width) / 2,
            y: 0,
            width: shellSize.width,
            height: shellSize.height
        )
    }

    var expandedCardFrame: CGRect {
        CGRect(
            x: (canvasSize.width - expandedCardSize.width) / 2,
            y: shellFrame.maxY + expandedTopSpacing,
            width: expandedCardSize.width,
            height: expandedCardSize.height
        )
    }

    func expandedCardInteractiveFrame(height interactiveHeight: CGFloat?) -> CGRect {
        let frame = expandedCardFrame
        let resolvedHeight = interactiveHeight.map { min(frame.height, max(0, $0)) } ?? frame.height

        return CGRect(
            x: frame.minX,
            y: frame.minY,
            width: frame.width,
            height: resolvedHeight
        )
    }

    func containsShellPoint(_ point: CGPoint) -> Bool {
        guard shellFrame.contains(point) else {
            return false
        }

        let localPoint = CGPoint(
            x: point.x - shellFrame.minX,
            y: point.y - shellFrame.minY
        )
        return shellHitRegion.containsInteractivePoint(localPoint)
    }

    func containsPointer(
        _ point: CGPoint,
        shellState: ShellInteractionState,
        expandedCardInteractiveHeight: CGFloat? = nil
    ) -> Bool {
        if containsShellPoint(point) {
            return true
        }

        switch shellState {
        case .hoverExpanded, .pinnedExpanded:
            return expandedCardInteractiveFrame(height: expandedCardInteractiveHeight).contains(point)
        case .collapsing:
            return false
        case .collapsed:
            return false
        }
    }

    func containsExpandedCardInteractivePoint(
        _ point: CGPoint,
        expandedCardInteractiveHeight: CGFloat? = nil
    ) -> Bool {
        expandedCardInteractiveFrame(height: expandedCardInteractiveHeight).contains(point)
    }
}
