import XCTest

@testable import AIIslandApp
@testable import AIIslandCore

final class ClaudeMonitorArbitratorTests: XCTestCase {
    func testArbitratorPrefersLiveBusySessionsOverOlderIdleSessions() {
        let now = Date(timeIntervalSince1970: 1_713_000_000)
        let busy = makeSnapshot(
            sessionID: "session-busy",
            cwd: "/workspace/busy",
            observedAt: now.addingTimeInterval(-120),
            activity: ClaudeCodeSessionActivity(status: .busy, waitingFor: nil),
            transcript: ClaudeCodeTranscriptSnapshot(
                fallbackState: .working,
                modelLabel: "claude-sonnet-4",
                taskSummary: "Busy task",
                hasInProgressToolUse: true
            )
        )
        let idle = makeSnapshot(
            sessionID: "session-idle",
            cwd: "/workspace/idle",
            observedAt: now.addingTimeInterval(-30),
            activity: ClaudeCodeSessionActivity(status: .idle, waitingFor: nil),
            transcript: ClaudeCodeTranscriptSnapshot(
                fallbackState: .idle,
                modelLabel: "kimi-k2.5",
                taskSummary: "Idle task",
                hasInProgressToolUse: false
            )
        )

        let result = ClaudeMonitorArbitrator.compute(
            snapshots: [idle, busy],
            baseWatchedPaths: ["/tmp/claude"],
            cachedModels: [:],
            freshnessPolicy: .v02Smooth,
            now: now,
            trigger: "manual"
        )

        XCTAssertEqual(result.state.availability, .available)
        XCTAssertEqual(result.state.globalState, .working)
        XCTAssertEqual(result.state.threads.map(\.id), ["session-busy", "session-idle"])
    }

    func testArbitratorDegradesCoolingSessionsToIdleButKeepsThemVisible() {
        let now = Date(timeIntervalSince1970: 1_713_000_000)
        let cooling = makeSnapshot(
            sessionID: "session-cooling",
            cwd: "/workspace/cooling",
            observedAt: now.addingTimeInterval(-(4 * 60)),
            activity: ClaudeCodeSessionActivity(status: .waiting, waitingFor: "approve Edit"),
            transcript: ClaudeCodeTranscriptSnapshot(
                fallbackState: .attention,
                modelLabel: "claude-sonnet-4",
                taskSummary: "Cooling task",
                hasInProgressToolUse: false
            )
        )

        let result = ClaudeMonitorArbitrator.compute(
            snapshots: [cooling],
            baseWatchedPaths: ["/tmp/claude"],
            cachedModels: [:],
            freshnessPolicy: .v02Smooth,
            now: now,
            trigger: "manual"
        )

        XCTAssertEqual(result.state.availability, .available)
        XCTAssertEqual(result.state.globalState, .idle)
        XCTAssertEqual(result.state.threads.count, 1)
        XCTAssertEqual(result.state.threads.first?.state, .idle)
    }

    func testArbitratorHidesExpiredSessionsAndMarksStatusUnavailableWhenNothingLiveRemains() {
        let now = Date(timeIntervalSince1970: 1_713_000_000)
        let expired = makeSnapshot(
            sessionID: "session-expired",
            cwd: "/workspace/expired",
            observedAt: now.addingTimeInterval(-(50 * 60)),
            activity: ClaudeCodeSessionActivity(status: .busy, waitingFor: nil),
            transcript: ClaudeCodeTranscriptSnapshot(
                fallbackState: .working,
                modelLabel: "claude-sonnet-4",
                taskSummary: "Expired task",
                hasInProgressToolUse: true
            )
        )

        let result = ClaudeMonitorArbitrator.compute(
            snapshots: [expired],
            baseWatchedPaths: ["/tmp/claude"],
            cachedModels: [:],
            freshnessPolicy: .v02Smooth,
            now: now,
            trigger: "manual"
        )

        XCTAssertTrue(result.state.online)
        XCTAssertEqual(result.state.availability, .statusUnavailable)
        XCTAssertEqual(result.state.globalState, .idle)
        XCTAssertTrue(result.state.threads.isEmpty)
    }

    func testArbitratorKeepsLastKnownModelPerSessionDuringTransientTranscriptLoss() {
        let now = Date(timeIntervalSince1970: 1_713_000_000)
        let session = makeSnapshot(
            sessionID: "session-model-cache",
            cwd: "/workspace/model-cache",
            observedAt: now.addingTimeInterval(-20),
            activity: ClaudeCodeSessionActivity(status: .busy, waitingFor: nil),
            transcript: ClaudeCodeTranscriptSnapshot(
                fallbackState: .working,
                modelLabel: "claude-sonnet-4",
                taskSummary: "Warm cache",
                hasInProgressToolUse: true
            )
        )

        let firstResult = ClaudeMonitorArbitrator.compute(
            snapshots: [session],
            baseWatchedPaths: ["/tmp/claude"],
            cachedModels: [:],
            freshnessPolicy: .v02Smooth,
            now: now,
            trigger: "manual"
        )

        let lostModel = makeSnapshot(
            sessionID: "session-model-cache",
            cwd: "/workspace/model-cache",
            observedAt: now.addingTimeInterval(40),
            activity: ClaudeCodeSessionActivity(status: .busy, waitingFor: nil),
            transcript: ClaudeCodeTranscriptSnapshot(
                fallbackState: .working,
                modelLabel: nil,
                taskSummary: "Warm cache",
                hasInProgressToolUse: true
            )
        )

        let secondResult = ClaudeMonitorArbitrator.compute(
            snapshots: [lostModel],
            baseWatchedPaths: ["/tmp/claude"],
            cachedModels: firstResult.updatedModels,
            freshnessPolicy: .v02Smooth,
            now: now.addingTimeInterval(40),
            trigger: "manual"
        )

        XCTAssertEqual(firstResult.state.threads.first?.modelLabel, "claude-sonnet-4")
        XCTAssertEqual(secondResult.state.threads.first?.modelLabel, "claude-sonnet-4")
    }

    func testArbitratorUsesDeterministicTieBreakForPrimaryVisibleThreadAndGlobalState() {
        let now = Date(timeIntervalSince1970: 1_713_000_000)
        let observedAt = now.addingTimeInterval(-15)
        let sessionA = makeSnapshot(
            sessionID: "session-a",
            cwd: "/workspace/a",
            observedAt: observedAt,
            activity: ClaudeCodeSessionActivity(status: .waiting, waitingFor: "approve Bash"),
            transcript: ClaudeCodeTranscriptSnapshot(
                fallbackState: .attention,
                modelLabel: "claude-sonnet-4",
                taskSummary: "A task",
                hasInProgressToolUse: false
            )
        )
        let sessionB = makeSnapshot(
            sessionID: "session-b",
            cwd: "/workspace/b",
            observedAt: observedAt,
            activity: ClaudeCodeSessionActivity(status: .waiting, waitingFor: "approve Bash"),
            transcript: ClaudeCodeTranscriptSnapshot(
                fallbackState: .attention,
                modelLabel: "claude-sonnet-4",
                taskSummary: "B task",
                hasInProgressToolUse: false
            )
        )

        let result = ClaudeMonitorArbitrator.compute(
            snapshots: [sessionB, sessionA],
            baseWatchedPaths: ["/tmp/claude"],
            cachedModels: [:],
            freshnessPolicy: .v02Smooth,
            now: now,
            trigger: "manual"
        )

        XCTAssertEqual(result.state.globalState, .attention)
        XCTAssertEqual(result.state.threads.map(\.id), ["session-a", "session-b"])
    }

    func testArbitratorUsesClaudeTaskSummaryAsTitleAndWaitingForAsDetail() throws {
        let now = Date(timeIntervalSince1970: 1_713_000_000)
        let snapshot = makeSnapshot(
            sessionID: "session-claude-title",
            cwd: "/Users/chenyuanjie/developer/ai-dynamic-island-macos",
            observedAt: now.addingTimeInterval(-10),
            activity: ClaudeCodeSessionActivity(status: .waiting, waitingFor: "approve Bash"),
            transcript: ClaudeCodeTranscriptSnapshot(
                fallbackState: .attention,
                modelLabel: "claude-sonnet-4",
                taskSummary: "Claude 多线程仲裁",
                hasInProgressToolUse: false
            )
        )

        let result = ClaudeMonitorArbitrator.compute(
            snapshots: [snapshot],
            baseWatchedPaths: ["/tmp/claude"],
            cachedModels: [:],
            freshnessPolicy: .v02Smooth,
            now: now,
            trigger: "manual"
        )

        let thread = try XCTUnwrap(result.state.threads.first)
        XCTAssertEqual(thread.title, "Claude 多线程仲裁")
        XCTAssertEqual(thread.detail, "等待批准 Bash")
        XCTAssertEqual(thread.workspaceLabel, "ai-dynamic-island-macos")
        XCTAssertEqual(thread.titleSource, .claudeTaskSummary)
    }

    func testArbitratorUsesClaudePromptSummaryWhenTaskSummaryAndWorkspaceFallbackAreUnavailable() throws {
        let now = Date(timeIntervalSince1970: 1_713_000_000)
        let snapshot = makeSnapshot(
            sessionID: "session-claude-prompt-title",
            cwd: "/Users/chenyuanjie",
            observedAt: now.addingTimeInterval(-10),
            activity: ClaudeCodeSessionActivity(status: .waiting, waitingFor: "approve Bash"),
            transcript: ClaudeCodeTranscriptSnapshot(
                fallbackState: .attention,
                modelLabel: "claude-sonnet-4",
                taskSummary: nil,
                hasInProgressToolUse: false,
                lastPrompt: "按这份 plan 开始 coding",
                userPromptCandidates: ["排查 Claude 线程标题兜底"]
            )
        )

        let result = ClaudeMonitorArbitrator.compute(
            snapshots: [snapshot],
            baseWatchedPaths: ["/tmp/claude"],
            cachedModels: [:],
            freshnessPolicy: .v02Smooth,
            now: now,
            trigger: "manual"
        )

        let thread = try XCTUnwrap(result.state.threads.first)
        XCTAssertEqual(thread.title, "排查 Claude 线程标题兜底")
        XCTAssertEqual(thread.detail, "等待批准 Bash")
        XCTAssertNil(thread.workspaceLabel)
        XCTAssertEqual(thread.titleSource, .claudePromptSummary)
    }

    func testArbitratorDoesNotRenderThreadOnlyBecauseExecutionOnlyLastPromptExists() {
        let now = Date(timeIntervalSince1970: 1_713_000_000)
        let snapshot = makeSnapshot(
            sessionID: "session-noisy-last-prompt",
            cwd: "/Users/chenyuanjie",
            observedAt: now.addingTimeInterval(-10),
            activity: nil,
            transcript: ClaudeCodeTranscriptSnapshot(
                fallbackState: .idle,
                modelLabel: nil,
                taskSummary: nil,
                hasInProgressToolUse: false,
                lastPrompt: "按这份 plan 开始 coding",
                userPromptCandidates: []
            )
        )

        let result = ClaudeMonitorArbitrator.compute(
            snapshots: [snapshot],
            baseWatchedPaths: ["/tmp/claude"],
            cachedModels: [:],
            freshnessPolicy: .v02Smooth,
            now: now,
            trigger: "manual"
        )

        XCTAssertTrue(result.state.online)
        XCTAssertEqual(result.state.availability, .available)
        XCTAssertEqual(result.state.globalState, .idle)
        XCTAssertTrue(result.state.threads.isEmpty)
    }

    private func makeSnapshot(
        sessionID: String,
        cwd: String,
        observedAt: Date,
        activity: ClaudeCodeSessionActivity?,
        transcript: ClaudeCodeTranscriptSnapshot
    ) -> ClaudeMonitorSessionSnapshot {
        ClaudeMonitorSessionSnapshot(
            candidate: ClaudeSessionCandidate(
                pid: 4242,
                sessionID: sessionID,
                cwd: cwd,
                observedAt: observedAt,
                filePath: "/tmp/\(sessionID).json",
                activity: activity
            ),
            transcript: transcript,
            transcriptUpdatedAt: observedAt,
            transcriptPath: "/tmp/\(sessionID).jsonl",
            bridge: ClaudeBridgeSnapshot(
                contextRatio: 0.42,
                observedAt: observedAt,
                filePath: "/tmp/claude-ctx-\(sessionID).json"
            )
        )
    }
}
