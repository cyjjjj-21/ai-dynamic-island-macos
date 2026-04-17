import XCTest

@testable import AIIslandApp

final class ClaudeCodeSnapshotParserTests: XCTestCase {
    func testParseSessionActivityExtractsBusyAndWaitingReason() throws {
        let data = try XCTUnwrap(
            """
            {
              "pid": 4242,
              "sessionId": "session-1",
              "cwd": "/workspace/ai-dynamic-island-macos",
              "status": "waiting",
              "waitingFor": "approve Bash",
              "updatedAt": 1712800000000
            }
            """.data(using: .utf8)
        )

        let activity = try XCTUnwrap(ClaudeCodeSnapshotParser.parseSessionActivity(from: data))

        XCTAssertEqual(activity.status, .waiting)
        XCTAssertEqual(activity.waitingFor, "approve Bash")
    }

    func testParseTranscriptTailExtractsTaskSummaryModelAndInProgressToolUse() {
        let transcript = """
        {"type":"assistant","message":{"model":"kimi-k2.5","usage":{"input_tokens":128},"stop_reason":"tool_use","content":[{"type":"tool_use","id":"tool-1","name":"Read","input":{"file_path":"README.md"}}]}}
        {"type":"task-summary","summary":"Audit Claude session state plumbing","timestamp":"2026-04-11T09:00:00Z"}
        {"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"tool-2","content":"done"}]}}
        """

        let snapshot = ClaudeCodeSnapshotParser.parseTranscriptTail(transcript)

        XCTAssertEqual(snapshot.modelLabel, "kimi-k2.5")
        XCTAssertEqual(snapshot.taskSummary, "Audit Claude session state plumbing")
        XCTAssertTrue(snapshot.hasInProgressToolUse)
        XCTAssertEqual(snapshot.fallbackState, .thinking)
    }

    func testResolveGlobalStateUsesWaitingAsAttention() {
        let activity = ClaudeCodeSessionActivity(status: .waiting, waitingFor: "approve Edit")
        let transcript = ClaudeCodeTranscriptSnapshot(
            fallbackState: .idle,
            modelLabel: "glm-5.1",
            taskSummary: nil,
            hasInProgressToolUse: false
        )

        XCTAssertEqual(
            ClaudeCodeSnapshotParser.resolveGlobalState(activity: activity, transcript: transcript),
            .attention
        )
    }

    func testResolveGlobalStateUsesBusyWithoutToolUseAsThinking() {
        let activity = ClaudeCodeSessionActivity(status: .busy, waitingFor: nil)
        let transcript = ClaudeCodeTranscriptSnapshot(
            fallbackState: .idle,
            modelLabel: "glm-5.1",
            taskSummary: "Compact conversation",
            hasInProgressToolUse: false
        )

        XCTAssertEqual(
            ClaudeCodeSnapshotParser.resolveGlobalState(activity: activity, transcript: transcript),
            .thinking
        )
    }

    func testResolveGlobalStateUsesBusyWithInProgressToolUseAsWorking() {
        let activity = ClaudeCodeSessionActivity(status: .busy, waitingFor: nil)
        let transcript = ClaudeCodeTranscriptSnapshot(
            fallbackState: .idle,
            modelLabel: "kimi-k2.5",
            taskSummary: "Run shell integration review",
            hasInProgressToolUse: true
        )

        XCTAssertEqual(
            ClaudeCodeSnapshotParser.resolveGlobalState(activity: activity, transcript: transcript),
            .working
        )
    }

    func testParseTranscriptTailIgnoresStreamingPlaceholderModelUntilStableAssistantMessage() {
        let transcript = """
        {"type":"assistant","message":{"model":"claude-streaming-placeholder","usage":{"input_tokens":0},"content":[]}}
        {"type":"assistant","message":{"model":"glm-5.1-long-provider-build","usage":{"input_tokens":256},"stop_reason":"end_turn","content":[]}}
        """

        let snapshot = ClaudeCodeSnapshotParser.parseTranscriptTail(transcript)

        XCTAssertEqual(snapshot.modelLabel, "glm-5.1-long-provider-build")
        XCTAssertEqual(snapshot.fallbackState, .idle)
    }

    func testParseTranscriptTailDoesNotLetTaskSummaryOverrideLiveFallbackState() {
        let transcript = """
        {"type":"assistant","message":{"model":"kimi-k2.5","usage":{"input_tokens":128},"stop_reason":"tool_use","content":[{"type":"tool_use","id":"tool-1","name":"Read","input":{"file_path":"README.md"}}]}}
        {"type":"task-summary","summary":"Inspect transcript state handling","timestamp":"2026-04-11T09:00:00Z"}
        """

        let snapshot = ClaudeCodeSnapshotParser.parseTranscriptTail(transcript)

        XCTAssertEqual(snapshot.taskSummary, "Inspect transcript state handling")
        XCTAssertEqual(snapshot.fallbackState, .working)
        XCTAssertTrue(snapshot.hasInProgressToolUse)
    }

    func testParseTranscriptTailExtractsLastPromptWithoutChangingFallbackState() {
        let transcript = """
        {"type":"assistant","message":{"model":"kimi-k2.5","usage":{"input_tokens":128},"stop_reason":"end_turn","content":[]}}
        {"type":"last-prompt","lastPrompt":"关闭灵动岛并构建最新版"}
        """

        let snapshot = ClaudeCodeSnapshotParser.parseTranscriptTail(transcript)

        XCTAssertEqual(snapshot.lastPrompt, "关闭灵动岛并构建最新版")
        XCTAssertEqual(snapshot.fallbackState, .idle)
    }

    func testParseTranscriptTailCollectsExternalUserPromptCandidatesButSkipsToolResults() {
        let transcript = """
        {"type":"user","userType":"external","message":{"content":[{"type":"text","text":"排查 Claude 线程标题兜底"}]}}
        {"type":"user","userType":"internal","message":{"content":[{"type":"text","text":"内部系统生成的 user 消息"}]}}
        {"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"tool-1","content":"done"}]}}
        {"type":"user","message":{"content":[{"type":"text","text":"补充 Claude prompt fallback 测试"}]}}
        """

        let snapshot = ClaudeCodeSnapshotParser.parseTranscriptTail(transcript)

        XCTAssertEqual(
            snapshot.userPromptCandidates,
            ["排查 Claude 线程标题兜底", "补充 Claude prompt fallback 测试"]
        )
    }

    func testParseTranscriptTailSkipsToolResultsWhenMixedWithUserTextBlocks() {
        let transcript = """
        {"type":"user","message":{"content":[{"type":"text","text":"排查 Claude 线程标题兜底"},{"type":"tool_result","tool_use_id":"tool-1","content":"done"},{"type":"input_text","text":"补充同条消息混排测试"}]}}
        """

        let snapshot = ClaudeCodeSnapshotParser.parseTranscriptTail(transcript)

        XCTAssertEqual(
            snapshot.userPromptCandidates,
            ["排查 Claude 线程标题兜底", "补充同条消息混排测试"]
        )
    }

    func testResolveTaskLabelPrefersWaitingReasonThenTaskSummaryThenDirectoryName() {
        let waitingActivity = ClaudeCodeSessionActivity(status: .waiting, waitingFor: "approve Bash")
        let transcript = ClaudeCodeTranscriptSnapshot(
            fallbackState: .idle,
            modelLabel: "glm-5.1",
            taskSummary: "Compact conversation",
            hasInProgressToolUse: false
        )

        XCTAssertEqual(
            ClaudeCodeSnapshotParser.resolveTaskLabel(
                activity: waitingActivity,
                transcript: transcript,
                cwd: "/workspace/ai-dynamic-island-macos"
            ),
            "approve Bash"
        )

        XCTAssertEqual(
            ClaudeCodeSnapshotParser.resolveTaskLabel(
                activity: ClaudeCodeSessionActivity(status: .busy, waitingFor: nil),
                transcript: transcript,
                cwd: "/workspace/ai-dynamic-island-macos"
            ),
            "Compact conversation"
        )

        XCTAssertEqual(
            ClaudeCodeSnapshotParser.resolveTaskLabel(
                activity: nil,
                transcript: ClaudeCodeTranscriptSnapshot(
                    fallbackState: .idle,
                    modelLabel: nil,
                    taskSummary: nil,
                    hasInProgressToolUse: false
                ),
                cwd: "/workspace/ai-dynamic-island-macos"
            ),
            "ai-dynamic-island-macos"
        )
    }

    func testShouldRenderThreadKeepsActiveThreadVisibleWithoutModelLabel() {
        let transcript = ClaudeCodeTranscriptSnapshot(
            fallbackState: .thinking,
            modelLabel: nil,
            taskSummary: "Inspect Claude live state",
            hasInProgressToolUse: false
        )

        XCTAssertTrue(
            ClaudeCodeSnapshotParser.shouldRenderThread(
                activity: nil,
                transcript: transcript,
                state: .thinking
            )
        )
        XCTAssertEqual(
            ClaudeCodeSnapshotParser.resolveModelLabel(transcript: transcript),
            ""
        )
    }

    func testShouldRenderThreadKeepsIdleSessionEmptyWithoutTaskSignals() {
        let transcript = ClaudeCodeTranscriptSnapshot(
            fallbackState: .idle,
            modelLabel: nil,
            taskSummary: nil,
            hasInProgressToolUse: false
        )

        XCTAssertFalse(
            ClaudeCodeSnapshotParser.shouldRenderThread(
                activity: nil,
                transcript: transcript,
                state: .idle
            )
        )
    }
}
