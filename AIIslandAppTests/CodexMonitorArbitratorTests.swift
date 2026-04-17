import XCTest

@testable import AIIslandApp
@testable import AIIslandCore

final class CodexMonitorArbitratorTests: XCTestCase {
    func testArbitratorPublishesStatusUnavailableWhenOnlyFallbackIndexThreadsExist() {
        let now = Date(timeIntervalSince1970: 1_713_000_000)

        let result = CodexMonitorArbitrator.compute(
            indexedThreads: [
                CodexIndexedThread(threadID: "thread-a", threadName: "Fallback A", updatedAt: now),
                CodexIndexedThread(threadID: "thread-b", threadName: "Fallback B", updatedAt: now.addingTimeInterval(-60))
            ],
            parsedSnapshots: [],
            hasReadableArtifacts: true,
            cachedModels: [:],
            freshnessPolicy: .v02Smooth,
            now: now,
            trigger: "manual"
        )

        XCTAssertTrue(result.state.online)
        XCTAssertEqual(result.state.availability, .statusUnavailable)
        XCTAssertEqual(result.state.globalState, .idle)
        XCTAssertEqual(result.state.threads.map(\.id), ["thread-a", "thread-b"])
        XCTAssertEqual(result.state.quota?.availability, .unavailable)
    }

    func testArbitratorPrefersAttentionThenWorkingThenThinkingThenIdle() {
        let now = Date(timeIntervalSince1970: 1_713_000_000)

        let result = CodexMonitorArbitrator.compute(
            indexedThreads: [],
            parsedSnapshots: [
                makeSnapshot(sessionID: "idle", state: .idle, updatedAt: now.addingTimeInterval(-10)),
                makeSnapshot(sessionID: "thinking", state: .thinking, updatedAt: now.addingTimeInterval(-15)),
                makeSnapshot(sessionID: "working", state: .working, updatedAt: now.addingTimeInterval(-20)),
                makeSnapshot(sessionID: "attention", state: .attention, updatedAt: now.addingTimeInterval(-25))
            ],
            hasReadableArtifacts: true,
            cachedModels: [:],
            freshnessPolicy: .v02Smooth,
            now: now,
            trigger: "manual"
        )

        XCTAssertEqual(result.state.availability, .available)
        XCTAssertEqual(result.state.globalState, .attention)
        XCTAssertEqual(result.state.threads.map(\.id), ["attention", "working", "thinking"])
    }

    func testArbitratorSelectsQuotaFromNewestLiveSnapshotWithTokenSignals() {
        let now = Date(timeIntervalSince1970: 1_713_000_000)

        let older = makeSnapshot(
            sessionID: "older",
            state: .working,
            updatedAt: now.addingTimeInterval(-90),
            fiveHourRatio: 0.70,
            weeklyRatio: 0.80,
            hasStructuredTokenSignal: true
        )
        let newer = makeSnapshot(
            sessionID: "newer",
            state: .thinking,
            updatedAt: now.addingTimeInterval(-30),
            fiveHourRatio: 0.55,
            weeklyRatio: 0.65,
            hasStructuredTokenSignal: true
        )

        let result = CodexMonitorArbitrator.compute(
            indexedThreads: [],
            parsedSnapshots: [older, newer],
            hasReadableArtifacts: true,
            cachedModels: [:],
            freshnessPolicy: .v02Smooth,
            now: now,
            trigger: "manual"
        )

        let quota = try? XCTUnwrap(result.state.quota)
        XCTAssertEqual(quota?.availability, .available)
        XCTAssertEqual((try? XCTUnwrap(quota?.fiveHourRatio)) ?? -1, 0.55, accuracy: 0.0001)
        XCTAssertEqual((try? XCTUnwrap(quota?.weeklyRatio)) ?? -1, 0.65, accuracy: 0.0001)
    }

    func testArbitratorCarriesForwardNewestQuotaResetTimes() throws {
        let now = Date(timeIntervalSince1970: 1_713_000_000)
        let olderReset = Date(timeIntervalSince1970: 1_776_250_000)
        let newerPrimaryReset = Date(timeIntervalSince1970: 1_776_282_138)
        let newerWeeklyReset = Date(timeIntervalSince1970: 1_776_475_167)

        let older = makeSnapshot(
            sessionID: "older",
            state: .working,
            updatedAt: now.addingTimeInterval(-90),
            fiveHourRatio: 0.70,
            weeklyRatio: 0.80,
            fiveHourResetsAt: olderReset,
            weeklyResetsAt: olderReset,
            hasStructuredTokenSignal: true
        )
        let newer = makeSnapshot(
            sessionID: "newer",
            state: .thinking,
            updatedAt: now.addingTimeInterval(-30),
            fiveHourRatio: 0.55,
            weeklyRatio: 0.65,
            fiveHourResetsAt: newerPrimaryReset,
            weeklyResetsAt: newerWeeklyReset,
            hasStructuredTokenSignal: true
        )

        let result = CodexMonitorArbitrator.compute(
            indexedThreads: [],
            parsedSnapshots: [older, newer],
            hasReadableArtifacts: true,
            cachedModels: [:],
            freshnessPolicy: .v02Smooth,
            now: now,
            trigger: "manual"
        )

        let quota = try XCTUnwrap(result.state.quota)
        XCTAssertEqual(quota.fiveHourResetsAt, newerPrimaryReset)
        XCTAssertEqual(quota.weeklyResetsAt, newerWeeklyReset)
    }

    func testArbitratorBuildsDiagnosticsFromRecentParsedSnapshots() {
        let now = Date(timeIntervalSince1970: 1_713_000_000)
        let result = CodexMonitorArbitrator.compute(
            indexedThreads: [],
            parsedSnapshots: [
                makeSnapshot(sessionID: "thread-a", state: .working, updatedAt: now.addingTimeInterval(-10)),
                makeSnapshot(sessionID: "thread-b", state: .thinking, updatedAt: now.addingTimeInterval(-20), trustLevel: .recentIndexFallback, hasStructuredActivitySignal: false),
                makeSnapshot(sessionID: "thread-c", state: .idle, updatedAt: now.addingTimeInterval(-30), modelLabel: "")
            ],
            hasReadableArtifacts: true,
            cachedModels: [:],
            freshnessPolicy: .v02Smooth,
            now: now,
            trigger: "manual"
        )

        XCTAssertEqual(result.diagnostics.threads.map(\.id), ["thread-a", "thread-b", "thread-c"])
        XCTAssertTrue(result.diagnostics.threads.first?.sourceHits.contains("activity") == true)
        XCTAssertTrue(result.diagnostics.threads[1].sourceHits.contains("index"))
    }

    func testArbitratorSuppressesFallbackThreadsWhenOnlyExpiredEventDerivedSnapshotsExist() {
        let now = Date(timeIntervalSince1970: 1_713_000_000)
        let expiredEvent = makeSnapshot(
            sessionID: "expired-event",
            state: .working,
            updatedAt: now.addingTimeInterval(-(50 * 60))
        )

        let result = CodexMonitorArbitrator.compute(
            indexedThreads: [
                CodexIndexedThread(threadID: "fallback-thread", threadName: "Fallback", updatedAt: now)
            ],
            parsedSnapshots: [expiredEvent],
            hasReadableArtifacts: true,
            cachedModels: [:],
            freshnessPolicy: .v02Smooth,
            now: now,
            trigger: "manual"
        )

        XCTAssertEqual(result.state.availability, .statusUnavailable)
        XCTAssertEqual(result.state.globalState, .idle)
        XCTAssertTrue(result.state.threads.isEmpty)
    }

    func testArbitratorResolvesStableTitleAndWorkspaceMetadataForCodexThreads() throws {
        let now = Date(timeIntervalSince1970: 1_713_000_000)

        let result = CodexMonitorArbitrator.compute(
            indexedThreads: [],
            parsedSnapshots: [
                makeSnapshot(
                    sessionID: "thread-codex",
                    state: .working,
                    updatedAt: now.addingTimeInterval(-8),
                    promptCandidates: ["继续把 Codex 配额展示做扎实", "顺便修一下配额刷新时间的对齐"],
                    titleHint: "查找自动化未读消息来源<br>ꕥꕥ ti...",
                    workspacePath: "/Users/chenyuanjie/developer/ai-dynamic-island-macos"
                )
            ],
            subagentActivityByParentID: [:],
            hasReadableArtifacts: true,
            cachedModels: [:],
            freshnessPolicy: .v02Smooth,
            now: now,
            trigger: "manual"
        )

        let thread = try XCTUnwrap(result.state.threads.first)
        XCTAssertEqual(thread.title, "Codex 配额展示优化")
        XCTAssertEqual(thread.workspaceLabel, "ai-dynamic-island-macos")
        XCTAssertEqual(thread.titleSource, .codexPromptSummary)
    }

    func testArbitratorFoldsSubagentActivityIntoParentDetailWithoutAddingRows() {
        let now = Date(timeIntervalSince1970: 1_713_000_000)

        let result = CodexMonitorArbitrator.compute(
            indexedThreads: [],
            parsedSnapshots: [
                makeSnapshot(
                    sessionID: "thread-main",
                    state: .working,
                    updatedAt: now.addingTimeInterval(-5),
                    promptCandidates: ["评估 ai dynamic island 优化方向"],
                    workspacePath: "/Users/chenyuanjie/developer/ai-dynamic-island-macos"
                )
            ],
            subagentActivityByParentID: [
                "thread-main": CodexSubagentActivity(
                    parentThreadID: "thread-main",
                    activeCount: 2,
                    latestUpdatedAt: now.addingTimeInterval(-2)
                )
            ],
            hasReadableArtifacts: true,
            cachedModels: [:],
            freshnessPolicy: .v02Smooth,
            now: now,
            trigger: "manual"
        )

        XCTAssertEqual(result.state.threads.count, 1)
        XCTAssertEqual(result.state.threads.first?.detail, "2 个子任务有更新")
    }

    func testArbitratorKeepsPrimaryDetailReadableWhenSubagentSummaryWouldOverflow() {
        let now = Date(timeIntervalSince1970: 1_713_000_000)

        let result = CodexMonitorArbitrator.compute(
            indexedThreads: [],
            parsedSnapshots: [
                makeSnapshot(
                    sessionID: "thread-main",
                    state: .attention,
                    updatedAt: now.addingTimeInterval(-5),
                    promptCandidates: ["评估 ai dynamic island 优化方向"],
                    workspacePath: "/Users/chenyuanjie/developer/ai-dynamic-island-macos",
                    latestAssistantMessage: "Need your approval before I continue."
                )
            ],
            subagentActivityByParentID: [
                "thread-main": CodexSubagentActivity(
                    parentThreadID: "thread-main",
                    activeCount: 2,
                    latestUpdatedAt: now.addingTimeInterval(-2)
                )
            ],
            hasReadableArtifacts: true,
            cachedModels: [:],
            freshnessPolicy: .v02Smooth,
            now: now,
            trigger: "manual"
        )

        XCTAssertEqual(result.state.threads.count, 1)
        XCTAssertEqual(result.state.threads.first?.detail, "等待你的确认")
    }

    private func makeSnapshot(
        sessionID: String,
        state: AgentGlobalState,
        updatedAt: Date,
        modelLabel: String = "gpt-5.4",
        fiveHourRatio: Double? = nil,
        weeklyRatio: Double? = nil,
        fiveHourResetsAt: Date? = nil,
        weeklyResetsAt: Date? = nil,
        trustLevel: CodexSnapshotTrustLevel = .eventDerived,
        hasStructuredTokenSignal: Bool = false,
        hasStructuredActivitySignal: Bool = true,
        promptCandidates: [String] = [],
        titleHint: String? = nil,
        workspacePath: String? = nil,
        latestAssistantMessage: String? = nil
    ) -> CodexSessionSnapshot {
        CodexSessionSnapshot(
            sessionID: sessionID,
            taskLabel: sessionID,
            modelLabel: modelLabel,
            contextRatio: 0.25,
            fiveHourRatio: fiveHourRatio,
            weeklyRatio: weeklyRatio,
            fiveHourResetsAt: fiveHourResetsAt,
            weeklyResetsAt: weeklyResetsAt,
            state: state,
            updatedAt: updatedAt,
            trustLevel: trustLevel,
            hasStructuredTokenSignal: hasStructuredTokenSignal,
            hasStructuredActivitySignal: hasStructuredActivitySignal,
            promptCandidates: promptCandidates,
            titleHint: titleHint,
            workspacePath: workspacePath,
            latestAssistantMessage: latestAssistantMessage
        )
    }
}
