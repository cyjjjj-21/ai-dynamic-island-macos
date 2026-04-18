import XCTest

@testable import AIIslandApp

@MainActor
final class ExpandedCardInteractionModelTests: XCTestCase {
    func testUpdateMeasuredCardHeightNotifiesOnMeaningfulChange() {
        let model = ExpandedCardInteractionModel()
        var callbackCount = 0

        model.onInteractionBoundsChanged = {
            callbackCount += 1
        }

        model.updateMeasuredCardHeight(220)
        model.updateMeasuredCardHeight(220)
        model.updateMeasuredCardHeight(236)
        model.updateMeasuredCardHeight(0)

        XCTAssertEqual(callbackCount, 2)
        XCTAssertEqual(model.measuredCardHeight, 236)
        XCTAssertEqual(model.interactiveHeight, 252)
    }
}
