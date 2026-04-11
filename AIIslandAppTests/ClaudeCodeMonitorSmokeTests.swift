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

        let oldDate = Date().addingTimeInterval(-16 * 60)
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

        let oldDate = Date().addingTimeInterval(-31 * 60)
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
}
