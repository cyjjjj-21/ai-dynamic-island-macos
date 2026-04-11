import XCTest

@testable import AIIslandApp
@testable import AIIslandCore

final class FallbackRenderingRulesTests: XCTestCase {
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
                    taskLabel: "Tune island spacing",
                    modelLabel: "gpt-5.4-internal-preview-long-build-string",
                    contextRatio: 0.41,
                    state: .working
                ),
                AgentThread(
                    id: "two",
                    taskLabel: "Implement hover hotzone",
                    modelLabel: "gpt-5.4-mini",
                    contextRatio: 0.34,
                    state: .thinking
                ),
                AgentThread(
                    id: "three",
                    taskLabel: "Wire shell pin state",
                    modelLabel: "gpt-5.4",
                    contextRatio: 0.39,
                    state: .working
                ),
                AgentThread(
                    id: "four",
                    taskLabel: "Add quota fallback",
                    modelLabel: "gpt-5.4-mini",
                    contextRatio: 0.22,
                    state: .idle
                ),
                AgentThread(
                    id: "five",
                    taskLabel: "Record motion samples",
                    modelLabel: "gpt-5.4",
                    contextRatio: 0.27,
                    state: .idle
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
                    taskLabel: "Check provider context",
                    modelLabel: "kimi-k2.5-long-provider-build-2026-04-experimental",
                    contextRatio: nil,
                    state: .idle
                )
            ],
            quota: nil
        )

        let viewModel = AgentSectionPresentation(state: state)

        XCTAssertEqual(viewModel.visibleThreads.first?.contextCopy, "Context --")
        XCTAssertEqual(viewModel.visibleThreads.first?.modelLabel, "Kimi K2.5")
    }
}
