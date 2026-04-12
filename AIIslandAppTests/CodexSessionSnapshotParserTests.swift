import XCTest

@testable import AIIslandApp
@testable import AIIslandCore

final class CodexSessionSnapshotParserTests: XCTestCase {
    func testParseSnapshotExtractsModelContextAndQuotaFromTokenCount() {
        let jsonl = """
        {"timestamp":"2026-04-11T01:57:03.186Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":46618},"model_context_window":258400},"rate_limits":{"primary":{"used_percent":35.0},"secondary":{"used_percent":8.0}}}}
        {"timestamp":"2026-04-11T01:57:03.221Z","type":"turn_context","payload":{"turn_id":"turn-1","model":"gpt-5.4"}}
        """

        let snapshot = CodexSessionSnapshotParser.parse(
            jsonl,
            sessionID: "thread-1",
            fallbackTaskLabel: "Fallback"
        )

        XCTAssertEqual(snapshot.modelLabel, "gpt-5.4")
        XCTAssertEqual(try XCTUnwrap(snapshot.contextRatio), 46618.0 / 258400.0, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(snapshot.fiveHourRatio), 0.65, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(snapshot.weeklyRatio), 0.92, accuracy: 0.0001)
        XCTAssertEqual(snapshot.trustLevel, .eventDerived)
    }

    func testParseSnapshotPrefersLastTokenUsageForContextRatio() {
        let jsonl = """
        {"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":105033964},"last_token_usage":{"total_tokens":152634},"model_context_window":258400}}}
        """

        let snapshot = CodexSessionSnapshotParser.parse(
            jsonl,
            sessionID: "thread-last-token",
            fallbackTaskLabel: "Fallback"
        )

        XCTAssertEqual(try XCTUnwrap(snapshot.contextRatio), 152634.0 / 258400.0, accuracy: 0.0001)
    }

    func testParseSnapshotResolvesWorkingVsThinkingVsAttention() {
        let workingJSONL = """
        {"type":"event_msg","payload":{"type":"task_started","turn_id":"turn-1"}}
        {"type":"event_msg","payload":{"type":"exec_command_begin","call_id":"call-1","turn_id":"turn-1"}}
        """

        let thinkingJSONL = """
        {"type":"event_msg","payload":{"type":"task_started","turn_id":"turn-1"}}
        """

        let attentionJSONL = """
        {"type":"event_msg","payload":{"type":"agent_message","message":"Need your approval before I continue.","phase":"final_answer"}}
        """

        XCTAssertEqual(
            CodexSessionSnapshotParser.parse(workingJSONL, sessionID: "t1", fallbackTaskLabel: "A").state,
            .working
        )
        XCTAssertEqual(
            CodexSessionSnapshotParser.parse(thinkingJSONL, sessionID: "t2", fallbackTaskLabel: "B").state,
            .thinking
        )
        XCTAssertEqual(
            CodexSessionSnapshotParser.parse(attentionJSONL, sessionID: "t3", fallbackTaskLabel: "C").state,
            .attention
        )
    }

    func testParseSnapshotPrefersLatestUserPromptForTaskLabel() {
        let jsonl = """
        {"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"继续向下推进，打磨到除了数据接入之外，其他都完全可用的状态。"}]}}
        """

        let snapshot = CodexSessionSnapshotParser.parse(
            jsonl,
            sessionID: "thread-1",
            fallbackTaskLabel: "Thread title"
        )

        XCTAssertEqual(snapshot.taskLabel, "继续向下推进，打磨到除了数据接入之外，其他都完全可用的状态。")
    }

    func testParseSnapshotLeavesQuotaAndContextNilWithoutTokenCount() {
        let jsonl = """
        {"type":"event_msg","payload":{"type":"task_started","turn_id":"turn-1"}}
        {"type":"turn_context","payload":{"turn_id":"turn-1","model":"gpt-5.4-mini"}}
        """

        let snapshot = CodexSessionSnapshotParser.parse(
            jsonl,
            sessionID: "thread-2",
            fallbackTaskLabel: "Thread title"
        )

        XCTAssertEqual(snapshot.modelLabel, "gpt-5.4-mini")
        XCTAssertNil(snapshot.contextRatio)
        XCTAssertNil(snapshot.fiveHourRatio)
        XCTAssertNil(snapshot.weeklyRatio)
        XCTAssertEqual(snapshot.trustLevel, .eventDerived)
    }

    func testParseSnapshotUsesFixtureBackedRealisticEventShapes() throws {
        let sessionJSONL = try fixtureText(named: "rollout-sample", ext: "jsonl")

        let snapshot = CodexSessionSnapshotParser.parse(
            sessionJSONL,
            sessionID: "fixture-thread",
            fallbackTaskLabel: "Fixture fallback"
        )

        XCTAssertFalse(snapshot.modelLabel.isEmpty)
        XCTAssertNotNil(snapshot.contextRatio)
        XCTAssertEqual(snapshot.state, .working)
    }

    private func fixtureText(named: String, ext: String) throws -> String {
        let bundle = Bundle(for: Self.self)
        let targetName = named + "." + ext

        if let direct = bundle.url(forResource: named, withExtension: ext) {
            return try String(contentsOf: direct, encoding: .utf8)
        }

        if let nested = bundle.url(forResource: named, withExtension: ext, subdirectory: "Fixtures/codex-live") {
            return try String(contentsOf: nested, encoding: .utf8)
        }

        let recursive = bundle.urls(forResourcesWithExtension: ext, subdirectory: nil)?
            .first(where: { $0.lastPathComponent == targetName })
        let url = try XCTUnwrap(recursive, "Missing fixture: \(targetName)")
        return try String(contentsOf: url, encoding: .utf8)
    }
}
