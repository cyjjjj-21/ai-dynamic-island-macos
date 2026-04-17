import XCTest

@testable import AIIslandApp
@testable import AIIslandCore

final class AppReviewConfigurationTests: XCTestCase {
    func testParsesReviewStateAndFixtureScenarioFromEnvironment() {
        let configuration = AppReviewConfiguration.fromEnvironment([
            "AIISLAND_REVIEW_STATE": "pinnedExpanded",
            "AIISLAND_REVIEW_SCENARIO": FixtureScenario.threadOverflow.rawValue
        ])

        XCTAssertEqual(configuration?.shellState, .pinnedExpanded)
        XCTAssertEqual(configuration?.fixtureScenario, .threadOverflow)
    }

    func testIgnoresInvalidReviewValues() {
        let configuration = AppReviewConfiguration.fromEnvironment([
            "AIISLAND_REVIEW_STATE": "not-a-real-state",
            "AIISLAND_REVIEW_SCENARIO": "missing-scenario"
        ])

        XCTAssertNil(configuration)
    }

    func testParsesReviewStateAndFixtureScenarioFromCommandLineArguments() {
        let configuration = AppReviewConfiguration.fromLaunchContext(
            environment: [:],
            arguments: [
                "AIIslandApp",
                "--review-state", "pinnedExpanded",
                "--review-scenario", FixtureScenario.threadOverflow.rawValue,
            ]
        )

        XCTAssertEqual(configuration?.shellState, .pinnedExpanded)
        XCTAssertEqual(configuration?.fixtureScenario, .threadOverflow)
    }
}
