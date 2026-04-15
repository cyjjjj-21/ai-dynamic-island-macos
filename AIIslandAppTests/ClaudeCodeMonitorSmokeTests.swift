import XCTest

@testable import AIIslandApp
@testable import AIIslandCore

@MainActor
final class ClaudeCodeMonitorSmokeTests: XCTestCase {
    func testRefreshNowBuildsClaudeStateFromTempSessionTranscriptBridgeAndPresentation() throws {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let claudeDirURL = rootURL.appendingPathComponent(".claude", isDirectory: true)
        let sessionsDirURL = claudeDirURL.appendingPathComponent("sessions", isDirectory: true)
        let projectsDirURL = claudeDirURL.appendingPathComponent("projects", isDirectory: true)
        let bridgeDirURL = rootURL.appendingPathComponent("bridge", isDirectory: true)
        let cwd = "/workspace/ai-dynamic-island-macos"
        let encodedCwd = cwd.replacingOccurrences(of: "/", with: "-")
        let transcriptDirURL = projectsDirURL.appendingPathComponent(encodedCwd, isDirectory: true)
        let sessionID = "session-smoke"

        try fileManager.createDirectory(at: sessionsDirURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: transcriptDirURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: bridgeDirURL, withIntermediateDirectories: true)

        defer { try? fileManager.removeItem(at: rootURL) }

        let sessionJSON = """
        {
          "pid": 4242,
          "sessionId": "\(sessionID)",
          "cwd": "\(cwd)",
          "status": "waiting",
          "waitingFor": "approve Bash"
        }
        """
        try sessionJSON.data(using: .utf8)?.write(
            to: sessionsDirURL.appendingPathComponent("\(sessionID).json")
        )

        let transcriptJSONL = """
        {"type":"assistant","message":{"model":"kimi-k2.5","usage":{"input_tokens":128},"stop_reason":"tool_use","content":[{"type":"tool_use","id":"tool-1","name":"Read","input":{"file_path":"README.md"}}]}}
        {"type":"task-summary","summary":"Inspect Claude state chain","timestamp":"2026-04-11T10:00:00Z"}
        """
        try transcriptJSONL.data(using: .utf8)?.write(
            to: transcriptDirURL.appendingPathComponent("\(sessionID).jsonl")
        )

        let bridgeJSON = """
        {
          "used_pct": 37,
          "agent_state": "idle"
        }
        """
        try bridgeJSON.data(using: .utf8)?.write(
            to: bridgeDirURL.appendingPathComponent("claude-ctx-\(sessionID).json")
        )

        let monitor = ClaudeCodeMonitor(
            claudeDirPath: claudeDirURL.path,
            temporaryDirectoryPath: bridgeDirURL.path,
            processAliveChecker: { _ in true }
        )

        monitor.refreshNow()

        let state = monitor.claudeState
        let presentation = AgentSectionPresentation(state: state)

        XCTAssertTrue(state.online)
        XCTAssertEqual(state.globalState, AgentGlobalState.attention)
        XCTAssertEqual(state.threads.count, 1)
        XCTAssertEqual(state.threads.first?.taskLabel, "approve Bash")
        XCTAssertEqual(state.threads.first?.modelLabel, "kimi-k2.5")
        XCTAssertEqual(try XCTUnwrap(state.threads.first?.contextRatio), 0.37, accuracy: 0.0001)
        XCTAssertEqual(presentation.primaryStatusCopy, "Attention")
        XCTAssertEqual(presentation.visibleThreads.count, 1)
        XCTAssertEqual(presentation.visibleThreads.first?.modelLabel, "Kimi K2.5")
        XCTAssertEqual(presentation.visibleThreads.first?.contextCopy, "Context 37%")
    }

    func testRefreshNowHidesClaudeThreadAfterVisibleIdleWindowButKeepsAvailabilityAvailable() throws {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let claudeDirURL = rootURL.appendingPathComponent(".claude", isDirectory: true)
        let sessionsDirURL = claudeDirURL.appendingPathComponent("sessions", isDirectory: true)
        let projectsDirURL = claudeDirURL.appendingPathComponent("projects", isDirectory: true)
        let bridgeDirURL = rootURL.appendingPathComponent("bridge", isDirectory: true)
        let cwd = "/workspace/ai-dynamic-island-macos"
        let encodedCwd = cwd.replacingOccurrences(of: "/", with: "-")
        let transcriptDirURL = projectsDirURL.appendingPathComponent(encodedCwd, isDirectory: true)
        let sessionID = "session-sunset-visible"

        try fileManager.createDirectory(at: sessionsDirURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: transcriptDirURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: bridgeDirURL, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: rootURL) }

        let sessionPath = sessionsDirURL.appendingPathComponent("\(sessionID).json")
        let transcriptPath = transcriptDirURL.appendingPathComponent("\(sessionID).jsonl")
        let bridgePath = bridgeDirURL.appendingPathComponent("claude-ctx-\(sessionID).json")

        let sessionJSON = """
        {
          "pid": 4242,
          "sessionId": "\(sessionID)",
          "cwd": "\(cwd)",
          "status": "busy"
        }
        """
        try sessionJSON.data(using: .utf8)?.write(to: sessionPath)
        try #"{"type":"assistant","message":{"model":"kimi-k2.5","stop_reason":"tool_use","content":[{"type":"tool_use","id":"tool-1","name":"Read","input":{"file_path":"README.md"}}]}}"#.data(using: .utf8)?.write(to: transcriptPath)
        try #"{"used_pct":37}"#.data(using: .utf8)?.write(to: bridgePath)

        let oldDate = Date().addingTimeInterval(-26 * 60)
        try fileManager.setAttributes([.modificationDate: oldDate], ofItemAtPath: sessionPath.path)
        try fileManager.setAttributes([.modificationDate: oldDate], ofItemAtPath: transcriptPath.path)
        try fileManager.setAttributes([.modificationDate: oldDate], ofItemAtPath: bridgePath.path)

        let monitor = ClaudeCodeMonitor(
            claudeDirPath: claudeDirURL.path,
            temporaryDirectoryPath: bridgeDirURL.path,
            processAliveChecker: { _ in true }
        )
        monitor.refreshNow()

        XCTAssertTrue(monitor.claudeState.online)
        XCTAssertEqual(monitor.claudeState.availability, .available)
        XCTAssertEqual(monitor.claudeState.globalState, .idle)
        XCTAssertEqual(monitor.claudeState.threads.count, 0)
    }

    func testRefreshNowMarksClaudeStatusUnavailableAfterLiveSignalWindowExpires() throws {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let claudeDirURL = rootURL.appendingPathComponent(".claude", isDirectory: true)
        let sessionsDirURL = claudeDirURL.appendingPathComponent("sessions", isDirectory: true)
        let projectsDirURL = claudeDirURL.appendingPathComponent("projects", isDirectory: true)
        let bridgeDirURL = rootURL.appendingPathComponent("bridge", isDirectory: true)
        let cwd = "/workspace/ai-dynamic-island-macos"
        let encodedCwd = cwd.replacingOccurrences(of: "/", with: "-")
        let transcriptDirURL = projectsDirURL.appendingPathComponent(encodedCwd, isDirectory: true)
        let sessionID = "session-sunset-expired"

        try fileManager.createDirectory(at: sessionsDirURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: transcriptDirURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: bridgeDirURL, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: rootURL) }

        let sessionPath = sessionsDirURL.appendingPathComponent("\(sessionID).json")
        let transcriptPath = transcriptDirURL.appendingPathComponent("\(sessionID).jsonl")
        let bridgePath = bridgeDirURL.appendingPathComponent("claude-ctx-\(sessionID).json")

        let sessionJSON = """
        {
          "pid": 4242,
          "sessionId": "\(sessionID)",
          "cwd": "\(cwd)",
          "status": "busy"
        }
        """
        try sessionJSON.data(using: .utf8)?.write(to: sessionPath)
        try #"{"type":"assistant","message":{"model":"kimi-k2.5","stop_reason":"tool_use","content":[{"type":"tool_use","id":"tool-1","name":"Read","input":{"file_path":"README.md"}}]}}"#.data(using: .utf8)?.write(to: transcriptPath)
        try #"{"used_pct":37}"#.data(using: .utf8)?.write(to: bridgePath)

        let oldDate = Date().addingTimeInterval(-46 * 60)
        try fileManager.setAttributes([.modificationDate: oldDate], ofItemAtPath: sessionPath.path)
        try fileManager.setAttributes([.modificationDate: oldDate], ofItemAtPath: transcriptPath.path)
        try fileManager.setAttributes([.modificationDate: oldDate], ofItemAtPath: bridgePath.path)

        let monitor = ClaudeCodeMonitor(
            claudeDirPath: claudeDirURL.path,
            temporaryDirectoryPath: bridgeDirURL.path,
            processAliveChecker: { _ in true }
        )
        monitor.refreshNow()

        XCTAssertTrue(monitor.claudeState.online)
        XCTAssertEqual(monitor.claudeState.availability, .statusUnavailable)
        XCTAssertEqual(monitor.claudeState.globalState, .idle)
        XCTAssertEqual(monitor.claudeState.threads.count, 0)
    }

    func testRefreshNowKeepsLastKnownModelWhenTranscriptTemporarilyDropsModelField() throws {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let claudeDirURL = rootURL.appendingPathComponent(".claude", isDirectory: true)
        let sessionsDirURL = claudeDirURL.appendingPathComponent("sessions", isDirectory: true)
        let projectsDirURL = claudeDirURL.appendingPathComponent("projects", isDirectory: true)
        let bridgeDirURL = rootURL.appendingPathComponent("bridge", isDirectory: true)
        let cwd = "/workspace/ai-dynamic-island-macos"
        let encodedCwd = cwd.replacingOccurrences(of: "/", with: "-")
        let transcriptDirURL = projectsDirURL.appendingPathComponent(encodedCwd, isDirectory: true)
        let sessionID = "session-model-cache"

        try fileManager.createDirectory(at: sessionsDirURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: transcriptDirURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: bridgeDirURL, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: rootURL) }

        let sessionPath = sessionsDirURL.appendingPathComponent("\(sessionID).json")
        let transcriptPath = transcriptDirURL.appendingPathComponent("\(sessionID).jsonl")
        let bridgePath = bridgeDirURL.appendingPathComponent("claude-ctx-\(sessionID).json")

        let sessionJSON = """
        {
          "pid": 4242,
          "sessionId": "\(sessionID)",
          "cwd": "\(cwd)",
          "status": "busy"
        }
        """
        try sessionJSON.data(using: .utf8)?.write(to: sessionPath)
        try #"{"used_pct":37}"#.data(using: .utf8)?.write(to: bridgePath)

        let withModel = """
        {"type":"assistant","message":{"model":"kimi-k2.5","stop_reason":"tool_use","content":[{"type":"tool_use","id":"tool-1","name":"Read","input":{"file_path":"README.md"}}]}}
        """
        try withModel.data(using: .utf8)?.write(to: transcriptPath)

        let monitor = ClaudeCodeMonitor(
            claudeDirPath: claudeDirURL.path,
            temporaryDirectoryPath: bridgeDirURL.path,
            processAliveChecker: { _ in true }
        )
        monitor.refreshNow()
        XCTAssertEqual(monitor.claudeState.threads.first?.modelLabel, "kimi-k2.5")

        let withoutModel = """
        {"type":"assistant","message":{"stop_reason":"tool_use","content":[{"type":"tool_use","id":"tool-1","name":"Read","input":{"file_path":"README.md"}}]}}
        """
        try withoutModel.data(using: .utf8)?.write(to: transcriptPath)
        monitor.refreshNow()

        XCTAssertEqual(monitor.claudeState.threads.first?.modelLabel, "kimi-k2.5")
    }

    func testRefreshNowBuildsMultipleClaudeThreadsWhenTwoLiveSessionsExist() throws {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let claudeDirURL = rootURL.appendingPathComponent(".claude", isDirectory: true)
        let sessionsDirURL = claudeDirURL.appendingPathComponent("sessions", isDirectory: true)
        let projectsDirURL = claudeDirURL.appendingPathComponent("projects", isDirectory: true)
        let bridgeDirURL = rootURL.appendingPathComponent("bridge", isDirectory: true)

        try fileManager.createDirectory(at: sessionsDirURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: projectsDirURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: bridgeDirURL, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: rootURL) }

        try makeClaudeSessionFixture(
            fileManager: fileManager,
            sessionsDirURL: sessionsDirURL,
            projectsDirURL: projectsDirURL,
            bridgeDirURL: bridgeDirURL,
            sessionID: "session-a",
            cwd: "/workspace/alpha",
            status: "busy",
            waitingFor: nil,
            model: "claude-sonnet-4",
            summary: "Inspect alpha monitor chain",
            usedPercent: 21,
            modifiedAt: Date().addingTimeInterval(-5)
        )

        try makeClaudeSessionFixture(
            fileManager: fileManager,
            sessionsDirURL: sessionsDirURL,
            projectsDirURL: projectsDirURL,
            bridgeDirURL: bridgeDirURL,
            sessionID: "session-b",
            cwd: "/workspace/beta",
            status: "waiting",
            waitingFor: "approve Edit",
            model: "kimi-k2.5",
            summary: "Inspect beta monitor chain",
            usedPercent: 63,
            modifiedAt: Date()
        )

        let monitor = ClaudeCodeMonitor(
            claudeDirPath: claudeDirURL.path,
            temporaryDirectoryPath: bridgeDirURL.path,
            processAliveChecker: { _ in true }
        )

        monitor.refreshNow()

        XCTAssertEqual(monitor.claudeState.availability, .available)
        XCTAssertEqual(monitor.claudeState.threads.count, 2)
        XCTAssertEqual(monitor.claudeState.threads.map(\.id), ["session-b", "session-a"])
        XCTAssertEqual(monitor.claudeState.globalState, .attention)
    }

    func testRefreshNowSwitchesVisiblePrimaryThreadWhenLatestLiveSessionChanges() throws {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let claudeDirURL = rootURL.appendingPathComponent(".claude", isDirectory: true)
        let sessionsDirURL = claudeDirURL.appendingPathComponent("sessions", isDirectory: true)
        let projectsDirURL = claudeDirURL.appendingPathComponent("projects", isDirectory: true)
        let bridgeDirURL = rootURL.appendingPathComponent("bridge", isDirectory: true)

        try fileManager.createDirectory(at: sessionsDirURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: projectsDirURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: bridgeDirURL, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: rootURL) }

        let older = Date().addingTimeInterval(-20)
        let newer = Date().addingTimeInterval(-5)

        try makeClaudeSessionFixture(
            fileManager: fileManager,
            sessionsDirURL: sessionsDirURL,
            projectsDirURL: projectsDirURL,
            bridgeDirURL: bridgeDirURL,
            sessionID: "session-a",
            cwd: "/workspace/alpha",
            status: "waiting",
            waitingFor: "approve Bash",
            model: "claude-sonnet-4",
            summary: "Inspect alpha monitor chain",
            usedPercent: 21,
            modifiedAt: newer
        )

        try makeClaudeSessionFixture(
            fileManager: fileManager,
            sessionsDirURL: sessionsDirURL,
            projectsDirURL: projectsDirURL,
            bridgeDirURL: bridgeDirURL,
            sessionID: "session-b",
            cwd: "/workspace/beta",
            status: "waiting",
            waitingFor: "approve Edit",
            model: "kimi-k2.5",
            summary: "Inspect beta monitor chain",
            usedPercent: 63,
            modifiedAt: older
        )

        let monitor = ClaudeCodeMonitor(
            claudeDirPath: claudeDirURL.path,
            temporaryDirectoryPath: bridgeDirURL.path,
            processAliveChecker: { _ in true }
        )

        monitor.refreshNow()
        XCTAssertEqual(monitor.claudeState.threads.map(\.id), ["session-a", "session-b"])

        let sessionBPath = sessionsDirURL.appendingPathComponent("session-b.json")
        let transcriptBPath = projectsDirURL
            .appendingPathComponent("-workspace-beta", isDirectory: true)
            .appendingPathComponent("session-b.jsonl")
        let bridgeBPath = bridgeDirURL.appendingPathComponent("claude-ctx-session-b.json")
        let promoted = Date().addingTimeInterval(15)
        try fileManager.setAttributes([.modificationDate: promoted], ofItemAtPath: sessionBPath.path)
        try fileManager.setAttributes([.modificationDate: promoted], ofItemAtPath: transcriptBPath.path)
        try fileManager.setAttributes([.modificationDate: promoted], ofItemAtPath: bridgeBPath.path)

        monitor.refreshNow()
        XCTAssertEqual(monitor.claudeState.threads.map(\.id), ["session-b", "session-a"])
        XCTAssertEqual(monitor.claudeState.globalState, .attention)
    }

    func testManualRefreshDuringInFlightRefreshDoesNotBlockLaterEventRefreshes() throws {
        let blocked = expectation(description: "startup refresh is blocked")
        let fileManager = BlockingFileManager { path in
            if path.hasSuffix("/session-a.json") {
                blocked.fulfill()
            }
        }
        let rootURL = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let claudeDirURL = rootURL.appendingPathComponent(".claude", isDirectory: true)
        let sessionsDirURL = claudeDirURL.appendingPathComponent("sessions", isDirectory: true)
        let projectsDirURL = claudeDirURL.appendingPathComponent("projects", isDirectory: true)
        let bridgeDirURL = rootURL.appendingPathComponent("bridge", isDirectory: true)

        try fileManager.createDirectory(at: sessionsDirURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: projectsDirURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: bridgeDirURL, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: rootURL) }

        try makeClaudeSessionFixture(
            fileManager: fileManager,
            sessionsDirURL: sessionsDirURL,
            projectsDirURL: projectsDirURL,
            bridgeDirURL: bridgeDirURL,
            sessionID: "session-a",
            cwd: "/workspace/alpha",
            status: "busy",
            waitingFor: nil,
            model: "claude-sonnet-4",
            summary: "startup refresh",
            usedPercent: 20,
            modifiedAt: Date().addingTimeInterval(-30)
        )

        let signalSource = TestRealtimeSignalSource()
        let monitor = ClaudeCodeMonitor(
            fileManager: fileManager,
            claudeDirPath: claudeDirURL.path,
            temporaryDirectoryPath: bridgeDirURL.path,
            processAliveChecker: { _ in true },
            keepAlivePollInterval: 60,
            eventDebounceInterval: 0.01,
            signalSource: signalSource
        )

        let blockedSessionPath = sessionsDirURL.appendingPathComponent("session-a.json").path
        fileManager.blockNextRead(atPath: blockedSessionPath)
        monitor.start()
        wait(for: [blocked], timeout: 1.0)

        try makeClaudeSessionFixture(
            fileManager: fileManager,
            sessionsDirURL: sessionsDirURL,
            projectsDirURL: projectsDirURL,
            bridgeDirURL: bridgeDirURL,
            sessionID: "session-b",
            cwd: "/workspace/beta",
            status: "waiting",
            waitingFor: "approve Edit",
            model: "kimi-k2.5",
            summary: "manual refresh",
            usedPercent: 63,
            modifiedAt: Date()
        )
        monitor.refreshNow()
        XCTAssertEqual(monitor.claudeState.threads.first?.id, "session-b")

        fileManager.releaseBlockedRead()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))

        try makeClaudeSessionFixture(
            fileManager: fileManager,
            sessionsDirURL: sessionsDirURL,
            projectsDirURL: projectsDirURL,
            bridgeDirURL: bridgeDirURL,
            sessionID: "session-c",
            cwd: "/workspace/gamma",
            status: "waiting",
            waitingFor: "approve Bash",
            model: "claude-opus-4.1",
            summary: "event refresh",
            usedPercent: 44,
            modifiedAt: Date().addingTimeInterval(1)
        )
        signalSource.emit()

        assertEventually {
            monitor.claudeState.threads.first?.id == "session-c"
        }
        monitor.stop()
    }

    func testRestartWhileStaleRefreshCompletesDoesNotDropCurrentInFlightGate() throws {
        let firstBlocked = expectation(description: "first startup refresh is blocked")
        let secondBlocked = expectation(description: "second startup refresh is blocked")
        let blockCounter = ReadBlockCounter()
        let fileManager = BlockingFileManager { path in
            guard path.hasSuffix("/session-a.json") || path.hasSuffix("/session-b.json") else {
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
        let claudeDirURL = rootURL.appendingPathComponent(".claude", isDirectory: true)
        let sessionsDirURL = claudeDirURL.appendingPathComponent("sessions", isDirectory: true)
        let projectsDirURL = claudeDirURL.appendingPathComponent("projects", isDirectory: true)
        let bridgeDirURL = rootURL.appendingPathComponent("bridge", isDirectory: true)

        try fileManager.createDirectory(at: sessionsDirURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: projectsDirURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: bridgeDirURL, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: rootURL) }

        let signalSource = TestRealtimeSignalSource()
        let monitor = ClaudeCodeMonitor(
            fileManager: fileManager,
            claudeDirPath: claudeDirURL.path,
            temporaryDirectoryPath: bridgeDirURL.path,
            processAliveChecker: { _ in true },
            keepAlivePollInterval: 60,
            eventDebounceInterval: 0.01,
            signalSource: signalSource
        )

        try makeClaudeSessionFixture(
            fileManager: fileManager,
            sessionsDirURL: sessionsDirURL,
            projectsDirURL: projectsDirURL,
            bridgeDirURL: bridgeDirURL,
            sessionID: "session-a",
            cwd: "/workspace/alpha",
            status: "busy",
            waitingFor: nil,
            model: "claude-sonnet-4",
            summary: "first startup refresh",
            usedPercent: 20,
            modifiedAt: Date().addingTimeInterval(-30)
        )

        let firstSessionPath = sessionsDirURL.appendingPathComponent("session-a.json").path
        fileManager.blockNextRead(atPath: firstSessionPath)
        monitor.start()
        wait(for: [firstBlocked], timeout: 1.0)

        monitor.stop()

        try makeClaudeSessionFixture(
            fileManager: fileManager,
            sessionsDirURL: sessionsDirURL,
            projectsDirURL: projectsDirURL,
            bridgeDirURL: bridgeDirURL,
            sessionID: "session-b",
            cwd: "/workspace/beta",
            status: "waiting",
            waitingFor: "approve Edit",
            model: "kimi-k2.5",
            summary: "second startup refresh",
            usedPercent: 63,
            modifiedAt: Date()
        )

        let secondSessionPath = sessionsDirURL.appendingPathComponent("session-b.json").path
        fileManager.blockNextRead(atPath: secondSessionPath)
        monitor.start()
        fileManager.releaseBlockedRead()
        wait(for: [secondBlocked], timeout: 1.0)

        try makeClaudeSessionFixture(
            fileManager: fileManager,
            sessionsDirURL: sessionsDirURL,
            projectsDirURL: projectsDirURL,
            bridgeDirURL: bridgeDirURL,
            sessionID: "session-c",
            cwd: "/workspace/gamma",
            status: "waiting",
            waitingFor: "approve Bash",
            model: "claude-opus-4.1",
            summary: "event refresh after restart",
            usedPercent: 44,
            modifiedAt: Date().addingTimeInterval(1)
        )
        signalSource.emit()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))

        let debugState = monitor.debugRefreshState
        XCTAssertTrue(debugState.refreshInFlight)
        XCTAssertTrue(debugState.refreshDirty)

        fileManager.releaseBlockedRead()
        assertEventually {
            monitor.claudeState.threads.first?.id == "session-c"
        }
        monitor.stop()
    }

    private func makeClaudeSessionFixture(
        fileManager: FileManager,
        sessionsDirURL: URL,
        projectsDirURL: URL,
        bridgeDirURL: URL,
        sessionID: String,
        cwd: String,
        status: String,
        waitingFor: String?,
        model: String,
        summary: String,
        usedPercent: Int,
        modifiedAt: Date
    ) throws {
        let sessionPath = sessionsDirURL.appendingPathComponent("\(sessionID).json")
        let encodedCwd = cwd.replacingOccurrences(of: "/", with: "-")
        let transcriptDirURL = projectsDirURL.appendingPathComponent(encodedCwd, isDirectory: true)
        let transcriptPath = transcriptDirURL.appendingPathComponent("\(sessionID).jsonl")
        let bridgePath = bridgeDirURL.appendingPathComponent("claude-ctx-\(sessionID).json")

        try fileManager.createDirectory(at: transcriptDirURL, withIntermediateDirectories: true)

        let waitingField: String
        if let waitingFor {
            waitingField = #","waitingFor":"\#(waitingFor)""#
        } else {
            waitingField = ""
        }

        let sessionJSON = #"""
        {
          "pid": 4242,
          "sessionId": "\#(sessionID)",
          "cwd": "\#(cwd)",
          "status": "\#(status)"\#(waitingField)
        }
        """#
        try sessionJSON.data(using: .utf8)?.write(to: sessionPath)

        let transcriptJSONL = #"""
        {"type":"assistant","message":{"model":"\#(model)","usage":{"input_tokens":128},"stop_reason":"tool_use","content":[{"type":"tool_use","id":"tool-\#(sessionID)","name":"Read","input":{"file_path":"README.md"}}]}}
        {"type":"task-summary","summary":"\#(summary)","timestamp":"2026-04-11T10:00:00Z"}
        """#
        try transcriptJSONL.data(using: .utf8)?.write(to: transcriptPath)

        let bridgeJSON = """
        {
          "used_pct": \(usedPercent)
        }
        """
        try bridgeJSON.data(using: .utf8)?.write(to: bridgePath)

        try fileManager.setAttributes([.modificationDate: modifiedAt], ofItemAtPath: sessionPath.path)
        try fileManager.setAttributes([.modificationDate: modifiedAt], ofItemAtPath: transcriptPath.path)
        try fileManager.setAttributes([.modificationDate: modifiedAt], ofItemAtPath: bridgePath.path)
    }
}
