import XCTest
@testable import AIIslandCore

final class FixtureBundleLoaderTests: XCTestCase {
    private var fixtureURL: URL {
        get throws {
            try XCTUnwrap(
                FixtureBundleMarker.bundle.url(
                    forResource: "phase1-fixtures",
                    withExtension: "json"
                )
            )
        }
    }

    func testFixtureScenarioDeclaresAllCanonicalCases() {
        XCTAssertEqual(FixtureScenario.allCases.count, 12)
    }

    func testFixtureBundleLoadsAllRequiredScenarios() throws {
        let bundle = try FixtureBundleLoader.load(from: try fixtureURL)

        XCTAssertEqual(bundle.version, 1)

        let expected = Set(FixtureScenario.allCases.map(\.rawValue))
        XCTAssertEqual(Set(bundle.fixtures.keys), expected)
    }

    func testFixtureStoreResolvesInitialScenario() throws {
        let bundle = try FixtureBundleLoader.load(from: try fixtureURL)
        let store = try FixtureStore(bundle: bundle, initialScenario: .attentionNeeded)

        XCTAssertEqual(store.currentScenario, .attentionNeeded)
        XCTAssertEqual(store.currentFixtureName, FixtureScenario.attentionNeeded.rawValue)
        XCTAssertEqual(store.codex.globalState, .attention)
        XCTAssertEqual(store.claude.globalState, .idle)
    }

    func testFixtureStoreSwitchesScenario() throws {
        let bundle = try FixtureBundleLoader.load(from: try fixtureURL)
        let store = try FixtureStore(bundle: bundle)

        try store.setScenario(.claudeOffline)

        XCTAssertEqual(store.currentScenario, .claudeOffline)
        XCTAssertEqual(store.codex.globalState, .working)
        XCTAssertEqual(store.claude.globalState, .offline)
    }

    func testFixtureStoreThrowsWhenInitialScenarioIsMissing() {
        let bundle = FixtureBundle(
            version: 1,
            notes: "test",
            shellStates: [],
            fixtures: [:]
        )

        XCTAssertThrowsError(
            try FixtureStore(bundle: bundle, initialScenario: .bothIdle)
        ) { error in
            XCTAssertEqual(
                error as? FixtureStore.Error,
                .missingScenario(.bothIdle)
            )
        }
    }
}
