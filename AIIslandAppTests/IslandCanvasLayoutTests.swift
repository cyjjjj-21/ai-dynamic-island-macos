import CoreGraphics
import XCTest

import AIIslandCore
@testable import AIIslandApp

final class IslandCanvasLayoutTests: XCTestCase {
    func testShellFrameRemainsPinnedToTopOfCanvas() {
        let layout = IslandCanvasLayout.default

        XCTAssertEqual(layout.shellFrame.minY, 0, accuracy: 0.1)
        XCTAssertEqual(layout.shellFrame.height, IslandPalette.hardware.bandHeight, accuracy: 0.1)
    }

    func testExpandedCardFrameSitsBelowShellBand() {
        let layout = IslandCanvasLayout.default

        XCTAssertGreaterThan(layout.expandedCardFrame.minY, layout.shellFrame.maxY)
        XCTAssertEqual(layout.expandedCardFrame.width, IslandPalette.expandedCardWidth, accuracy: 0.1)
    }

    func testCollapsedPointerRegionIgnoresExpandedCardArea() {
        let layout = IslandCanvasLayout.default
        let point = CGPoint(x: layout.expandedCardFrame.midX, y: layout.expandedCardFrame.midY)

        XCTAssertFalse(layout.containsPointer(point, shellState: .collapsed))
    }

    func testExpandedPointerRegionIncludesExpandedCardArea() {
        let layout = IslandCanvasLayout.default
        let point = CGPoint(x: layout.expandedCardFrame.midX, y: layout.expandedCardFrame.midY)

        XCTAssertTrue(layout.containsPointer(point, shellState: .hoverExpanded))
        XCTAssertTrue(layout.containsPointer(point, shellState: .pinnedExpanded))
    }

    func testExpandedPointerRegionIgnoresFarLowerCanvasArea() {
        let layout = IslandCanvasLayout.default
        let visibleCardHeight: CGFloat = 220
        let point = CGPoint(
            x: layout.expandedCardFrame.midX,
            y: layout.expandedCardFrame.maxY - 24
        )

        XCTAssertFalse(
            layout.containsPointer(
                point,
                shellState: .hoverExpanded,
                expandedCardInteractiveHeight: visibleCardHeight
            )
        )
        XCTAssertFalse(
            layout.containsPointer(
                point,
                shellState: .pinnedExpanded,
                expandedCardInteractiveHeight: visibleCardHeight
            )
        )
    }

    func testExpandedCardInteractivePointTracksMeasuredCardHeight() {
        let layout = IslandCanvasLayout.default
        let visibleCardHeight: CGFloat = 220
        let insidePoint = CGPoint(
            x: layout.expandedCardFrame.midX,
            y: layout.expandedCardFrame.minY + visibleCardHeight - 8
        )
        let belowPoint = CGPoint(
            x: layout.expandedCardFrame.midX,
            y: layout.expandedCardFrame.minY + visibleCardHeight + 40
        )

        XCTAssertTrue(
            layout.containsExpandedCardInteractivePoint(
                insidePoint,
                expandedCardInteractiveHeight: visibleCardHeight
            )
        )
        XCTAssertFalse(
            layout.containsExpandedCardInteractivePoint(
                belowPoint,
                expandedCardInteractiveHeight: visibleCardHeight
            )
        )
    }

    func testCollapsingPointerRegionDoesNotReopenFromExpandedCardArea() {
        let layout = IslandCanvasLayout.default
        let point = CGPoint(x: layout.expandedCardFrame.midX, y: layout.expandedCardFrame.midY)

        XCTAssertFalse(layout.containsPointer(point, shellState: .collapsing))
    }
}
