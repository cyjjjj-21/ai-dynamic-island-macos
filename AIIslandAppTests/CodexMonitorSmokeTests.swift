import XCTest

@testable import AIIslandApp
@testable import AIIslandCore

@MainActor
final class CodexMonitorSmokeTests: XCTestCase {
    private let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private func isoString(_ date: Date) -> String {
        isoFormatter.string(from: date)
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

        let baseTime = Date()
        let sessionID = "thread-smoke"
        let indexTimestamp = isoString(baseTime)
        let contextTimestamp = isoString(baseTime.addingTimeInterval(-2))
        let userMessageTimestamp = isoString(baseTime.addingTimeInterval(-1))
        let taskStartedTimestamp = isoString(baseTime)
        let commandBeginTimestamp = isoString(baseTime.addingTimeInterval(1))
        let tokenCountTimestamp = isoString(baseTime.addingTimeInterval(2))
        let sessionIndexJSONL = """
        {"id":"\(sessionID)","thread_name":"Build Codex live monitor","updated_at":"\(indexTimestamp)"}
        """
        try sessionIndexJSONL.data(using: .utf8)?.write(
            to: rootURL.appendingPathComponent("session_index.jsonl")
        )

        let sessionJSONL = """
        {"timestamp":"\(contextTimestamp)","type":"turn_context","payload":{"turn_id":"turn-1","model":"gpt-5.4"}}
        {"timestamp":"\(userMessageTimestamp)","type":"response_item","payload":{"type":"message","role":"user","turn_id":"turn-1","content":[{"type":"input_text","text":"把 codex monitor 接进 root view"}]}}
        {"timestamp":"\(taskStartedTimestamp)","type":"event_msg","payload":{"type":"task_started","turn_id":"turn-1"}}
        {"timestamp":"\(commandBeginTimestamp)","type":"event_msg","payload":{"type":"exec_command_begin","turn_id":"turn-1","call_id":"call-1"}}
        {"timestamp":"\(tokenCountTimestamp)","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":62000},"model_context_window":248000},"rate_limits":{"primary":{"used_percent":40.0},"secondary":{"used_percent":12.5}}}}
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
        XCTAssertEqual(try XCTUnwrap(quota.fiveHourRatio), 0.60, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(quota.weeklyRatio), 0.875, accuracy: 0.0001)

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

        let staleID = "019d7280-4a37-75a3-859a-29c3389b3831"
        let freshID = "019d7280-4a37-75a3-859a-29c3389b3832"
        let staleTime = Date().addingTimeInterval(-2 * 60 * 60)
        let freshTime = Date().addingTimeInterval(-60)
        let staleTimestamp = isoString(staleTime)
        let freshTimestamp = isoString(freshTime)
        let sessionIndexJSONL = """
        {"id":"\(staleID)","thread_name":"Course correction for Task 1 based on...","updated_at":"\(staleTimestamp)"}
        {"id":"\(freshID)","thread_name":"你运行一下app我来看看效果","updated_at":"\(freshTimestamp)"}
        """
        try sessionIndexJSONL.data(using: .utf8)?.write(
            to: rootURL.appendingPathComponent("session_index.jsonl")
        )

        let staleJSONL = """
        {"timestamp":"\(staleTimestamp)","type":"turn_context","payload":{"turn_id":"turn-stale","model":"gpt-5.4"}}
        {"timestamp":"\(isoString(staleTime.addingTimeInterval(1)))","type":"response_item","payload":{"type":"message","role":"user","turn_id":"turn-stale","content":[{"type":"input_text","text":"Course correction for Task 1 based on..."}]}}
        {"timestamp":"\(isoString(staleTime.addingTimeInterval(2)))","type":"event_msg","payload":{"type":"task_started","turn_id":"turn-stale"}}
        """
        let staleURL = sessionsDayURL.appendingPathComponent(staleID + ".jsonl")
        try staleJSONL.data(using: .utf8)?.write(to: staleURL)
        try fileManager.setAttributes(
            [.modificationDate: staleTime],
            ofItemAtPath: staleURL.path
        )

        let freshJSONL = """
        {"timestamp":"\(freshTimestamp)","type":"turn_context","payload":{"turn_id":"turn-fresh","model":"gpt-5.4"}}
        {"timestamp":"\(isoString(freshTime.addingTimeInterval(1)))","type":"response_item","payload":{"type":"message","role":"user","turn_id":"turn-fresh","content":[{"type":"input_text","text":"你运行一下app我来看看效果"}]}}
        {"timestamp":"\(isoString(freshTime.addingTimeInterval(2)))","type":"event_msg","payload":{"type":"task_started","turn_id":"turn-fresh"}}
        """
        let freshURL = sessionsDayURL.appendingPathComponent(freshID + ".jsonl")
        try freshJSONL.data(using: .utf8)?.write(to: freshURL)
        try fileManager.setAttributes(
            [.modificationDate: freshTime],
            ofItemAtPath: freshURL.path
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

        let baseTime = Date()
        let threadID = "019d7280-4a37-75a3-859a-29c3389b3832"
        let threadName = "当前灵动岛状态排查"
        let sessionIndexJSONL = """
        {"id":"\(threadID)","thread_name":"\(threadName)","updated_at":"\(isoString(baseTime))"}
        """
        try sessionIndexJSONL.data(using: .utf8)?.write(
            to: rootURL.appendingPathComponent("session_index.jsonl")
        )

        let rolloutFilename = "rollout-2026-04-11T15-50-00-\(threadID).jsonl"
        let sessionJSONL = """
        {"timestamp":"\(isoString(baseTime.addingTimeInterval(-2)))","type":"turn_context","payload":{"turn_id":"turn-1","model":"gpt-5.4"}}
        {"timestamp":"\(isoString(baseTime.addingTimeInterval(-1)))","type":"event_msg","payload":{"type":"task_started","turn_id":"turn-1"}}
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

        let baseTime = Date()
        let threadID = "019d7b83-6e2e-7a60-852d-d3cfc2fa54aa"
        let sessionIndexJSONL = """
        {"id":"\(threadID)","thread_name":"实时状态回归","updated_at":"\(isoString(baseTime))"}
        """
        try sessionIndexJSONL.data(using: .utf8)?.write(
            to: rootURL.appendingPathComponent("session_index.jsonl")
        )

        let longMessage = String(repeating: "x", count: 16_000)
        var lines: [String] = [
            #"{"timestamp":"\#(isoString(baseTime.addingTimeInterval(-2)))","type":"turn_context","payload":{"turn_id":"turn-1","model":"gpt-5.3-codex"}}"#,
            #"{"timestamp":"\#(isoString(baseTime.addingTimeInterval(-1)))","type":"response_item","payload":{"type":"message","role":"user","turn_id":"turn-1","content":[{"type":"input_text","text":"确认 codex 实时状态"}]}}"#,
            #"{"timestamp":"\#(isoString(baseTime))","type":"event_msg","payload":{"type":"task_started","turn_id":"turn-1"}}"#
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

    func testRefreshNowUsesRecentSessionFileModificationTimeToKeepIdleThreadVisible() throws {
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

        let threadID = "019d7280-4a37-75a3-859a-29c3389b3833"
        let signalAt = Date().addingTimeInterval(-26 * 60)
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
        {"timestamp":"\(signalTimestamp)","type":"event_msg","payload":{"type":"task_complete","turn_id":"turn-1"}}
        """
        let sessionURL = sessionsDayURL.appendingPathComponent("rollout-2026-04-11T16-00-00-\(threadID).jsonl")
        try sessionJSONL.data(using: .utf8)?.write(to: sessionURL)

        let monitor = CodexMonitor(codexHomePath: rootURL.path)
        monitor.refreshNow()

        XCTAssertEqual(monitor.codexState.availability, .available)
        XCTAssertEqual(monitor.codexState.globalState, .idle)
        XCTAssertEqual(monitor.codexState.threads.count, 1)
        XCTAssertEqual(monitor.codexState.threads.first?.id, threadID)
        XCTAssertEqual(monitor.codexState.threads.first?.state, .idle)
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
        let signalAt = Date().addingTimeInterval(-46 * 60)
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
        let sessionURL = sessionsDayURL.appendingPathComponent("rollout-2026-04-11T15-50-00-\(threadID).jsonl")
        try sessionJSONL.data(using: .utf8)?.write(to: sessionURL)
        try fileManager.setAttributes(
            [.modificationDate: signalAt],
            ofItemAtPath: sessionURL.path
        )

        let monitor = CodexMonitor(codexHomePath: rootURL.path)
        monitor.refreshNow()

        XCTAssertEqual(monitor.codexState.availability, .statusUnavailable)
        XCTAssertEqual(monitor.codexState.globalState, .idle)
        XCTAssertEqual(monitor.codexState.threads.count, 0)
    }

    func testRefreshNowUsesLastKnownModelWhenLatestSnapshotTemporarilyMissingModel() throws {
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

        let threadID = "thread-model-cache"
        let baseTime = Date().addingTimeInterval(-10)
        let firstTimestamp = isoString(baseTime)
        let secondTimestamp = isoString(baseTime.addingTimeInterval(1))
        let thirdTimestamp = isoString(baseTime.addingTimeInterval(2))
        let fourthTimestamp = isoString(baseTime.addingTimeInterval(3))
        let sessionIndexJSONL = """
        {"id":"\(threadID)","thread_name":"model cache","updated_at":"\(firstTimestamp)"}
        """
        try sessionIndexJSONL.data(using: .utf8)?.write(
            to: rootURL.appendingPathComponent("session_index.jsonl")
        )

        let rolloutPath = sessionsDayURL.appendingPathComponent("rollout-2026-04-11T10-00-00-\(threadID).jsonl")
        let withModel = """
        {"timestamp":"\(firstTimestamp)","type":"turn_context","payload":{"turn_id":"turn-1","model":"gpt-5.4"}}
        {"timestamp":"\(secondTimestamp)","type":"event_msg","payload":{"type":"task_started","turn_id":"turn-1"}}
        """
        try withModel.data(using: .utf8)?.write(to: rolloutPath)

        let monitor = CodexMonitor(codexHomePath: rootURL.path)
        monitor.refreshNow()
        XCTAssertEqual(monitor.codexState.threads.first?.modelLabel, "gpt-5.4")

        let withoutModel = """
        {"timestamp":"\(thirdTimestamp)","type":"response_item","payload":{"type":"message","role":"user","turn_id":"turn-1","content":[{"type":"input_text","text":"继续执行"}]}}
        {"timestamp":"\(fourthTimestamp)","type":"event_msg","payload":{"type":"task_started","turn_id":"turn-1"}}
        """
        try withoutModel.data(using: .utf8)?.write(to: rolloutPath)
        monitor.refreshNow()

        XCTAssertEqual(monitor.codexState.threads.first?.modelLabel, "gpt-5.4")
    }

    func testRefreshNowIgnoresLiveSubagentThreadSessions() throws {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sessionsDayURL = rootURL
            .appendingPathComponent("sessions", isDirectory: true)
            .appendingPathComponent("2026", isDirectory: true)
            .appendingPathComponent("04", isDirectory: true)
            .appendingPathComponent("15", isDirectory: true)

        try fileManager.createDirectory(at: sessionsDayURL, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: rootURL) }

        let mainThreadID = "thread-main"
        let subagentThreadID = "019d91b0-3122-74b1-af47-c94cdaac39cf"
        let mainTime = Date().addingTimeInterval(-30)
        let subagentTime = Date()
        let sessionIndexJSONL = """
        {"id":"\(mainThreadID)","thread_name":"评估 ai dynamic island 优化方向","updated_at":"\(isoString(mainTime))"}
        {"id":"\(subagentThreadID)","thread_name":"Review concurrency fix","updated_at":"\(isoString(subagentTime))"}
        """
        try sessionIndexJSONL.data(using: .utf8)?.write(
            to: rootURL.appendingPathComponent("session_index.jsonl")
        )

        let mainJSONL = """
        {"timestamp":"\(isoString(mainTime.addingTimeInterval(-2)))","type":"turn_context","payload":{"turn_id":"turn-main","model":"gpt-5.4"}}
        {"timestamp":"\(isoString(mainTime.addingTimeInterval(-1)))","type":"response_item","payload":{"type":"message","role":"user","turn_id":"turn-main","content":[{"type":"input_text","text":"重启 ai 灵动岛我检查下"}]}}
        {"timestamp":"\(isoString(mainTime))","type":"event_msg","payload":{"type":"task_started","turn_id":"turn-main"}}
        """
        try mainJSONL.data(using: .utf8)?.write(
            to: sessionsDayURL.appendingPathComponent("\(mainThreadID).jsonl")
        )

        let subagentJSONL = """
        {"timestamp":"\(isoString(subagentTime.addingTimeInterval(-3)))","type":"session_meta","payload":{"id":"\(subagentThreadID)","cwd":"/Users/chenyuanjie/developer","source":{"subagent":{"thread_spawn":{"parent_thread_id":"\(mainThreadID)","depth":1,"agent_nickname":"Zeno","agent_role":"explorer"}}},"agent_nickname":"Zeno","agent_role":"explorer"}}
        {"timestamp":"\(isoString(subagentTime.addingTimeInterval(-2)))","type":"turn_context","payload":{"turn_id":"turn-subagent","model":"gpt-5.4-mini"}}
        {"timestamp":"\(isoString(subagentTime.addingTimeInterval(-1)))","type":"response_item","payload":{"type":"message","role":"user","turn_id":"turn-subagent","content":[{"type":"input_text","text":"Please re-review the updated version of the same files after fixes were applied."}]}}
        {"timestamp":"\(isoString(subagentTime))","type":"event_msg","payload":{"type":"task_started","turn_id":"turn-subagent"}}
        """
        try subagentJSONL.data(using: .utf8)?.write(
            to: sessionsDayURL.appendingPathComponent("\(subagentThreadID).jsonl")
        )

        let monitor = CodexMonitor(codexHomePath: rootURL.path)
        monitor.refreshNow()

        XCTAssertEqual(monitor.codexState.threads.count, 1)
        XCTAssertEqual(monitor.codexState.threads.first?.id, mainThreadID)
        XCTAssertEqual(monitor.codexState.threads.first?.taskLabel, "重启 ai 灵动岛我检查下")
    }

    func testRefreshNowFoldsSuppressedSubagentActivityIntoParentThreadDetail() throws {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sessionsDayURL = rootURL
            .appendingPathComponent("sessions", isDirectory: true)
            .appendingPathComponent("2026", isDirectory: true)
            .appendingPathComponent("04", isDirectory: true)
            .appendingPathComponent("15", isDirectory: true)

        try fileManager.createDirectory(at: sessionsDayURL, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: rootURL) }

        let mainThreadID = "thread-main"
        let subagentThreadID = "thread-subagent"
        let mainTime = Date().addingTimeInterval(-20)
        let subagentTime = Date().addingTimeInterval(-2)
        let sessionIndexJSONL = """
        {"id":"\(mainThreadID)","thread_name":"评估 ai dynamic island 优化方向","updated_at":"\(isoString(mainTime))"}
        {"id":"\(subagentThreadID)","thread_name":"Review concurrency fix","updated_at":"\(isoString(subagentTime))"}
        """
        try sessionIndexJSONL.data(using: .utf8)?.write(
            to: rootURL.appendingPathComponent("session_index.jsonl")
        )

        let mainJSONL = """
        {"timestamp":"\(isoString(mainTime.addingTimeInterval(-1)))","type":"session_meta","payload":{"id":"\(mainThreadID)","cwd":"/Users/chenyuanjie/developer/ai-dynamic-island-macos","model":"gpt-5.4"}}
        {"timestamp":"\(isoString(mainTime))","type":"response_item","payload":{"type":"message","role":"user","turn_id":"turn-main","content":[{"type":"input_text","text":"评估 ai dynamic island 优化方向"}]}}
        {"timestamp":"\(isoString(mainTime.addingTimeInterval(1)))","type":"event_msg","payload":{"type":"task_started","turn_id":"turn-main"}}
        """
        try mainJSONL.data(using: .utf8)?.write(
            to: sessionsDayURL.appendingPathComponent("\(mainThreadID).jsonl")
        )

        let subagentJSONL = """
        {"timestamp":"\(isoString(subagentTime.addingTimeInterval(-2)))","type":"session_meta","payload":{"id":"\(subagentThreadID)","cwd":"/Users/chenyuanjie/developer/ai-dynamic-island-macos","source":{"subagent":{"thread_spawn":{"parent_thread_id":"\(mainThreadID)","depth":1,"agent_nickname":"Zeno","agent_role":"explorer"}}},"agent_nickname":"Zeno","agent_role":"explorer"}}
        {"timestamp":"\(isoString(subagentTime.addingTimeInterval(-1)))","type":"response_item","payload":{"type":"message","role":"user","turn_id":"turn-subagent","content":[{"type":"input_text","text":"Please re-review the updated version."}]}}
        {"timestamp":"\(isoString(subagentTime))","type":"event_msg","payload":{"type":"task_started","turn_id":"turn-subagent"}}
        """
        try subagentJSONL.data(using: .utf8)?.write(
            to: sessionsDayURL.appendingPathComponent("\(subagentThreadID).jsonl")
        )

        let monitor = CodexMonitor(codexHomePath: rootURL.path)
        monitor.refreshNow()

        XCTAssertEqual(monitor.codexState.threads.count, 1)
        XCTAssertEqual(monitor.codexState.threads.first?.id, mainThreadID)
        XCTAssertEqual(monitor.codexState.threads.first?.detail, "1 个子任务有更新")
    }

    func testRefreshNowIgnoresIndexedSubagentThreadWhenSessionHeaderLineIsIncomplete() throws {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sessionsDayURL = rootURL
            .appendingPathComponent("sessions", isDirectory: true)
            .appendingPathComponent("2026", isDirectory: true)
            .appendingPathComponent("04", isDirectory: true)
            .appendingPathComponent("15", isDirectory: true)

        try fileManager.createDirectory(at: sessionsDayURL, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: rootURL) }

        let mainThreadID = "thread-main"
        let subagentThreadID = "thread-subagent-incomplete"
        let mainTime = Date().addingTimeInterval(-30)
        let subagentTime = Date()
        let sessionIndexJSONL = """
        {"id":"\(mainThreadID)","thread_name":"评估 ai dynamic island 优化方向","updated_at":"\(isoString(mainTime))"}
        {"id":"\(subagentThreadID)","thread_name":"Please re-review the updated version...","updated_at":"\(isoString(subagentTime))"}
        """
        try sessionIndexJSONL.data(using: .utf8)?.write(
            to: rootURL.appendingPathComponent("session_index.jsonl")
        )

        let mainJSONL = """
        {"timestamp":"\(isoString(mainTime.addingTimeInterval(-2)))","type":"turn_context","payload":{"turn_id":"turn-main","model":"gpt-5.4"}}
        {"timestamp":"\(isoString(mainTime.addingTimeInterval(-1)))","type":"response_item","payload":{"type":"message","role":"user","turn_id":"turn-main","content":[{"type":"input_text","text":"重启 ai 灵动岛我检查下"}]}}
        {"timestamp":"\(isoString(mainTime))","type":"event_msg","payload":{"type":"task_started","turn_id":"turn-main"}}
        """
        try mainJSONL.data(using: .utf8)?.write(
            to: sessionsDayURL.appendingPathComponent("\(mainThreadID).jsonl")
        )

        let incompleteSubagentHeader = """
        {"timestamp":"\(isoString(subagentTime.addingTimeInterval(-3)))","type":"session_meta","payload":{"id":"\(subagentThreadID)","cwd":"/Users/chenyuanjie/developer","source":{"subagent":{"thread_spawn":{"parent_thread_id":"\(mainThreadID)","depth":1,"agent_nickname":"Zeno","agent_role":"explorer"}}},"agent_nickname":"Zeno","agent_role":"explorer"}}
        """
        let incompleteHeaderWithoutTrailingNewline = String(incompleteSubagentHeader.dropLast())
        try incompleteHeaderWithoutTrailingNewline.data(using: .utf8)?.write(
            to: sessionsDayURL.appendingPathComponent("\(subagentThreadID).jsonl")
        )

        let monitor = CodexMonitor(codexHomePath: rootURL.path)
        monitor.refreshNow()

        XCTAssertEqual(monitor.codexState.threads.count, 1)
        XCTAssertEqual(monitor.codexState.threads.first?.id, mainThreadID)
        XCTAssertEqual(monitor.codexState.threads.first?.taskLabel, "重启 ai 灵动岛我检查下")
    }

    func testManualRefreshDuringInFlightRefreshDoesNotBlockLaterEventRefreshes() throws {
        let blocked = expectation(description: "startup refresh is blocked")
        let fileManager = BlockingFileManager { path in
            if path.hasSuffix("/session_index.jsonl") {
                blocked.fulfill()
            }
        }
        let rootURL = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sessionsDayURL = rootURL
            .appendingPathComponent("sessions", isDirectory: true)
            .appendingPathComponent("2026", isDirectory: true)
            .appendingPathComponent("04", isDirectory: true)
            .appendingPathComponent("11", isDirectory: true)
        try fileManager.createDirectory(at: sessionsDayURL, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: rootURL) }

        let indexPath = rootURL.appendingPathComponent("session_index.jsonl").path
        try writeCodexFixture(
            fileManager: fileManager,
            rootURL: rootURL,
            sessionsDayURL: sessionsDayURL,
            threadID: "thread-a",
            taskLabel: "startup refresh",
            signalAt: Date().addingTimeInterval(-30),
            model: "gpt-5.4"
        )

        let signalSource = TestRealtimeSignalSource()
        let monitor = CodexMonitor(
            fileManager: fileManager,
            codexHomePath: rootURL.path,
            keepAlivePollInterval: 60,
            eventDebounceInterval: 0.01,
            signalSource: signalSource
        )

        fileManager.blockNextRead(atPath: indexPath)
        monitor.start()
        wait(for: [blocked], timeout: 1.0)

        try writeCodexFixture(
            fileManager: fileManager,
            rootURL: rootURL,
            sessionsDayURL: sessionsDayURL,
            threadID: "thread-b",
            taskLabel: "manual refresh",
            signalAt: Date(),
            model: "gpt-5.4-mini"
        )
        monitor.refreshNow()
        XCTAssertEqual(monitor.codexState.threads.first?.id, "thread-b")

        fileManager.releaseBlockedRead()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))

        try writeCodexFixture(
            fileManager: fileManager,
            rootURL: rootURL,
            sessionsDayURL: sessionsDayURL,
            threadID: "thread-c",
            taskLabel: "event refresh",
            signalAt: Date().addingTimeInterval(1),
            model: "gpt-5.3-codex"
        )
        signalSource.emit()

        assertEventually {
            monitor.codexState.threads.first?.id == "thread-c"
        }
        monitor.stop()
    }

    func testRestartWhileStaleRefreshCompletesDoesNotDropCurrentInFlightGate() throws {
        let firstBlocked = expectation(description: "first startup refresh is blocked")
        let secondBlocked = expectation(description: "second startup refresh is blocked")
        let blockCounter = ReadBlockCounter()
        let fileManager = BlockingFileManager { path in
            guard path.hasSuffix("/session_index.jsonl") else {
                return
            }

            let blockCount = blockCounter.increment()
            if blockCount == 1 {
                firstBlocked.fulfill()
            } else if blockCount == 2 {
                secondBlocked.fulfill()
            }
        }
        let rootURL = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sessionsDayURL = rootURL
            .appendingPathComponent("sessions", isDirectory: true)
            .appendingPathComponent("2026", isDirectory: true)
            .appendingPathComponent("04", isDirectory: true)
            .appendingPathComponent("11", isDirectory: true)
        try fileManager.createDirectory(at: sessionsDayURL, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: rootURL) }

        let indexPath = rootURL.appendingPathComponent("session_index.jsonl").path
        let signalSource = TestRealtimeSignalSource()
        let monitor = CodexMonitor(
            fileManager: fileManager,
            codexHomePath: rootURL.path,
            keepAlivePollInterval: 60,
            eventDebounceInterval: 0.01,
            signalSource: signalSource
        )

        try writeCodexFixture(
            fileManager: fileManager,
            rootURL: rootURL,
            sessionsDayURL: sessionsDayURL,
            threadID: "thread-a",
            taskLabel: "first startup refresh",
            signalAt: Date().addingTimeInterval(-30),
            model: "gpt-5.4"
        )

        fileManager.blockNextRead(atPath: indexPath)
        monitor.start()
        wait(for: [firstBlocked], timeout: 1.0)

        monitor.stop()

        try writeCodexFixture(
            fileManager: fileManager,
            rootURL: rootURL,
            sessionsDayURL: sessionsDayURL,
            threadID: "thread-b",
            taskLabel: "second startup refresh",
            signalAt: Date(),
            model: "gpt-5.4-mini"
        )

        fileManager.blockNextRead(atPath: indexPath)
        monitor.start()
        fileManager.releaseBlockedRead()
        wait(for: [secondBlocked], timeout: 1.0)

        try writeCodexFixture(
            fileManager: fileManager,
            rootURL: rootURL,
            sessionsDayURL: sessionsDayURL,
            threadID: "thread-c",
            taskLabel: "event refresh after restart",
            signalAt: Date().addingTimeInterval(1),
            model: "gpt-5.3-codex"
        )
        signalSource.emit()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))

        let debugState = monitor.debugRefreshState
        XCTAssertTrue(debugState.refreshInFlight)
        XCTAssertTrue(debugState.refreshDirty)

        fileManager.releaseBlockedRead()
        assertEventually {
            monitor.codexState.threads.first?.id == "thread-c"
        }
        monitor.stop()
    }

    private func writeCodexFixture(
        fileManager: FileManager,
        rootURL: URL,
        sessionsDayURL: URL,
        threadID: String,
        taskLabel: String,
        signalAt: Date,
        model: String
    ) throws {
        let signalTimestamp = isoString(signalAt)
        let sessionIndexJSONL = """
        {"id":"\(threadID)","thread_name":"\(taskLabel)","updated_at":"\(signalTimestamp)"}
        """
        try sessionIndexJSONL.data(using: .utf8)?.write(
            to: rootURL.appendingPathComponent("session_index.jsonl")
        )

        if let enumerator = fileManager.enumerator(
            at: sessionsDayURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) {
            for case let existingURL as URL in enumerator where existingURL.pathExtension == "jsonl" {
                try? fileManager.removeItem(at: existingURL)
            }
        }

        let sessionJSONL = """
        {"timestamp":"\(signalTimestamp)","type":"turn_context","payload":{"turn_id":"turn-1","model":"\(model)"}}
        {"timestamp":"\(isoString(signalAt.addingTimeInterval(1)))","type":"response_item","payload":{"type":"message","role":"user","turn_id":"turn-1","content":[{"type":"input_text","text":"\(taskLabel)"}]}}
        {"timestamp":"\(isoString(signalAt.addingTimeInterval(2)))","type":"event_msg","payload":{"type":"task_started","turn_id":"turn-1"}}
        """
        try sessionJSONL.data(using: .utf8)?.write(
            to: sessionsDayURL.appendingPathComponent("\(threadID).jsonl")
        )
    }
}
