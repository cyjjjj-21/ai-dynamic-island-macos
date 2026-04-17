import XCTest

@testable import AIIslandApp

@MainActor
final class ExpandedIslandReviewLayoutTests: XCTestCase {
    func testThreadOverflowReviewFixtureShowsQuotaRefreshCopy() throws {
        let fixture = try XCTUnwrap(
            ReviewFixtureResolver.resolve(
                AppReviewConfiguration(
                    shellState: .pinnedExpanded,
                    fixtureScenario: .threadOverflow
                )
            )
        )

        let quotaPresentation = try XCTUnwrap(
            AgentSectionPresentation(state: fixture.codex).quotaPresentation
        )

        XCTAssertNotNil(quotaPresentation.fiveHourRefreshCopy)
        XCTAssertNotNil(quotaPresentation.weeklyRefreshCopy)
    }

    func testExpandedPinnedLayoutUsesRaisedCanvasAndMatchingHitRegion() {
        XCTAssertGreaterThanOrEqual(IslandPalette.canvasHeight, 620)
        XCTAssertGreaterThanOrEqual(IslandPalette.expandedCardHitHeight, 590)
        XCTAssertEqual(
            IslandPalette.expandedCardHitHeight,
            IslandPalette.canvasHeight - IslandPalette.shellHeight - IslandPalette.expandedCardTopSpacing
        )
    }
}
