import CoreGraphics
import XCTest

@testable import AIIslandApp

final class IslandShellHitRegionTests: XCTestCase {
    func testPhysicalNotchGapIsNonInteractiveAcrossEntireBandHeight() {
        let metrics = IslandHardwareMetrics.macBookPro14
        let hitRegion = IslandShellHitRegion(
            shellSize: CGSize(width: metrics.collapsedShellWidth, height: metrics.collapsedShellHeight),
            notchAvoidanceWidth: metrics.notchWidth,
            notchAvoidanceHeight: metrics.bandHeight
        )

        XCTAssertFalse(hitRegion.containsInteractivePoint(CGPoint(x: metrics.collapsedShellWidth / 2, y: 2)))
        XCTAssertFalse(hitRegion.containsInteractivePoint(CGPoint(x: metrics.collapsedShellWidth / 2, y: 16)))
        XCTAssertFalse(hitRegion.containsInteractivePoint(CGPoint(x: metrics.collapsedShellWidth / 2, y: 30)))
    }

    func testSideLobesRemainInteractive() {
        let metrics = IslandHardwareMetrics.macBookPro14
        let hitRegion = IslandShellHitRegion(
            shellSize: CGSize(width: metrics.collapsedShellWidth, height: metrics.collapsedShellHeight),
            notchAvoidanceWidth: metrics.notchWidth,
            notchAvoidanceHeight: metrics.bandHeight
        )

        XCTAssertTrue(hitRegion.containsInteractivePoint(CGPoint(x: 28, y: 16)))
        XCTAssertTrue(hitRegion.containsInteractivePoint(CGPoint(x: metrics.collapsedShellWidth - 28, y: 16)))
    }

    func testInnerEdgesRemainSquareBeforeBottomCornerArcBegins() {
        let metrics = IslandHardwareMetrics.macBookPro14
        let hitRegion = IslandShellHitRegion(
            shellSize: CGSize(width: metrics.collapsedShellWidth, height: metrics.collapsedShellHeight),
            notchAvoidanceWidth: metrics.notchWidth,
            notchAvoidanceHeight: metrics.bandHeight
        )

        let leftInnerX = metrics.lobeWidth - 1
        let rightInnerX = metrics.lobeWidth + metrics.notchWidth + 1

        XCTAssertTrue(hitRegion.containsInteractivePoint(CGPoint(x: leftInnerX, y: 1)))
        XCTAssertTrue(hitRegion.containsInteractivePoint(CGPoint(x: rightInnerX, y: 1)))
        XCTAssertTrue(hitRegion.containsInteractivePoint(CGPoint(x: leftInnerX, y: 12)))
        XCTAssertTrue(hitRegion.containsInteractivePoint(CGPoint(x: rightInnerX, y: 12)))
    }

    func testBottomBandEatsIntoNotchCornerRadiusWithoutClosingTopGap() {
        let metrics = IslandHardwareMetrics.macBookPro14
        let hitRegion = IslandShellHitRegion(
            shellSize: CGSize(width: metrics.collapsedShellWidth, height: metrics.collapsedShellHeight),
            notchAvoidanceWidth: metrics.notchWidth,
            notchAvoidanceHeight: metrics.bandHeight
        )

        let probeX = metrics.lobeWidth + 6
        let justInsideTopGapFromLeft = CGPoint(x: probeX, y: 2)
        let justInsideBottomOverlapFromLeft = CGPoint(x: probeX, y: metrics.bandHeight - 2)

        XCTAssertFalse(hitRegion.containsInteractivePoint(justInsideTopGapFromLeft))
        XCTAssertTrue(hitRegion.containsInteractivePoint(justInsideBottomOverlapFromLeft))
    }

    func testShoulderStaysVerticalBeforeBottomCornerArcBegins() {
        let metrics = IslandHardwareMetrics.macBookPro14
        let hitRegion = IslandShellHitRegion(
            shellSize: CGSize(width: metrics.collapsedShellWidth, height: metrics.collapsedShellHeight),
            notchAvoidanceWidth: metrics.notchWidth,
            notchAvoidanceHeight: metrics.bandHeight
        )

        let probeX = metrics.lobeWidth + 6

        XCTAssertFalse(hitRegion.containsInteractivePoint(CGPoint(x: probeX, y: 12)))
        XCTAssertFalse(hitRegion.containsInteractivePoint(CGPoint(x: probeX, y: 20)))
        XCTAssertTrue(hitRegion.containsInteractivePoint(CGPoint(x: probeX, y: 30)))
    }
}
