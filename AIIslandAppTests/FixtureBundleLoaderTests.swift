import XCTest

final class FixtureBundleLoaderTests: XCTestCase {
    private var fixtureURL: URL {
        URL(fileURLWithPath: "/Users/chenyuanjie/developer/ai-dynamic-island-macos/AIIslandApp/Resources/Fixtures/phase1-fixtures.json")
    }

    func testFixtureScenarioDeclaresAllCanonicalCases() {
        XCTAssertEqual(FixtureScenario.allCases.count, 12)
    }

    func testFixtureBundleLoadsAllRequiredScenarios() throws {
        let bundle = try FixtureBundleLoader.load(from: fixtureURL)

        XCTAssertEqual(bundle.version, 1)

        let expected = Set(FixtureScenario.allCases.map(\.rawValue))
        XCTAssertEqual(Set(bundle.fixtures.keys), expected)
    }
}
