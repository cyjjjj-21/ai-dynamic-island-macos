import CoreGraphics
import Observation

@MainActor
@Observable
final class ExpandedCardInteractionModel {
    private(set) var measuredCardHeight: CGFloat?
    var hoverRetentionPadding: CGFloat = 16
    var onInteractionBoundsChanged: (() -> Void)?

    var interactiveHeight: CGFloat? {
        guard let measuredCardHeight else {
            return nil
        }

        return measuredCardHeight + hoverRetentionPadding
    }

    func updateMeasuredCardHeight(_ height: CGFloat) {
        guard height > 0 else {
            return
        }

        let previousHeight = measuredCardHeight
        measuredCardHeight = height

        if previousHeight != height {
            onInteractionBoundsChanged?()
        }
    }
}
