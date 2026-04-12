import XCTest

@testable import AIIslandCore

final class MonitorFreshnessPolicyTests: XCTestCase {
    func testV02SmoothStageThresholds() {
        let policy = MonitorFreshnessPolicy.v02Smooth
        let now = Date()

        XCTAssertEqual(policy.stage(lastSignalAt: now.addingTimeInterval(-2 * 60), now: now), .live)
        XCTAssertEqual(policy.stage(lastSignalAt: now.addingTimeInterval(-10 * 60), now: now), .cooling)
        XCTAssertEqual(policy.stage(lastSignalAt: now.addingTimeInterval(-20 * 60), now: now), .recentIdle)
        XCTAssertEqual(policy.stage(lastSignalAt: now.addingTimeInterval(-40 * 60), now: now), .staleHidden)
        XCTAssertEqual(policy.stage(lastSignalAt: now.addingTimeInterval(-50 * 60), now: now), .expired)
    }

    func testFreshnessScoreDecreasesWithAge() {
        let policy = MonitorFreshnessPolicy.v02Smooth
        let now = Date()

        let fresh = policy.freshnessScore(lastSignalAt: now.addingTimeInterval(-60), now: now)
        let stale = policy.freshnessScore(lastSignalAt: now.addingTimeInterval(-30 * 60), now: now)

        XCTAssertGreaterThan(fresh, stale)
    }
}
