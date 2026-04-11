import XCTest

@testable import AIIslandApp
@testable import AIIslandCore

@MainActor
final class CodexMonitorSmokeTests: XCTestCase {
    private let isoFormatter = ISO8601DateFormatter()

    override func setUp() {
        super.setUp()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    func testRefreshNowBuildsCodexStateFromSessionIndexSessionJSONLAndPresentation() throws {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sessionsDayURL = rootURL
            .appendingPathComponent("sessions", isDirectory: true)
            .appendingPathComponent("2026", isDirectory: true)
            .appendingPathComponent("04", isDirectory: true)
            .appendingPathComponent("11", isDirectory: true)

        try fileManager.createDirectory(at: sessionsDayURL, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: rootURL) }

        let sessionID = "thread-smoke"
        let sessionIndexJSONL = """
        {"id":"\(sessionID)","thread_name":"Build Codex live monitor","updated_at":"2026-04-11T10:05:00Z"}
        """
        try sessionIndexJSONL.data(using: .utf8)?.write(
            to: rootURL.appendingPathComponent("session_index.jsonl")
        )

        let sessionJSONL = """
        {"timestamp":"2026-04-11T10:04:58Z","type":"turn_context","payload":{"turn_id":"turn-1","model":"gpt-5.4"}}
        {"timestamp":"2026-04-11T10:04:59Z","type":"response_item","payload":{"type":"message","role":"user","turn_id":"turn-1","content":[{"type":"input_text","text":"把 codex monitor 接进 root view"}]}}
        {"timestamp":"2026-04-11T10:05:00Z","type":"event_msg","payload":{"type":"task_started","turn_id":"turn-1"}}
        {"timestamp":"2026-04-11T10:05:01Z","type":"event_msg","payload":{"type":"exec_command_begin","turn_id":"turn-1","call_id":"call-1"}}
        {"timestamp":"2026-04-11T10:05:02Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":62000},"model_context_window":248000},"rate_limits":{"primary":{"used_percent":40.0},"secondary":{"used_percent":12.5}}}}
        """
        try sessionJSONL.data(using: .utf8)?.write(
            to: sessionsDayURL.appendingPathComponent(sessionID + ".jsonl")
        )

        let monitor = CodexMonitor(codexHomePath: rootURL.path)
        monitor.refreshNow()

        let state = monitor.codexState
        let presentation = AgentSectionPresentation(state: state)

        XCTAssertTrue(state.online)
        XCTAssertEqual(state.availability, .available)
        XCTAssertEqual(state.globalState, .working)
        XCTAssertEqual(state.threads.count, 1)
        XCTAssertEqual(state.threads.first?.taskLabel, "把 codex monitor 接进 root view")
        XCTAssertEqual(state.threads.first?.modelLabel, "gpt-5.4")
        XCTAssertEqual(try XCTUnwrap(state.threads.first?.contextRatio), 0.25, accuracy: 0.0001)
        let quota = try XCTUnwrap(state.quota)
        XCTAssertEqual(try XCTUnwrap(quota.fiveHourRatio), 0.40, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(quota.weeklyRatio), 0.125, accuracy: 0.0001)

        XCTAssertEqual(presentation.primaryStatusCopy, "Working")
        XCTAssertEqual(presentation.visibleThreads.count, 1)
        XCTAssertEqual(presentation.visibleThreads.first?.modelLabel, "GPT-5.4")
        XCTAssertEqual(presentation.visibleThreads.first?.contextCopy, "Context 25%")
    }

    func testRefreshNowPublishesStatusUnavailableWhenOnlySessionIndexIsReadable() throws {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: rootURL) }

        let sessionIndexJSONL = """
        {"id":"thread-a","thread_name":"Fallback thread A","updated_at":"2026-04-11T10:10:00Z"}
        {"id":"thread-b","thread_name":"Fallback thread B","updated_at":"2026-04-11T10:09:00Z"}
        """
        try sessionIndexJSONL.data(using: .utf8)?.write(
            to: rootURL.appendingPathComponent("session_index.jsonl")
        )

        let monitor = CodexMonitor(codexHomePath: rootURL.path)
        monitor.refreshNow()

        let state = monitor.codexState
        let presentation = AgentSectionPresentation(state: state)

        XCTAssertTrue(state.online)
        XCTAssertEqual(state.availability, .statusUnavailable)
        XCTAssertEqual(state.globalState, .idle)
        XCTAssertEqual(state.threads.count, 2)
        XCTAssertEqual(state.quota?.availability, .unavailable)
        XCTAssertEqual(presentation.primaryStatusCopy, "Status unavailable")
    }

    func testRefreshNowFallsBackToOfflineWhenCodexRootHasNoReadableData() throws {
        let fileManager = FileManager.default
        let emptyTempRoot = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: emptyTempRoot, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: emptyTempRoot) }

        let monitor = CodexMonitor(codexHomePath: emptyTempRoot.path)
        monitor.refreshNow()

        XCTAssertFalse(monitor.codexState.online)
        XCTAssertEqual(monitor.codexState.globalState, .offline)
        XCTAssertEqual(
            AgentSectionPresentation(state: monitor.codexState).primaryStatusCopy,
            "Not running"
        )
    }

    func testRefreshNowIgnoresStaleActiveThreadSnapshots() throws {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sessionsDayURL = rootURL
            .appendingPathComponent("sessions", isDirectory: true)
            .appendingPathComponent("2026", isDirectory: true)
            .appendingPathComponent("04", isDirectory: true)
            .appendingPathComponent("11", isDirectory: true)

        try fileManager.createDirectory(at: sessionsDayURL, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: rootURL) }

        let staleID = "thread-stale"
        let freshID = "thread-fresh"
        let sessionIndexJSONL = """
        {"id":"\(staleID)","thread_name":"Course correction for Task 1 based on...","updated_at":"2026-04-09T15:05:00Z"}
        {"id":"\(freshID)","thread_name":"你运行一下app我来看看效果","updated_at":"2026-04-11T15:42:00Z"}
        """
        try sessionIndexJSONL.data(using: .utf8)?.write(
            to: rootURL.appendingPathComponent("session_index.jsonl")
        )

        let staleJSONL = """
        {"timestamp":"2026-04-09T15:05:00Z","type":"turn_context","payload":{"turn_id":"turn-stale","model":"gpt-5.4"}}
        {"timestamp":"2026-04-09T15:05:01Z","type":"response_item","payload":{"type":"message","role":"user","turn_id":"turn-stale","content":[{"type":"input_text","text":"Course correction for Task 1 based on..."}]}}
        {"timestamp":"2026-04-09T15:05:02Z","type":"event_msg","payload":{"type":"task_started","turn_id":"turn-stale"}}
        """
        try staleJSONL.data(using: .utf8)?.write(
            to: sessionsDayURL.appendingPathComponent(staleID + ".jsonl")
        )

        let freshJSONL = """
        {"timestamp":"2026-04-11T15:42:01Z","type":"turn_context","payload":{"turn_id":"turn-fresh","model":"gpt-5.4"}}
        {"timestamp":"2026-04-11T15:42:02Z","type":"response_item","payload":{"type":"message","role":"user","turn_id":"turn-fresh","content":[{"type":"input_text","text":"你运行一下app我来看看效果"}]}}
        {"timestamp":"2026-04-11T15:42:03Z","type":"event_msg","payload":{"type":"task_started","turn_id":"turn-fresh"}}
        """
        try freshJSONL.data(using: .utf8)?.write(
            to: sessionsDayURL.appendingPathComponent(freshID + ".jsonl")
        )

        let monitor = CodexMonitor(codexHomePath: rootURL.path)
        monitor.refreshNow()

        let state = monitor.codexState
        XCTAssertEqual(state.threads.count, 1)
        XCTAssertEqual(state.threads.first?.id, freshID)
        XCTAssertEqual(state.threads.first?.taskLabel, "你运行一下app我来看看效果")
    }

    func testRefreshNowUsesThreadIDExtractedFromRolloutFilename() throws {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sessionsDayURL = rootURL
            .appendingPathComponent("sessions", isDirectory: true)
            .appendingPathComponent("2026", isDirectory: true)
            .appendingPathComponent("04", isDirectory: true)
            .appendingPathComponent("11", isDirectory: true)

        try fileManager.createDirectory(at: sessionsDayURL, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: rootURL) }

        let threadID = "019d7280-4a37-75a3-859a-29c3389b3832"
        let threadName = "当前灵动岛状态排查"
        let sessionIndexJSONL = """
        {"id":"\(threadID)","thread_name":"\(threadName)","updated_at":"2026-04-11T15:55:00Z"}
        """
        try sessionIndexJSONL.data(using: .utf8)?.write(
            to: rootURL.appendingPathComponent("session_index.jsonl")
        )

        let rolloutFilename = "rollout-2026-04-11T15-50-00-\(threadID).jsonl"
        let sessionJSONL = """
        {"timestamp":"2026-04-11T15:54:58Z","type":"turn_context","payload":{"turn_id":"turn-1","model":"gpt-5.4"}}
        {"timestamp":"2026-04-11T15:54:59Z","type":"event_msg","payload":{"type":"task_started","turn_id":"turn-1"}}
        """
        try sessionJSONL.data(using: .utf8)?.write(
            to: sessionsDayURL.appendingPathComponent(rolloutFilename)
        )

        let monitor = CodexMonitor(codexHomePath: rootURL.path)
        monitor.refreshNow()

        let thread = try XCTUnwrap(monitor.codexState.threads.first)
        XCTAssertEqual(thread.id, threadID)
        XCTAssertEqual(thread.taskLabel, threadName)
        XCTAssertEqual(thread.modelLabel, "gpt-5.4")
        XCTAssertEqual(thread.state, .thinking)
    }

    func testRefreshNowExpandsSessionTailWhenRecentChunkContainsTooFewLines() throws {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sessionsDayURL = rootURL
            .appendingPathComponent("sessions", isDirectory: true)
            .appendingPathComponent("2026", isDirectory: true)
            .appendingPathComponent("04", isDirectory: true)
            .appendingPathComponent("11", isDirectory: true)

        try fileManager.createDirectory(at: sessionsDayURL, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: rootURL) }

        let threadID = "019d7b83-6e2e-7a60-852d-d3cfc2fa54aa"
        let sessionIndexJSONL = """
        {"id":"\(threadID)","thread_name":"实时状态回归","updated_at":"2026-04-11T15:56:00Z"}
        """
        try sessionIndexJSONL.data(using: .utf8)?.write(
            to: rootURL.appendingPathComponent("session_index.jsonl")
        )

        let longMessage = String(repeating: "x", count: 16_000)
        var lines: [String] = [
            #"{"timestamp":"2026-04-11T15:55:01Z","type":"turn_context","payload":{"turn_id":"turn-1","model":"gpt-5.3-codex"}}"#,
            #"{"timestamp":"2026-04-11T15:55:02Z","type":"response_item","payload":{"type":"message","role":"user","turn_id":"turn-1","content":[{"type":"input_text","text":"确认 codex 实时状态"}]}}"#,
            #"{"timestamp":"2026-04-11T15:55:03Z","type":"event_msg","payload":{"type":"task_started","turn_id":"turn-1"}}"#
        ]
        for _ in 0..<40 {
            lines.append(
                #"{"timestamp":"2026-04-11T15:55:10Z","type":"event_msg","payload":{"type":"agent_message","message":""# +
                    longMessage +
                    #""}}"#
            )
        }
        let sessionJSONL = lines.joined(separator: "\n")
        try sessionJSONL.data(using: .utf8)?.write(
            to: sessionsDayURL.appendingPathComponent("rollout-2026-04-11T15-55-00-\(threadID).jsonl")
        )

        let monitor = CodexMonitor(codexHomePath: rootURL.path)
        monitor.refreshNow()

        let thread = try XCTUnwrap(monitor.codexState.threads.first)
        XCTAssertEqual(thread.taskLabel, "确认 codex 实时状态")
        XCTAssertEqual(thread.modelLabel, "gpt-5.3-codex")
        XCTAssertEqual(thread.state, .thinking)
    }

    func testRefreshNowHidesThreadAfterVisibleIdleWindowButKeepsAvailabilityAvailable() throws {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sessionsDayURL = rootURL
            .appendingPathComponent("sessions", isDirectory: true)
            .appendingPathComponent("2026", isDirectory: true)
            .appendingPathComponent("04", isDirectory: true)
            .appendingPathComponent("11", isDirectory: true)
        try fileManager.createDirectory(at: sessionsDayURL, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: rootURL) }

        let threadID = "thread-sunset-visible"
        let signalAt = Date().addingTimeInterval(-16 * 60)
        let signalTimestamp = isoFormatter.string(from: signalAt)
        let sessionIndexJSONL = """
        {"id":"\(threadID)","thread_name":"sunset visible","updated_at":"\(signalTimestamp)"}
        """
        try sessionIndexJSONL.data(using: .utf8)?.write(
            to: rootURL.appendingPathComponent("session_index.jsonl")
        )

        let sessionJSONL = """
        {"timestamp":"\(signalTimestamp)","type":"turn_context","payload":{"turn_id":"turn-1","model":"gpt-5.4"}}
        {"timestamp":"\(signalTimestamp)","type":"event_msg","payload":{"type":"task_started","turn_id":"turn-1"}}
        """
        try sessionJSONL.data(using: .utf8)?.write(
            to: sessionsDayURL.appendingPathComponent("rollout-2026-04-11T16-00-00-\(threadID).jsonl")
        )

        let monitor = CodexMonitor(codexHomePath: rootURL.path)
        monitor.refreshNow()

        XCTAssertEqual(monitor.codexState.availability, .available)
        XCTAssertEqual(monitor.codexState.globalState, .idle)
        XCTAssertEqual(monitor.codexState.threads.count, 0)
    }

    func testRefreshNowBecomesStatusUnavailableAfterLiveSignalWindowExpires() throws {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sessionsDayURL = rootURL
            .appendingPathComponent("sessions", isDirectory: true)
            .appendingPathComponent("2026", isDirectory: true)
            .appendingPathComponent("04", isDirectory: true)
            .appendingPathComponent("11", isDirectory: true)
        try fileManager.createDirectory(at: sessionsDayURL, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: rootURL) }

        let threadID = "thread-sunset-expired"
        let signalAt = Date().addingTimeInterval(-31 * 60)
        let signalTimestamp = isoFormatter.string(from: signalAt)
        let sessionIndexJSONL = """
        {"id":"\(threadID)","thread_name":"sunset expired","updated_at":"\(signalTimestamp)"}
        """
        try sessionIndexJSONL.data(using: .utf8)?.write(
            to: rootURL.appendingPathComponent("session_index.jsonl")
        )

        let sessionJSONL = """
        {"timestamp":"\(signalTimestamp)","type":"turn_context","payload":{"turn_id":"turn-1","model":"gpt-5.4"}}
        {"timestamp":"\(signalTimestamp)","type":"event_msg","payload":{"type":"task_started","turn_id":"turn-1"}}
        """
        try sessionJSONL.data(using: .utf8)?.write(
            to: sessionsDayURL.appendingPathComponent("rollout-2026-04-11T15-50-00-\(threadID).jsonl")
        )

        let monitor = CodexMonitor(codexHomePath: rootURL.path)
        monitor.refreshNow()

        XCTAssertEqual(monitor.codexState.availability, .statusUnavailable)
        XCTAssertEqual(monitor.codexState.globalState, .idle)
        XCTAssertEqual(monitor.codexState.threads.count, 0)
    }
}
