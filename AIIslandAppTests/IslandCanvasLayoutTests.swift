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
}
