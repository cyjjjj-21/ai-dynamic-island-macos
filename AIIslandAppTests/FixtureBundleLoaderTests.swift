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

    func testFixtureStoreEnumeratesOnlyScenariosPresentInBundleInCanonicalOrder() throws {
        let bundle = try FixtureBundleLoader.load(from: try fixtureURL)
        let filteredBundle = FixtureBundle(
            version: bundle.version,
            notes: bundle.notes,
            shellStates: bundle.shellStates,
            fixtures: [
                FixtureScenario.claudeOffline.rawValue: try XCTUnwrap(
                    bundle.fixtures[FixtureScenario.claudeOffline.rawValue]
                ),
                FixtureScenario.bothIdle.rawValue: try XCTUnwrap(
                    bundle.fixtures[FixtureScenario.bothIdle.rawValue]
                )
            ]
        )

        let store = try FixtureStore(bundle: filteredBundle)

        XCTAssertEqual(store.allScenarios, [.bothIdle, .claudeOffline])
    }

    func testFixtureBundleLoadsAllRequiredScenarios() throws {
        let bundle = try FixtureBundleLoader.load(from: try fixtureURL)

        XCTAssertEqual(bundle.version, 1)

        let expected = Set(FixtureScenario.allCases.map(\.rawValue))
        XCTAssertEqual(Set(bundle.fixtures.keys), expected)
        XCTAssertEqual(
            bundle.shellStates,
            ["collapsed", "hoverExpanded", "pinnedExpanded", "collapsing"]
        )
    }

    func testFixtureBundleRespectsAgentKindsAndRatioBounds() throws {
        let bundle = try FixtureBundleLoader.load(from: try fixtureURL)

        for fixture in bundle.fixtures.values {
            XCTAssertEqual(fixture.codex.kind, .codex)
            XCTAssertEqual(fixture.claude.kind, .claude)

            XCTAssertTrue(
                ratioValues(in: fixture.codex).allSatisfy { 0.0 ... 1.0 ~= $0 }
            )
            XCTAssertTrue(
                ratioValues(in: fixture.claude).allSatisfy { 0.0 ... 1.0 ~= $0 }
            )
        }
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

    func testAgentThreadDecodesLegacyTaskLabelOnlyShape() throws {
        let data = Data(
            """
            {
              "id": "thread-legacy",
              "taskLabel": "旧版线程标题",
              "modelLabel": "gpt-5.4",
              "contextRatio": 0.42,
              "state": "working"
            }
            """.utf8
        )

        let thread = try JSONDecoder().decode(AgentThread.self, from: data)

        XCTAssertEqual(thread.id, "thread-legacy")
        XCTAssertEqual(thread.title, "旧版线程标题")
        XCTAssertNil(thread.detail)
        XCTAssertNil(thread.workspaceLabel)
        XCTAssertEqual(thread.modelLabel, "gpt-5.4")
        XCTAssertEqual(try XCTUnwrap(thread.contextRatio), 0.42, accuracy: 0.0001)
        XCTAssertEqual(thread.state, .working)
        XCTAssertNil(thread.lastUpdatedAt)
        XCTAssertEqual(thread.titleSource, .unknown)
    }

    func testAgentThreadStillEncodesLegacyTaskLabelForCompatibility() throws {
        let thread = AgentThread(
            id: "thread-legacy",
            title: "新版线程标题",
            detail: "执行工具中",
            workspaceLabel: "ai-dynamic-island-macos",
            modelLabel: "gpt-5.4",
            contextRatio: 0.42,
            state: .working,
            lastUpdatedAt: nil,
            titleSource: .codexPromptSummary
        )

        let payload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(thread)) as? [String: Any]
        )

        XCTAssertEqual(payload["title"] as? String, "新版线程标题")
        XCTAssertEqual(payload["taskLabel"] as? String, "新版线程标题")
    }

    private func ratioValues(in state: AgentState) -> [Double] {
        let quotaRatios = [
            state.quota?.fiveHourRatio,
            state.quota?.weeklyRatio
        ]
        let threadRatios = state.threads.compactMap(\.contextRatio)
        return quotaRatios.compactMap { $0 } + threadRatios
    }
}
