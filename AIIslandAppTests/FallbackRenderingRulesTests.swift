import XCTest

@testable import AIIslandApp
@testable import AIIslandCore

final class FallbackRenderingRulesTests: XCTestCase {
    func testThreadPresentationUsesStableTitleAndSeparateDetail() {
        let now = Date(timeIntervalSince1970: 1_713_000_018)
        let thread = AgentThread(
            id: "thread-1",
            title: "Codex 配额展示优化",
            detail: "执行工具中",
            workspaceLabel: "ai-dynamic-island-macos",
            modelLabel: "gpt-5.4",
            contextRatio: 0.42,
            state: .working,
            lastUpdatedAt: Date(timeIntervalSince1970: 1_713_000_000),
            titleSource: .codexPromptSummary
        )

        let row = ThreadRowPresentation(thread: thread, isPrimary: true, now: now)

        XCTAssertEqual(row.threadTitle, "Codex 配额展示优化")
        XCTAssertEqual(row.detailCopy, "执行工具中")
        XCTAssertEqual(row.recencyCopy, "18s")
        XCTAssertEqual(row.contextCopy, "Context 42%")
        XCTAssertEqual(row.modelLabel, "GPT-5.4")
    }

    func testSectionPresentationMarksOnlyFirstVisibleThreadAsPrimary() {
        let now = Date(timeIntervalSince1970: 1_713_000_120)
        let state = AgentState(
            kind: .codex,
            online: true,
            availability: .available,
            globalState: .working,
            threads: [
                AgentThread(
                    id: "primary",
                    title: "Codex 配额展示优化",
                    detail: "执行工具中",
                    workspaceLabel: "ai-dynamic-island-macos",
                    modelLabel: "gpt-5.4",
                    contextRatio: 0.42,
                    state: .working,
                    lastUpdatedAt: now.addingTimeInterval(-12),
                    titleSource: .codexPromptSummary
                ),
                AgentThread(
                    id: "secondary-a",
                    title: "Claude 多线程仲裁",
                    detail: "等待批准 Bash",
                    workspaceLabel: "ai-dynamic-island-macos",
                    modelLabel: "claude-sonnet-4",
                    contextRatio: 0.31,
                    state: .attention,
                    lastUpdatedAt: now.addingTimeInterval(-30),
                    titleSource: .claudeTaskSummary
                ),
                AgentThread(
                    id: "secondary-b",
                    title: "自动化未读消息排查",
                    detail: "最近活跃",
                    workspaceLabel: "ai-dynamic-island-macos",
                    modelLabel: "gpt-5.4-mini",
                    contextRatio: 0.19,
                    state: .idle,
                    lastUpdatedAt: now.addingTimeInterval(-48),
                    titleSource: .codexPromptSummary
                )
            ],
            quota: nil
        )

        let presentation = AgentSectionPresentation(state: state, now: now)

        XCTAssertEqual(presentation.visibleThreads.count, 3)
        XCTAssertEqual(presentation.visibleThreads.map { $0.isPrimary }, [true, false, false])
    }

    func testOfflineTakesPrecedenceOverQuotaUnavailableCopy() {
        let state = AgentState(
            kind: .codex,
            online: false,
            availability: .offline,
            globalState: .offline,
            threads: [],
            quota: AgentQuota(
                availability: .unavailable,
                fiveHourRatio: nil,
                weeklyRatio: nil
            )
        )

        let viewModel = AgentSectionPresentation(state: state)

        XCTAssertEqual(viewModel.primaryStatusCopy, "Not running")
        XCTAssertNil(viewModel.quotaPresentation)
        XCTAssertNil(viewModel.overflowSummaryCopy)
        XCTAssertTrue(viewModel.visibleThreads.isEmpty)
    }

    func testStatusUnavailableTakesPrecedenceOverIdleCopy() {
        let state = AgentState(
            kind: .codex,
            online: true,
            availability: .statusUnavailable,
            globalState: .idle,
            threads: [],
            quota: AgentQuota(
                availability: .unavailable,
                fiveHourRatio: nil,
                weeklyRatio: nil
            )
        )

        let viewModel = AgentSectionPresentation(state: state)

        XCTAssertEqual(viewModel.primaryStatusCopy, "Status unavailable")
        XCTAssertEqual(viewModel.quotaPresentation?.availabilityCopy, "Quota unavailable")
    }

    func testQuotaUnavailableStillRendersSectionFallbackForCodex() {
        let state = AgentState(
            kind: .codex,
            online: true,
            availability: .available,
            globalState: .idle,
            threads: [],
            quota: AgentQuota(
                availability: .unavailable,
                fiveHourRatio: nil,
                weeklyRatio: nil
            )
        )

        let viewModel = AgentSectionPresentation(state: state)

        XCTAssertEqual(viewModel.primaryStatusCopy, "Idle")
        XCTAssertEqual(viewModel.quotaPresentation?.availabilityCopy, "Quota unavailable")
    }

    func testThreadOverflowKeepsTopThreeAndAddsSummary() {
        let state = AgentState(
            kind: .codex,
            online: true,
            availability: .available,
            globalState: .working,
            threads: [
                AgentThread(
                    id: "one",
                    title: "Tune island spacing",
                    detail: nil,
                    workspaceLabel: nil,
                    modelLabel: "gpt-5.4-internal-preview-long-build-string",
                    contextRatio: 0.41,
                    state: .working,
                    lastUpdatedAt: nil,
                    titleSource: .unknown
                ),
                AgentThread(
                    id: "two",
                    title: "Implement hover hotzone",
                    detail: nil,
                    workspaceLabel: nil,
                    modelLabel: "gpt-5.4-mini",
                    contextRatio: 0.34,
                    state: .thinking,
                    lastUpdatedAt: nil,
                    titleSource: .unknown
                ),
                AgentThread(
                    id: "three",
                    title: "Wire shell pin state",
                    detail: nil,
                    workspaceLabel: nil,
                    modelLabel: "gpt-5.4",
                    contextRatio: 0.39,
                    state: .working,
                    lastUpdatedAt: nil,
                    titleSource: .unknown
                ),
                AgentThread(
                    id: "four",
                    title: "Add quota fallback",
                    detail: nil,
                    workspaceLabel: nil,
                    modelLabel: "gpt-5.4-mini",
                    contextRatio: 0.22,
                    state: .idle,
                    lastUpdatedAt: nil,
                    titleSource: .unknown
                ),
                AgentThread(
                    id: "five",
                    title: "Record motion samples",
                    detail: nil,
                    workspaceLabel: nil,
                    modelLabel: "gpt-5.4",
                    contextRatio: 0.27,
                    state: .idle,
                    lastUpdatedAt: nil,
                    titleSource: .unknown
                )
            ],
            quota: AgentQuota(
                availability: .available,
                fiveHourRatio: 0.58,
                weeklyRatio: 0.69
            )
        )

        let viewModel = AgentSectionPresentation(state: state)

        XCTAssertEqual(viewModel.visibleThreads.count, 3)
        XCTAssertEqual(viewModel.overflowSummaryCopy, "+2 more")
        XCTAssertEqual(viewModel.visibleThreads.first?.modelLabel, "GPT-5.4")
    }

    func testMissingContextRendersPlaceholderCopy() {
        let state = AgentState(
            kind: .claude,
            online: true,
            availability: .available,
            globalState: .idle,
            threads: [
                AgentThread(
                    id: "claude-context-gap",
                    title: "Check provider context",
                    detail: nil,
                    workspaceLabel: nil,
                    modelLabel: "kimi-k2.5-long-provider-build-2026-04-experimental",
                    contextRatio: nil,
                    state: .idle,
                    lastUpdatedAt: nil,
                    titleSource: .unknown
                )
            ],
            quota: nil
        )

        let viewModel = AgentSectionPresentation(state: state)

        XCTAssertEqual(viewModel.visibleThreads.first?.contextCopy, "Context --")
        XCTAssertEqual(viewModel.visibleThreads.first?.modelLabel, "Kimi K2.5")
    }
}
