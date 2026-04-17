import XCTest

@testable import AIIslandApp
@testable import AIIslandCore

final class ThreadTitleResolverTests: XCTestCase {
    func testResolverRejectsCodexSessionIndexTitleContainingHTMLFragments() {
        let result = ThreadTitleResolver.resolveCodexTitle(
            prompts: ["查找自动化未读消息来源"],
            sessionIndexTitle: "查找自动化未读消息来源<br>ꕥꕥ ti...",
            workspacePath: "/Users/chenyuanjie/developer/ai-dynamic-island-macos",
            latestAssistantMessage: nil
        )

        XCTAssertEqual(result.title, "自动化未读消息排查")
        XCTAssertEqual(result.source, .codexPromptSummary)
    }

    func testResolverRejectsUsernameOnlyWorkspaceFallback() {
        XCTAssertNil(ThreadTitleResolver.resolveWorkspaceLabel(from: "/Users/chenyuanjie"))
    }

    func testResolverUsesTaskSummaryForClaudeTitleAndWaitingForForDetail() {
        let result = ThreadTitleResolver.resolveClaudeTitle(
            taskSummary: "Claude 多线程仲裁",
            promptCandidates: [],
            lastPrompt: nil,
            waitingFor: "approve Bash",
            workspacePath: "/Users/chenyuanjie/developer/ai-dynamic-island-macos"
        )

        XCTAssertEqual(result.title, "Claude 多线程仲裁")
        XCTAssertEqual(result.detail, "等待批准 Bash")
        XCTAssertEqual(result.workspaceLabel, "ai-dynamic-island-macos")
        XCTAssertEqual(result.source, .claudeTaskSummary)
    }

    func testResolverCleansClaudeTaskSummaryBeforeViabilityCheck() {
        let result = ThreadTitleResolver.resolveClaudeTitle(
            taskSummary: "Claude 线程标题 fallback<br>   ",
            promptCandidates: ["排查 Claude prompt fallback"],
            lastPrompt: nil,
            waitingFor: nil,
            workspacePath: "/Users/chenyuanjie"
        )

        XCTAssertEqual(result.title, "Claude 线程标题 fallback")
        XCTAssertEqual(result.source, .claudeTaskSummary)
    }

    func testResolverUsesClaudePromptSummaryBeforeUsernameOnlyWorkspaceFallback() {
        let result = ThreadTitleResolver.resolveClaudeTitle(
            taskSummary: nil,
            promptCandidates: ["排查 Claude 线程标题兜底"],
            lastPrompt: nil,
            waitingFor: nil,
            workspacePath: "/Users/chenyuanjie"
        )

        XCTAssertEqual(result.title, "排查 Claude 线程标题兜底")
        XCTAssertEqual(result.source, .claudePromptSummary)
        XCTAssertNil(result.workspaceLabel)
    }

    func testResolverDoesNotLetExecutionOnlyClaudeLastPromptOverrideTopicPrompt() {
        let result = ThreadTitleResolver.resolveClaudeTitle(
            taskSummary: nil,
            promptCandidates: ["排查 Claude 线程标题兜底"],
            lastPrompt: "按这份 plan 开始 coding",
            waitingFor: nil,
            workspacePath: "/Users/chenyuanjie"
        )

        XCTAssertEqual(result.title, "排查 Claude 线程标题兜底")
        XCTAssertEqual(result.source, .claudePromptSummary)
    }

    func testResolverSkipsNoiseOnlyPromptsAndFallsBackToSessionHint() {
        let result = ThreadTitleResolver.resolveCodexTitle(
            prompts: ["继续", "review", "go", "ok"],
            sessionIndexTitle: "整理 AI Dynamic Island 改进清单",
            workspacePath: "/Users/chenyuanjie/developer/ai-dynamic-island-macos",
            latestAssistantMessage: nil
        )

        XCTAssertEqual(result.title, "整理 AI Dynamic Island 改进清单")
        XCTAssertEqual(result.source, .codexSessionIndexHint)
    }

    func testResolverCleansCodexSessionIndexTitleBeforeViabilityCheck() {
        let result = ThreadTitleResolver.resolveCodexTitle(
            prompts: [],
            sessionIndexTitle: "审查 Claude 线程标题 fallback<br>   ",
            workspacePath: "/Users/chenyuanjie",
            latestAssistantMessage: nil
        )

        XCTAssertEqual(result.title, "审查 Claude 线程标题 fallback")
        XCTAssertEqual(result.source, .codexSessionIndexHint)
    }

    func testResolverTrimsCodexSessionIndexTitleAtHTMLBreakBeforeGarbledTail() {
        let result = ThreadTitleResolver.resolveCodexTitle(
            prompts: [],
            sessionIndexTitle: "查找自动化未读消息来源<br>ꕥꕥ ti...",
            workspacePath: "/Users/chenyuanjie/developer/ai-dynamic-island-macos",
            latestAssistantMessage: nil
        )

        XCTAssertEqual(result.title, "查找自动化未读消息来源")
        XCTAssertEqual(result.source, .codexSessionIndexHint)
    }

    func testResolverTrimsCodexSessionIndexTitleAtHTMLBreakVariants() {
        let slashBreak = ThreadTitleResolver.resolveCodexTitle(
            prompts: [],
            sessionIndexTitle: "审查 Codex 标题 fallback<br/>ꕥꕥ ti...",
            workspacePath: "/Users/chenyuanjie/developer/ai-dynamic-island-macos",
            latestAssistantMessage: nil
        )
        let spacedBreak = ThreadTitleResolver.resolveCodexTitle(
            prompts: [],
            sessionIndexTitle: "审查 Claude 标题 fallback<br />ꕥꕥ ti...",
            workspacePath: "/Users/chenyuanjie/developer/ai-dynamic-island-macos",
            latestAssistantMessage: nil
        )

        XCTAssertEqual(slashBreak.title, "审查 Codex 标题 fallback")
        XCTAssertEqual(spacedBreak.title, "审查 Claude 标题 fallback")
        XCTAssertEqual(slashBreak.source, .codexSessionIndexHint)
        XCTAssertEqual(spacedBreak.source, .codexSessionIndexHint)
    }

    func testResolverDoesNotApplyCodexQuotaRewriteToClaudePromptCandidates() {
        let result = ThreadTitleResolver.resolveClaudeTitle(
            taskSummary: nil,
            promptCandidates: ["梳理配额展示优化方案"],
            lastPrompt: nil,
            waitingFor: nil,
            workspacePath: "/Users/chenyuanjie"
        )

        XCTAssertEqual(result.title, "梳理配额展示优化方案")
        XCTAssertEqual(result.source, .claudePromptSummary)
    }

    func testResolverKeepsLegitimateComparisonSyntaxInPromptTitles() {
        let result = ThreadTitleResolver.resolveCodexTitle(
            prompts: ["修复 x < y 比较逻辑"],
            sessionIndexTitle: nil,
            workspacePath: "/Users/chenyuanjie/developer/ai-dynamic-island-macos",
            latestAssistantMessage: nil
        )

        XCTAssertEqual(result.title, "修复 x < y 比较逻辑")
        XCTAssertEqual(result.source, .codexPromptSummary)
    }

    func testResolverPrefersNewestViablePromptInsteadOfOldestOne() {
        let result = ThreadTitleResolver.resolveCodexTitle(
            prompts: [
                "整理 AI Dynamic Island 改进清单",
                "继续把 Codex 配额展示做扎实"
            ],
            sessionIndexTitle: nil,
            workspacePath: "/Users/chenyuanjie/developer/ai-dynamic-island-macos",
            latestAssistantMessage: nil
        )

        XCTAssertEqual(result.title, "Codex 配额展示优化")
        XCTAssertEqual(result.source, .codexPromptSummary)
    }

    func testResolverUsesRepositoryNameForWorktreePathsAndGenericUserHomes() {
        XCTAssertEqual(
            ThreadTitleResolver.resolveWorkspaceLabel(
                from: "/Users/alice/developer/ai-dynamic-island-macos/.worktrees/visual-polish-steady-premium"
            ),
            "ai-dynamic-island-macos"
        )
        XCTAssertEqual(
            ThreadTitleResolver.resolveWorkspaceLabel(from: "/home/bob/projects/telemetry-dashboard"),
            "telemetry-dashboard"
        )
        XCTAssertNil(ThreadTitleResolver.resolveWorkspaceLabel(from: "/Users/alice"))
    }

    func testResolverSkipsExecutionOnlyPromptAndKeepsOlderTaskTopic() {
        let result = ThreadTitleResolver.resolveCodexTitle(
            prompts: [
                "整理 AI Dynamic Island 改进清单",
                "按这份 plan 开始 coding"
            ],
            sessionIndexTitle: nil,
            workspacePath: "/Users/chenyuanjie/developer/ai-dynamic-island-macos",
            latestAssistantMessage: nil
        )

        XCTAssertEqual(result.title, "AI Dynamic Island 优化")
        XCTAssertEqual(result.source, .codexPromptSummary)
    }

    func testResolverPrefersEarlierTopicPromptOverLaterFollowUpPrompts() {
        let result = ThreadTitleResolver.resolveCodexTitle(
            prompts: [
                "梳理线程命名和展示的改进方案",
                "好的，那你准备具体怎么去做？",
                "go"
            ],
            sessionIndexTitle: nil,
            workspacePath: "/Users/chenyuanjie/developer",
            latestAssistantMessage: nil
        )

        XCTAssertEqual(result.title, "梳理线程命名和展示的改进方案")
        XCTAssertEqual(result.source, .codexPromptSummary)
        XCTAssertNil(result.workspaceLabel)
    }

    func testResolverKeepsContainerWorkspaceFallbackOutOfPrimaryTitle() {
        let result = ThreadTitleResolver.resolveCodexTitle(
            prompts: [],
            sessionIndexTitle: nil,
            workspacePath: "/Users/chenyuanjie/developer",
            latestAssistantMessage: nil
        )

        XCTAssertEqual(result.title, "Codex 任务")
        XCTAssertEqual(result.source, .unknown)
        XCTAssertNil(result.workspaceLabel)
    }

    func testResolverRejectsAbsolutePathSessionIndexTitleAndFallsBackToWorkspaceLabel() {
        let result = ThreadTitleResolver.resolveCodexTitle(
            prompts: [],
            sessionIndexTitle: "/Users/alice/project-x",
            workspacePath: "/Users/alice/project-x",
            latestAssistantMessage: nil
        )

        XCTAssertEqual(result.title, "project-x")
        XCTAssertEqual(result.source, .workspaceFallback)
    }

    func testResolverRejectsUndefinedPromptAndUsesSessionIndexTitle() {
        let result = ThreadTitleResolver.resolveCodexTitle(
            prompts: ["undefined"],
            sessionIndexTitle: "整理 AI Dynamic Island 改进清单",
            workspacePath: "/Users/chenyuanjie/developer/ai-dynamic-island-macos",
            latestAssistantMessage: nil
        )

        XCTAssertEqual(result.title, "整理 AI Dynamic Island 改进清单")
        XCTAssertEqual(result.source, .codexSessionIndexHint)
    }

    func testResolverRejectsUndefinedSessionIndexTitleAndFallsBackToWorkspaceLabel() {
        let result = ThreadTitleResolver.resolveCodexTitle(
            prompts: [],
            sessionIndexTitle: "undefined",
            workspacePath: "/Users/alice/project-x",
            latestAssistantMessage: nil
        )

        XCTAssertEqual(result.title, "project-x")
        XCTAssertEqual(result.source, .workspaceFallback)
    }

    func testResolverRejectsUndefinedWorkspaceFallback() {
        let result = ThreadTitleResolver.resolveCodexTitle(
            prompts: [],
            sessionIndexTitle: nil,
            workspacePath: "undefined",
            latestAssistantMessage: nil
        )

        XCTAssertEqual(result.title, "Codex 任务")
        XCTAssertEqual(result.source, .unknown)
        XCTAssertNil(result.workspaceLabel)
    }

    func testResolverRejectsSubagentNotificationPromptAndKeepsTopicTitle() {
        let notification = """
        <subagent_notification>
        {"agent_path":"019d9b3d-8e8f-73b2-aa77-8b73d3088e77","status":{"completed":"::code-comment{title=\\"[P2] review finding\\"}"}}
        </subagent_notification>
        """

        let result = ThreadTitleResolver.resolveCodexTitle(
            prompts: [
                "整理 AI Dynamic Island 改进清单",
                notification
            ],
            sessionIndexTitle: "整理 AI Dynamic Island 改进清单",
            workspacePath: "/Users/chenyuanjie/developer/ai-dynamic-island-macos",
            latestAssistantMessage: nil
        )

        XCTAssertEqual(result.title, "AI Dynamic Island 优化")
        XCTAssertEqual(result.source, .codexPromptSummary)
    }

    func testResolverRejectsRawAgentPathJSONSessionTitle() {
        let result = ThreadTitleResolver.resolveCodexTitle(
            prompts: [],
            sessionIndexTitle: "{\"agent_path\":\"019d9b3d-8e8f\",\"status\":{\"completed\":\"review\"}}",
            workspacePath: "/Users/chenyuanjie/developer/ai-dynamic-island-macos",
            latestAssistantMessage: nil
        )

        XCTAssertEqual(result.title, "ai-dynamic-island-macos")
        XCTAssertEqual(result.source, .workspaceFallback)
    }
}
