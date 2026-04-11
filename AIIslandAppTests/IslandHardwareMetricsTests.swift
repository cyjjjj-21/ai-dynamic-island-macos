import XCTest

@testable import AIIslandApp

final class IslandHardwareMetricsTests: XCTestCase {
    func testFourteenInchMacBookProMetricsMatchMeasuredHardwareBand() {
        let metrics = IslandHardwareMetrics.macBookPro14

        XCTAssertEqual(metrics.notchWidth, 193.549, accuracy: 0.1)
        XCTAssertEqual(metrics.bandHeight, 32.5, accuracy: 0.1)
        XCTAssertEqual(metrics.lobeWidth, 124, accuracy: 0.1)
        XCTAssertEqual(metrics.collapsedShellWidth, 441.549, accuracy: 0.1)
        XCTAssertEqual(metrics.collapsedShellHeight, 32.5, accuracy: 0.1)
    }
}
