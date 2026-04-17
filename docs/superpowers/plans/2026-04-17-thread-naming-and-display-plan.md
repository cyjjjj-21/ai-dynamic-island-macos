# Thread Naming And Display Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Upgrade Codex and Claude thread naming from raw prompts and weak path fallbacks into stable, sanitized thread titles plus compact action detail, while preserving the current expanded-card height and premium visual direction.

**Architecture:** Keep the current monitor pipelines intact, but insert a small shared thread-title resolution layer between parsed monitor signals and `AgentState`. Split thread display semantics into stable `title` and transient `detail`, add source/quality metadata for debugging, and adapt the existing two-line row UI to render stronger information density without adding any new vertical blocks or increasing section/card height.

**Tech Stack:** Swift, SwiftUI, Foundation, XCTest, `xcodebuild`

---

## File Structure

- Create: `AIIslandApp/Monitoring/ThreadTitleResolver.swift`
  Purpose: shared deterministic title/detail resolution, sanitization, quality gates, and workspace fallback helpers for Codex and Claude.
- Modify: `AIIslandCore/Domain/AgentState.swift`
  Purpose: extend `AgentThread` with stable title/detail/workspace/recency/title-source metadata instead of a single overloaded `taskLabel`.
- Modify: `AIIslandApp/Monitoring/CodexSessionSnapshotParser.swift`
  Purpose: emit richer raw naming inputs instead of directly freezing the latest user prompt as final UI title.
- Modify: `AIIslandApp/Monitoring/ClaudeCodeSnapshotParser.swift`
  Purpose: stop using `waitingFor` or user-home path tails as title fallbacks; emit inputs for shared title/detail resolution.
- Modify: `AIIslandApp/Monitoring/CodexMonitorArbitrator.swift`
  Purpose: map resolved Codex title/detail metadata into `AgentThread`.
- Modify: `AIIslandApp/Monitoring/ClaudeMonitorArbitrator.swift`
  Purpose: map resolved Claude title/detail metadata into `AgentThread`.
- Modify: `AIIslandApp/UI/Expanded/AgentSectionPresentation.swift`
  Purpose: expose `threadTitle`, `detailCopy`, `recencyCopy`, and primary-row styling flags to the UI while keeping the section structure flat.
- Modify: `AIIslandApp/UI/Expanded/ThreadRowView.swift`
  Purpose: re-layout the existing two-line thread row into `title + model` and `detail/status + context/recency`, without increasing row height.
- Modify: `AIIslandApp/UI/Expanded/AgentSectionView.swift`
  Purpose: mark the first visible thread as primary via styling only, not by adding extra blocks or vertical height.
- Modify: `AIIslandApp/UI/Styling/IslandPalette.swift`
  Purpose: add any compact text/spacing tokens needed for the denser row layout while preserving the current premium visual system.
- Create: `AIIslandAppTests/ThreadTitleResolverTests.swift`
  Purpose: lock title sanitization, quality-gate rejection, prompt summarization heuristics, workspace fallback rules, and source-priority behavior.
- Modify: `AIIslandAppTests/CodexSessionSnapshotParserTests.swift`
  Purpose: cover Codex-specific naming inputs and ensure dirty session-index titles do not leak through as final titles.
- Modify: `AIIslandAppTests/ClaudeMonitorArbitratorTests.swift`
  Purpose: cover Claude title/detail separation, especially `waitingFor` becoming detail instead of title and username path fallbacks being rejected.
- Modify: `AIIslandAppTests/CodexMonitorArbitratorTests.swift`
  Purpose: cover Codex title/detail mapping and low-quality fallback suppression.
- Modify: `AIIslandAppTests/FallbackRenderingRulesTests.swift`
  Purpose: lock presentation-layer compact strings and degraded fallback copies after the thread model changes.
- Modify: `PROGRESS.md`
  Purpose: record the thread-title architecture shift and the “no extra expanded-card height” product constraint after implementation lands.

## Hard Constraints

- Do not increase `ExpandedIslandCardView` height.
- Do not add a third row of thread metadata.
- Do not add new per-thread subcards, drawers, or footer summaries.
- Do not expose subagent sessions as independent top-level rows in the expanded card.
- If subagent state is surfaced, it must be folded into the parent thread's compact detail line or badge treatment only.
- Do not show raw `session_index.thread_name` or raw `waitingFor` as the final title without passing sanitization and quality gates.
- If a title candidate contains HTML-like tags, transport fragments, suspicious symbol density, replacement characters, or user-home-only path fallbacks, reject it and fall back to a safer candidate.

### Task 1: Extend The Thread Domain Model

**Files:**
- Modify: `AIIslandCore/Domain/AgentState.swift`
- Test: `AIIslandAppTests/FallbackRenderingRulesTests.swift`

- [ ] **Step 1: Write the failing domain/presentation tests for split title/detail semantics**

```swift
func testThreadPresentationUsesStableTitleAndSeparateDetail() {
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

    let row = ThreadRowPresentation(thread: thread, isPrimary: true, now: Date(timeIntervalSince1970: 1_713_000_018))
    XCTAssertEqual(row.threadTitle, "Codex 配额展示优化")
    XCTAssertEqual(row.detailCopy, "执行工具中")
    XCTAssertEqual(row.recencyCopy, "18s")
}
```

- [ ] **Step 2: Run the focused presentation tests to verify they fail**

Run: `xcodebuild test -project /Users/chenyuanjie/developer/ai-dynamic-island-macos/.worktrees/visual-polish-steady-premium/AIIslandApp.xcodeproj -scheme AIIslandApp -destination 'platform=macOS' -only-testing:AIIslandAppTests/FallbackRenderingRulesTests`
Expected: FAIL because `AgentThread` and `ThreadRowPresentation` do not yet expose split title/detail fields.

- [ ] **Step 3: Extend `AgentThread` with stable title/detail metadata**

```swift
public enum AgentThreadTitleSource: String, Codable, Equatable, Sendable {
    case codexPromptSummary
    case codexSessionIndexHint
    case claudeTaskSummary
    case workspaceFallback
    case unknown
}

public struct AgentThread: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let detail: String?
    public let workspaceLabel: String?
    public let modelLabel: String
    public let contextRatio: Double?
    public let state: AgentGlobalState
    public let lastUpdatedAt: Date?
    public let titleSource: AgentThreadTitleSource
}
```

- [ ] **Step 4: Update compile-time call sites with temporary direct mappings**

Minimal temporary rule:
- map old `taskLabel` into `title`
- map `detail` to `nil`
- map `lastUpdatedAt` from existing snapshot/update timestamps
- use `.unknown` until resolvers land in later tasks

- [ ] **Step 5: Re-run the focused presentation test**

Run: `xcodebuild test -project /Users/chenyuanjie/developer/ai-dynamic-island-macos/.worktrees/visual-polish-steady-premium/AIIslandApp.xcodeproj -scheme AIIslandApp -destination 'platform=macOS' -only-testing:AIIslandAppTests/FallbackRenderingRulesTests`
Expected: PASS or compile-success with any remaining failures shifted to later title/detail presentation assertions.

- [ ] **Step 6: Commit the domain-model split**

```bash
git -C /Users/chenyuanjie/developer/ai-dynamic-island-macos/.worktrees/visual-polish-steady-premium add AIIslandCore/Domain/AgentState.swift AIIslandAppTests/FallbackRenderingRulesTests.swift
git -C /Users/chenyuanjie/developer/ai-dynamic-island-macos/.worktrees/visual-polish-steady-premium commit -m "refactor: split thread title and detail semantics"
```

### Task 2: Build A Shared Thread Title Resolver With Quality Gates

**Files:**
- Create: `AIIslandApp/Monitoring/ThreadTitleResolver.swift`
- Test: `AIIslandAppTests/ThreadTitleResolverTests.swift`

- [ ] **Step 1: Write failing resolver tests for dirty-title rejection and fallback priority**

```swift
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
    let result = ThreadTitleResolver.resolveWorkspaceLabel(from: "/Users/chenyuanjie")
    XCTAssertNil(result)
}

func testResolverUsesTaskSummaryForClaudeTitleAndWaitingForForDetail() {
    let result = ThreadTitleResolver.resolveClaudeTitle(
        taskSummary: "Claude 多线程仲裁",
        waitingFor: "approve Bash",
        workspacePath: "/Users/chenyuanjie/developer/ai-dynamic-island-macos"
    )

    XCTAssertEqual(result.title, "Claude 多线程仲裁")
    XCTAssertEqual(result.detail, "等待批准 Bash")
}
```

- [ ] **Step 2: Run the focused resolver test target to verify failure**

Run: `xcodebuild test -project /Users/chenyuanjie/developer/ai-dynamic-island-macos/.worktrees/visual-polish-steady-premium/AIIslandApp.xcodeproj -scheme AIIslandApp -destination 'platform=macOS' -only-testing:AIIslandAppTests/ThreadTitleResolverTests`
Expected: FAIL because the resolver file and tests do not exist yet.

- [ ] **Step 3: Implement the shared resolver with deterministic heuristics**

Required units inside `ThreadTitleResolver.swift`:

```swift
struct ResolvedThreadTitle: Equatable, Sendable {
    let title: String
    let detail: String?
    let workspaceLabel: String?
    let source: AgentThreadTitleSource
}

enum ThreadTitleResolver {
    static func resolveCodexTitle(...) -> ResolvedThreadTitle
    static func resolveClaudeTitle(...) -> ResolvedThreadTitle
    static func resolveWorkspaceLabel(from path: String?) -> String?
}
```

Required behavior:
- reject candidate titles containing `<...>` HTML-like tags
- reject titles with suspicious symbol density or replacement characters
- reject pure user-home or username-only path tails
- normalize whitespace and strip low-value lead-in phrases like `继续`, `接着`, `帮我`, `please`, `re-review`
- compress prompt text into compact title phrases rather than replaying the full prompt
- keep transient action strings such as `approve Bash` or `等待确认` in `detail`, not `title`

- [ ] **Step 4: Re-run the focused resolver tests**

Run: `xcodebuild test -project /Users/chenyuanjie/developer/ai-dynamic-island-macos/.worktrees/visual-polish-steady-premium/AIIslandApp.xcodeproj -scheme AIIslandApp -destination 'platform=macOS' -only-testing:AIIslandAppTests/ThreadTitleResolverTests`
Expected: PASS

- [ ] **Step 5: Commit the resolver layer**

```bash
git -C /Users/chenyuanjie/developer/ai-dynamic-island-macos/.worktrees/visual-polish-steady-premium add AIIslandApp/Monitoring/ThreadTitleResolver.swift AIIslandAppTests/ThreadTitleResolverTests.swift
git -C /Users/chenyuanjie/developer/ai-dynamic-island-macos/.worktrees/visual-polish-steady-premium commit -m "feat: add shared thread title resolver"
```

### Task 3: Refactor Codex Naming Inputs Away From Raw Prompt And Dirty Session Titles

**Files:**
- Modify: `AIIslandApp/Monitoring/CodexSessionSnapshotParser.swift`
- Modify: `AIIslandAppTests/CodexSessionSnapshotParserTests.swift`

- [ ] **Step 1: Write failing Codex parser tests for title-input extraction**

```swift
func testCodexParserPreservesRecentPromptCandidatesWithoutCommittingToFinalTitle() {
    let jsonl = """
    {"type":"response_item","payload":{"type":"message","role":"user","turn_id":"turn-1","content":[{"type":"input_text","text":"继续把 Codex 配额展示做扎实"}]}}
    {"type":"response_item","payload":{"type":"message","role":"user","turn_id":"turn-2","content":[{"type":"input_text","text":"顺便修一下配额刷新时间的对齐"}]}}
    """

    let snapshot = CodexSessionSnapshotParser.parse(jsonl, sessionID: "t1", fallbackTaskLabel: "脏标题")
    XCTAssertEqual(snapshot.promptCandidates.count, 2)
    XCTAssertEqual(snapshot.titleHint, "脏标题")
}
```

- [ ] **Step 2: Run the focused Codex parser tests to verify failure**

Run: `xcodebuild test -project /Users/chenyuanjie/developer/ai-dynamic-island-macos/.worktrees/visual-polish-steady-premium/AIIslandApp.xcodeproj -scheme AIIslandApp -destination 'platform=macOS' -only-testing:AIIslandAppTests/CodexSessionSnapshotParserTests`
Expected: FAIL because the snapshot struct does not yet expose title inputs.

- [ ] **Step 3: Modify `CodexSessionSnapshot` to carry raw naming inputs instead of only final `taskLabel`**

Add compact raw fields such as:

```swift
let titleHint: String?
let promptCandidates: [String]
let latestAssistantMessage: String?
let workspacePath: String?
```

Implementation rules:
- `session_index.thread_name` becomes `titleHint`, not final UI title
- collect up to a small bounded set of recent user prompts in chronological order
- preserve `latestAssistantMessage` for later detail derivation
- keep all existing state, model, context, and quota behavior unchanged

- [ ] **Step 4: Re-run the focused Codex parser tests**

Run: `xcodebuild test -project /Users/chenyuanjie/developer/ai-dynamic-island-macos/.worktrees/visual-polish-steady-premium/AIIslandApp.xcodeproj -scheme AIIslandApp -destination 'platform=macOS' -only-testing:AIIslandAppTests/CodexSessionSnapshotParserTests`
Expected: PASS

- [ ] **Step 5: Commit the Codex input refactor**

```bash
git -C /Users/chenyuanjie/developer/ai-dynamic-island-macos/.worktrees/visual-polish-steady-premium add AIIslandApp/Monitoring/CodexSessionSnapshotParser.swift AIIslandAppTests/CodexSessionSnapshotParserTests.swift
git -C /Users/chenyuanjie/developer/ai-dynamic-island-macos/.worktrees/visual-polish-steady-premium commit -m "refactor: separate codex thread title inputs from final labels"
```

### Task 4: Refactor Claude Naming Inputs Away From Waiting-For Titles And Username Fallbacks

**Files:**
- Modify: `AIIslandApp/Monitoring/ClaudeCodeSnapshotParser.swift`
- Modify: `AIIslandAppTests/ClaudeMonitorArbitratorTests.swift`

- [ ] **Step 1: Write failing Claude tests for title/detail separation**

```swift
func testClaudeWaitingForBecomesDetailNotTitle() {
    let resolved = ThreadTitleResolver.resolveClaudeTitle(
        taskSummary: nil,
        waitingFor: "approve Bash",
        workspacePath: "/Users/chenyuanjie/developer/ai-dynamic-island-macos"
    )

    XCTAssertEqual(resolved.title, "ai-dynamic-island-macos")
    XCTAssertEqual(resolved.detail, "等待批准 Bash")
}
```

- [ ] **Step 2: Run the focused Claude arbitrator tests to verify failure**

Run: `xcodebuild test -project /Users/chenyuanjie/developer/ai-dynamic-island-macos/.worktrees/visual-polish-steady-premium/AIIslandApp.xcodeproj -scheme AIIslandApp -destination 'platform=macOS' -only-testing:AIIslandAppTests/ClaudeMonitorArbitratorTests`
Expected: FAIL because Claude still resolves title directly from `waitingFor` or raw path tails.

- [ ] **Step 3: Modify Claude parser/resolution helpers**

Required changes:
- replace `resolveTaskLabel(...)` with a raw-input provider or direct resolver call
- `waitingFor` stays available for detail generation
- `taskSummary` remains the strongest title source
- raw `cwd` tail may only become `workspaceLabel`, not a final title if it collapses to a username/home folder

- [ ] **Step 4: Re-run the focused Claude tests**

Run: `xcodebuild test -project /Users/chenyuanjie/developer/ai-dynamic-island-macos/.worktrees/visual-polish-steady-premium/AIIslandApp.xcodeproj -scheme AIIslandApp -destination 'platform=macOS' -only-testing:AIIslandAppTests/ClaudeMonitorArbitratorTests`
Expected: PASS

- [ ] **Step 5: Commit the Claude naming refactor**

```bash
git -C /Users/chenyuanjie/developer/ai-dynamic-island-macos/.worktrees/visual-polish-steady-premium add AIIslandApp/Monitoring/ClaudeCodeSnapshotParser.swift AIIslandAppTests/ClaudeMonitorArbitratorTests.swift
git -C /Users/chenyuanjie/developer/ai-dynamic-island-macos/.worktrees/visual-polish-steady-premium commit -m "refactor: separate claude thread titles from waiting state"
```

### Task 5: Wire Resolved Titles Into Codex And Claude Arbitrators

**Files:**
- Modify: `AIIslandApp/Monitoring/CodexMonitorArbitrator.swift`
- Modify: `AIIslandApp/Monitoring/ClaudeMonitorArbitrator.swift`
- Modify: `AIIslandAppTests/CodexMonitorArbitratorTests.swift`
- Modify: `AIIslandAppTests/ClaudeMonitorArbitratorTests.swift`

- [ ] **Step 1: Write failing arbitrator tests for final `AgentThread` title/detail mapping**

```swift
func testCodexArbitratorPublishesResolvedTitleInsteadOfRawPrompt() {
    let snapshot = makeSnapshot(
        sessionID: "thread-1",
        titleHint: "查找自动化未读消息来源<br>garbled",
        promptCandidates: ["查找自动化未读消息来源"],
        state: .working
    )

    let result = CodexMonitorArbitrator.compute(...)
    XCTAssertEqual(result.state.threads.first?.title, "自动化未读消息排查")
}
```

- [ ] **Step 2: Run the focused arbitrator suites to verify failure**

Run: `xcodebuild test -project /Users/chenyuanjie/developer/ai-dynamic-island-macos/.worktrees/visual-polish-steady-premium/AIIslandApp.xcodeproj -scheme AIIslandApp -destination 'platform=macOS' -only-testing:AIIslandAppTests/CodexMonitorArbitratorTests -only-testing:AIIslandAppTests/ClaudeMonitorArbitratorTests`
Expected: FAIL because arbitrators still populate the old thread title field directly.

- [ ] **Step 3: Resolve title/detail/workspace inside both arbitrators**

Implementation rules:
- Codex arbitrator calls `ThreadTitleResolver.resolveCodexTitle(...)`
- Claude arbitrator calls `ThreadTitleResolver.resolveClaudeTitle(...)`
- store `updatedAt` as `lastUpdatedAt` on `AgentThread`
- preserve current thread ordering, freshness decay, quota selection, and availability behavior
- do not let title-resolution failure drop the whole thread; only degrade the title candidate

- [ ] **Step 4: Re-run the focused arbitrator tests**

Run: `xcodebuild test -project /Users/chenyuanjie/developer/ai-dynamic-island-macos/.worktrees/visual-polish-steady-premium/AIIslandApp.xcodeproj -scheme AIIslandApp -destination 'platform=macOS' -only-testing:AIIslandAppTests/CodexMonitorArbitratorTests -only-testing:AIIslandAppTests/ClaudeMonitorArbitratorTests`
Expected: PASS

- [ ] **Step 5: Commit the arbitrator wiring**

```bash
git -C /Users/chenyuanjie/developer/ai-dynamic-island-macos/.worktrees/visual-polish-steady-premium add AIIslandApp/Monitoring/CodexMonitorArbitrator.swift AIIslandApp/Monitoring/ClaudeMonitorArbitrator.swift AIIslandAppTests/CodexMonitorArbitratorTests.swift AIIslandAppTests/ClaudeMonitorArbitratorTests.swift
git -C /Users/chenyuanjie/developer/ai-dynamic-island-macos/.worktrees/visual-polish-steady-premium commit -m "feat: wire resolved thread titles into monitor output"
```

### Task 6: Fold Subagent Activity Into Parent Thread Detail Without Adding Rows

**Files:**
- Modify: `AIIslandApp/Monitoring/CodexSessionSnapshotParser.swift`
- Modify: `AIIslandApp/Monitoring/CodexMonitor.swift`
- Modify: `AIIslandApp/Monitoring/CodexMonitorArbitrator.swift`
- Modify: `AIIslandAppTests/CodexSessionSnapshotParserTests.swift`
- Modify: `AIIslandAppTests/CodexMonitorSmokeTests.swift`
- Modify: `AIIslandAppTests/CodexMonitorArbitratorTests.swift`

- [ ] **Step 1: Write failing tests for parent-thread subagent aggregation**

```swift
func testRefreshNowFoldsLiveSubagentWorkIntoParentThreadDetail() throws {
    // main thread + subagent thread with parent_thread_id
    // expect only the main thread to render
    // expect the main thread detail to contain a compact subagent summary such as "1 个子任务处理中"
}

func testArbitratorDoesNotCreateExtraVisibleRowsForSubagentSummaries() {
    // provide a main snapshot plus aggregated subagent metadata
    // expect visible thread count to remain unchanged
}
```

- [ ] **Step 2: Run the focused Codex suites to verify failure**

Run: `xcodebuild test -project /Users/chenyuanjie/developer/ai-dynamic-island-macos/.worktrees/visual-polish-steady-premium/AIIslandApp.xcodeproj -scheme AIIslandApp -destination 'platform=macOS' -only-testing:AIIslandAppTests/CodexSessionSnapshotParserTests -only-testing:AIIslandAppTests/CodexMonitorArbitratorTests -only-testing:AIIslandAppTests/CodexMonitorSmokeTests`
Expected: FAIL because subagent sessions are currently only suppressed, not aggregated into parent-thread detail.

- [ ] **Step 3: Extend Codex parsing to capture parent-thread subagent metadata**

Add compact metadata fields to `CodexSessionSnapshot` or a neighboring helper model such as:

```swift
let parentThreadID: String?
let subagentRole: String?
let subagentNickname: String?
```

Rules:
- keep current `isSubagentSession` detection intact
- parse `parent_thread_id` / `thread_spawn.parent_thread_id` when present
- preserve current suppression behavior for the subagent thread itself

- [ ] **Step 4: Aggregate suppressed subagent activity by parent thread during refresh**

Inside `CodexMonitor.computeRefresh(...)`:
- build a compact per-parent summary while scanning suppressed subagent sessions
- suggested summary fields:

```swift
struct CodexSubagentSummary: Equatable, Sendable {
    let activeCount: Int
    let busyCount: Int
    let attentionCount: Int
}
```

- do not append new top-level snapshots for subagents
- carry the summary map into the arbitrator

- [ ] **Step 5: Merge subagent summaries into the parent thread detail only**

Inside `CodexMonitorArbitrator.compute(...)`:
- if a visible parent thread has a summary, fold it into the resolved detail line
- example compact copies:
  - `1 个子任务处理中`
  - `2 个子任务运行中`
  - `子任务等待确认`
- if the parent already has a stronger detail such as `等待批准 Bash`, append the subagent summary only when it still fits the one-line budget
- never create a separate row, chip row, or footer block for subagents

- [ ] **Step 6: Re-run the focused Codex tests**

Run: `xcodebuild test -project /Users/chenyuanjie/developer/ai-dynamic-island-macos/.worktrees/visual-polish-steady-premium/AIIslandApp.xcodeproj -scheme AIIslandApp -destination 'platform=macOS' -only-testing:AIIslandAppTests/CodexSessionSnapshotParserTests -only-testing:AIIslandAppTests/CodexMonitorArbitratorTests -only-testing:AIIslandAppTests/CodexMonitorSmokeTests`
Expected: PASS

- [ ] **Step 7: Commit the subagent aggregation pass**

```bash
git -C /Users/chenyuanjie/developer/ai-dynamic-island-macos/.worktrees/visual-polish-steady-premium add AIIslandApp/Monitoring/CodexSessionSnapshotParser.swift AIIslandApp/Monitoring/CodexMonitor.swift AIIslandApp/Monitoring/CodexMonitorArbitrator.swift AIIslandAppTests/CodexSessionSnapshotParserTests.swift AIIslandAppTests/CodexMonitorArbitratorTests.swift AIIslandAppTests/CodexMonitorSmokeTests.swift
git -C /Users/chenyuanjie/developer/ai-dynamic-island-macos/.worktrees/visual-polish-steady-premium commit -m "feat: fold codex subagent activity into parent thread detail"
```

### Task 7: Rebuild Thread Presentation For Higher Information Density Without Extra Height

**Files:**
- Modify: `AIIslandApp/UI/Expanded/AgentSectionPresentation.swift`
- Modify: `AIIslandApp/UI/Expanded/ThreadRowView.swift`
- Modify: `AIIslandApp/UI/Expanded/AgentSectionView.swift`
- Modify: `AIIslandApp/UI/Styling/IslandPalette.swift`
- Modify: `AIIslandAppTests/FallbackRenderingRulesTests.swift`

- [ ] **Step 1: Write failing presentation tests for compact title/detail/recency rows**

```swift
func testThreadRowPresentationBuildsCompactDetailAndRecencyStrings() {
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
}
```

- [ ] **Step 2: Run the focused presentation test suite to verify failure**

Run: `xcodebuild test -project /Users/chenyuanjie/developer/ai-dynamic-island-macos/.worktrees/visual-polish-steady-premium/AIIslandApp.xcodeproj -scheme AIIslandApp -destination 'platform=macOS' -only-testing:AIIslandAppTests/FallbackRenderingRulesTests`
Expected: FAIL because `ThreadRowPresentation` and the layout do not yet support compact title/detail/recency semantics.

- [ ] **Step 3: Update presentation-layer contracts**

Required `ThreadRowPresentation` fields:

```swift
let threadTitle: String
let detailCopy: String
let modelLabel: String
let contextCopy: String
let recencyCopy: String?
let state: AgentGlobalState
let isPrimary: Bool
```

Rules:
- `detailCopy` prefers resolved detail, then compact state fallback
- `recencyCopy` derives from `lastUpdatedAt`
- first visible thread gets `isPrimary = true`
- keep `maximumVisibleThreads == 3`

- [ ] **Step 4: Re-layout `ThreadRowView` without adding height**

Required visual shape:
- first line: `threadTitle` left, `modelLabel` right
- second line: compact status/detail capsule left, `contextCopy` and optional `recencyCopy` right
- row still uses exactly two lines and current vertical padding budget
- if space is tight, trim `recencyCopy` before trimming `threadTitle`

Example row layout target:

```swift
VStack(alignment: .leading, spacing: 5) {
    HStack { title; Spacer(); model }
    HStack { detailBadge; Spacer(); metaCluster }
}
.padding(.vertical, 7)
```

- [ ] **Step 5: Keep section/card vertical size unchanged**

Before considering this task complete:
- keep `ExpandedIslandCardView` structure unchanged
- do not add new block-level summary under thread rows
- verify `AgentSectionView` still contains the same header + rows + optional quota structure
- if row spacing needs reduction, reduce internal padding rather than adding outer height

- [ ] **Step 6: Re-run the focused presentation tests**

Run: `xcodebuild test -project /Users/chenyuanjie/developer/ai-dynamic-island-macos/.worktrees/visual-polish-steady-premium/AIIslandApp.xcodeproj -scheme AIIslandApp -destination 'platform=macOS' -only-testing:AIIslandAppTests/FallbackRenderingRulesTests`
Expected: PASS

- [ ] **Step 7: Commit the compact UI refactor**

```bash
git -C /Users/chenyuanjie/developer/ai-dynamic-island-macos/.worktrees/visual-polish-steady-premium add AIIslandApp/UI/Expanded/AgentSectionPresentation.swift AIIslandApp/UI/Expanded/ThreadRowView.swift AIIslandApp/UI/Expanded/AgentSectionView.swift AIIslandApp/UI/Styling/IslandPalette.swift AIIslandAppTests/FallbackRenderingRulesTests.swift
git -C /Users/chenyuanjie/developer/ai-dynamic-island-macos/.worktrees/visual-polish-steady-premium commit -m "feat: upgrade thread rows to compact title and detail display"
```

### Task 8: Full Verification And Repo Notes

**Files:**
- Modify: `PROGRESS.md`
- Test: `AIIslandAppTests/ThreadTitleResolverTests.swift`
- Test: `AIIslandAppTests/CodexSessionSnapshotParserTests.swift`
- Test: `AIIslandAppTests/CodexMonitorArbitratorTests.swift`
- Test: `AIIslandAppTests/ClaudeMonitorArbitratorTests.swift`
- Test: `AIIslandAppTests/FallbackRenderingRulesTests.swift`

- [ ] **Step 1: Run the focused naming/presentation regression suite**

Run: `xcodebuild test -project /Users/chenyuanjie/developer/ai-dynamic-island-macos/.worktrees/visual-polish-steady-premium/AIIslandApp.xcodeproj -scheme AIIslandApp -destination 'platform=macOS' -only-testing:AIIslandAppTests/ThreadTitleResolverTests -only-testing:AIIslandAppTests/CodexSessionSnapshotParserTests -only-testing:AIIslandAppTests/CodexMonitorArbitratorTests -only-testing:AIIslandAppTests/ClaudeMonitorArbitratorTests -only-testing:AIIslandAppTests/FallbackRenderingRulesTests`
Expected: PASS

- [ ] **Step 2: Run the full regression suite**

Run: `xcodebuild test -project /Users/chenyuanjie/developer/ai-dynamic-island-macos/.worktrees/visual-polish-steady-premium/AIIslandApp.xcodeproj -scheme AIIslandApp -destination 'platform=macOS'`
Expected: PASS

- [ ] **Step 3: Perform a UI size sanity check**

Run:

```bash
rg -n "expandedCardWidth|expandedCardHitHeight|padding\\(.vertical|frame\\(height" /Users/chenyuanjie/developer/ai-dynamic-island-macos/.worktrees/visual-polish-steady-premium/AIIslandApp/UI/Expanded
```

Expected:
- no new explicit height increases
- no new third-line row stacks
- no extra thread summary blocks added beneath the rows

- [ ] **Step 4: Update `PROGRESS.md`**

Record:
- the new stable thread-title architecture
- the rule that raw session-index titles and username path tails are never trusted as final UI titles
- the rule that Codex subagent sessions remain hidden as independent rows and are only surfaced through compact parent-thread summaries
- the compact UI constraint that this pass preserved the existing expanded-card height

- [ ] **Step 5: Commit verification and notes**

```bash
git -C /Users/chenyuanjie/developer/ai-dynamic-island-macos/.worktrees/visual-polish-steady-premium add PROGRESS.md
git -C /Users/chenyuanjie/developer/ai-dynamic-island-macos/.worktrees/visual-polish-steady-premium commit -m "docs: record thread naming and compact display upgrade"
```
