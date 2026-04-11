# Codex Live Monitor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the fixture-backed Codex state with live local Codex session data so the island shows real per-thread task labels, real model names, real context usage, and real 5-hour / weekly quota.

**Architecture:** Mirror the existing Claude monitor shape instead of inventing a second architecture. Treat Codex `sessions/**/*.jsonl` as the primary local live source for model, token, quota, and task lifecycle signals, while using `session_index.jsonl` only for discovery, recency, and task-title fallback. Let a `CodexMonitor` compose those snapshots into the existing `AgentState` contract, but explicitly distinguish verified values from inferred status so the UI never over-claims precision.

**Tech Stack:** Swift, SwiftUI, Foundation, XCTest, `xcodebuild`

---

## Scope

- Ship a real Codex live monitor with no extra bridge process.
- Use `~/.codex/sessions/YYYY/MM/DD/*.jsonl` as the primary source for per-session model, token, quota, and activity events.
- Use `~/.codex/session_index.jsonl` only for thread discovery, recency, and task-label fallback.
- Do **not** use `~/.codex/logs_2.sqlite` as a UI data source.
- Do **not** use Accessibility / UI scraping as a primary data source.
- First ship task label fallback chain:
  1. latest parseable user prompt text from the active turn
  2. `session_index.jsonl` `thread_name`
  3. session `cwd` tail
- First ship availability rules:
  - `offline`: no readable recent Codex artifacts at all
  - `statusUnavailable`: Codex artifacts are readable, but no trustworthy live thread state can be derived
  - `available`: at least one live thread snapshot is trustworthy enough to render
- First ship global state rules:
  - `idle`: latest turn completed and no in-flight work markers
  - `thinking`: inferred from an in-flight turn without active tool / command markers
  - `working`: inferred from an in-flight turn with active tool / command markers
  - `attention`: inferred from the latest assistant output clearly blocking on user input or approval
- Keep non-goals explicit:
  - do not claim GUI-focused thread selection
  - do not claim per-frame internal Codex UI state
  - do not claim exact current tool step beyond event-derived inference

## File Structure

**Create**
- `AIIslandApp/Monitoring/CodexSessionIndexParser.swift`
- `AIIslandApp/Monitoring/CodexSessionSnapshotParser.swift`
- `AIIslandApp/Monitoring/CodexMonitor.swift`
- `AIIslandAppTests/CodexSessionIndexParserTests.swift`
- `AIIslandAppTests/CodexSessionSnapshotParserTests.swift`
- `AIIslandAppTests/CodexMonitorSmokeTests.swift`

**Modify**
- `AIIslandApp/UI/IslandRootView.swift`
- `PROGRESS.md`

## Data Contract Notes

Keep the existing app-facing contract unchanged:

```swift
AgentState(
    kind: .codex,
    online: true,
    availability: .available,
    globalState: .working,
    threads: [
        AgentThread(
            id: threadID,
            taskLabel: taskLabel,
            modelLabel: modelLabel,
            contextRatio: contextRatio,
            state: threadState
        )
    ],
    quota: AgentQuota(
        availability: .available,
        fiveHourRatio: fiveHourRatio,
        weeklyRatio: weeklyRatio
    )
)
```

Codex-specific mapping rules:

```swift
struct CodexSessionQuotaSnapshot: Equatable {
    let contextRatio: Double?
    let fiveHourRatio: Double?
    let weeklyRatio: Double?
}

struct CodexThreadSnapshot: Equatable {
    let threadID: String
    let taskLabel: String
    let modelLabel: String
    let contextRatio: Double?
    let state: AgentGlobalState
    let updatedAt: Date?
}
```

Internal parsing metadata must separate truth from inference:

```swift
enum CodexSnapshotTrustLevel: Equatable {
    case eventDerived
    case recentIndexFallback
    case insufficient
}

struct CodexSessionSnapshot: Equatable {
    let sessionID: String
    let taskLabel: String
    let modelLabel: String
    let contextRatio: Double?
    let fiveHourRatio: Double?
    let weeklyRatio: Double?
    let state: AgentGlobalState
    let updatedAt: Date?
    let trustLevel: CodexSnapshotTrustLevel
    let hasStructuredTokenSignal: Bool
    let hasStructuredActivitySignal: Bool
}
```

Source-of-truth hierarchy must be written down in code comments and tests:

- Verified values:
  - `turn_context.model`
  - `token_count.info.total_token_usage.total_tokens`
  - `token_count.info.model_context_window`
  - `token_count.rate_limits.primary/secondary.used_percent`
- Event-derived but still acceptable for product status:
  - `task_started` / `task_complete`
  - unresolved tool or command spans
  - latest assistant/user messages
- Fallback-only values:
  - `session_index.jsonl` `thread_name`
  - `session_index.jsonl` `updated_at`

Product semantics:

- `Context XX%` is shown only when a real `token_count` plus `model_context_window` pair exists.
- 5-hour and weekly quota bars are shown only when `rate_limits` are present.
- `Working / Thinking / Attention` are event-derived states, not official Codex enums.
- If only `session_index.jsonl` is available, prefer `statusUnavailable` over pretending the thread is truly live.

Session arbitration rules must be explicit and deterministic:

```swift
// 1. Parse all readable candidate sessions.
// 2. Drop snapshots that have neither a usable task label nor any usable token/quota signal.
// 3. Compute global quota from the newest snapshot that contains token_count data.
// 4. Compute visible thread rows from snapshots that are:
//    - trustLevel == .eventDerived and state is .attention / .working / .thinking, or
//    - trustLevel == .eventDerived and .idle but updated within the recent activity window, or
//    - trustLevel == .recentIndexFallback only when no eventDerived rows are available.
// 5. Sort thread rows by:
//    - state priority: attention > working > thinking > idle
//    - updatedAt descending
//    - trustLevel priority: eventDerived > recentIndexFallback > insufficient
//    - threadID ascending as a final tiebreaker
// 6. Truncate to the UI limit only after sorting.
let recentThreadWindow: TimeInterval = 10 * 60
```

## Task 0: Capture A Sanitized Live Fixture

**Files:**
- Create: `AIIslandAppTests/Fixtures/codex-live/README.md`
- Create: `AIIslandAppTests/Fixtures/codex-live/session_index.jsonl`
- Create: `AIIslandAppTests/Fixtures/codex-live/rollout-sample.jsonl`

- [ ] **Step 1: Capture one real local Codex fixture and sanitize it**

Required sanitization:
- replace absolute paths with repo-neutral placeholders
- replace thread IDs with stable fake IDs
- trim unrelated long developer instructions if they are not needed for parser coverage
- keep at least one real `turn_context`, one real `token_count`, one real activity sequence, and one partial-data sequence without `token_count`

- [ ] **Step 2: Write a short fixture note**

```markdown
# Codex Live Fixture

- Source date: 2026-04-11
- Fields intentionally preserved: `thread_name`, `turn_context.model`, `token_count`, task lifecycle events
- Fields intentionally redacted: absolute paths, local identifiers, long prompt bodies
- Fixture coverage includes both fully-populated live data and partial-data fallback cases
```

- [ ] **Step 3: Verify fixture placement does not break test discovery**

Run: `xcodebuild test -project <REPO_ROOT>/AIIslandApp.xcodeproj -scheme AIIslandApp -destination 'platform=macOS' -only-testing:AIIslandAppTests/CodexSessionIndexParserTests`

Expected: either parser-symbol failures or passing fixture-loading plumbing, but no file-not-found issues.

- [ ] **Step 4: Commit**

```bash
git add AIIslandAppTests/Fixtures/codex-live
git commit -m "test: add sanitized codex live fixtures"
```

## Task 1: Lock The Session Index Parser

**Files:**
- Create: `AIIslandApp/Monitoring/CodexSessionIndexParser.swift`
- Test: `AIIslandAppTests/CodexSessionIndexParserTests.swift`

`session_index.jsonl` is not a state machine. This parser must stay intentionally narrow: thread ID, `thread_name`, and `updated_at` only.

- [ ] **Step 1: Write the failing tests for thread index parsing**

```swift
func testParseSessionIndexPrefersNewestEntryPerThreadID() throws {
    let jsonl = """
    {"id":"thread-1","thread_name":"Old title","updated_at":"2026-04-11T01:00:00Z"}
    {"id":"thread-1","thread_name":"New title","updated_at":"2026-04-11T02:00:00Z"}
    {"id":"thread-2","thread_name":"Other thread","updated_at":"2026-04-11T01:30:00Z"}
    """

    let snapshots = CodexSessionIndexParser.parse(jsonl)

    XCTAssertEqual(snapshots.count, 2)
    XCTAssertEqual(snapshots.first?.threadName, "New title")
}

func testParseSessionIndexIgnoresMalformedRows() throws {
    let jsonl = """
    {"id":"thread-1","thread_name":"Valid","updated_at":"2026-04-11T02:00:00Z"}
    not-json
    {"thread_name":"Missing id"}
    """

    let snapshots = CodexSessionIndexParser.parse(jsonl)

    XCTAssertEqual(snapshots.count, 1)
    XCTAssertEqual(snapshots.first?.threadID, "thread-1")
}
```

- [ ] **Step 2: Run the focused tests to verify failure**

Run: `xcodebuild test -project <REPO_ROOT>/AIIslandApp.xcodeproj -scheme AIIslandApp -destination 'platform=macOS' -only-testing:AIIslandAppTests/CodexSessionIndexParserTests`

Expected: FAIL because `CodexSessionIndexParser` does not exist yet.

- [ ] **Step 3: Implement the minimal parser**

```swift
struct CodexIndexedThread: Equatable {
    let threadID: String
    let threadName: String
    let updatedAt: Date
}

enum CodexSessionIndexParser {
    static func parse(_ text: String) -> [CodexIndexedThread] {
        // Parse line-delimited JSON, keep the newest row for each thread ID,
        // and return rows sorted by descending updatedAt.
    }
}
```

- [ ] **Step 4: Run the focused tests to verify pass**

Run: `xcodebuild test -project <REPO_ROOT>/AIIslandApp.xcodeproj -scheme AIIslandApp -destination 'platform=macOS' -only-testing:AIIslandAppTests/CodexSessionIndexParserTests`

Expected: PASS with both parser tests green.

- [ ] **Step 5: Commit**

```bash
git add AIIslandApp/Monitoring/CodexSessionIndexParser.swift AIIslandAppTests/CodexSessionIndexParserTests.swift
git commit -m "test: lock codex session index parser"
```

## Task 2: Lock The Session Snapshot Parser

**Files:**
- Create: `AIIslandApp/Monitoring/CodexSessionSnapshotParser.swift`
- Test: `AIIslandAppTests/CodexSessionSnapshotParserTests.swift`

- [ ] **Step 1: Write failing parser tests for live session events**

```swift
func testParseSnapshotExtractsModelContextAndQuotaFromTokenCount() throws {
    let jsonl = """
    {"timestamp":"2026-04-11T01:57:03.186Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":46618},"model_context_window":258400},"rate_limits":{"primary":{"used_percent":50.0},"secondary":{"used_percent":8.0}}}}
    {"timestamp":"2026-04-11T01:57:03.221Z","type":"turn_context","payload":{"turn_id":"turn-1","model":"gpt-5.4"}}
    """

    let snapshot = CodexSessionSnapshotParser.parse(jsonl, sessionID: "thread-1", fallbackTaskLabel: "Fallback")

    XCTAssertEqual(snapshot.modelLabel, "gpt-5.4")
    XCTAssertEqual(snapshot.contextRatio, 46618.0 / 258400.0, accuracy: 0.0001)
    XCTAssertEqual(snapshot.fiveHourRatio, 0.50, accuracy: 0.0001)
    XCTAssertEqual(snapshot.weeklyRatio, 0.08, accuracy: 0.0001)
}

func testParseSnapshotResolvesWorkingVsThinkingVsAttention() throws {
    let workingJSONL = """
    {"type":"event_msg","payload":{"type":"task_started","turn_id":"turn-1"}}
    {"type":"event_msg","payload":{"type":"exec_command_begin","call_id":"call-1","turn_id":"turn-1"}}
    """

    let thinkingJSONL = """
    {"type":"event_msg","payload":{"type":"task_started","turn_id":"turn-1"}}
    """

    let attentionJSONL = """
    {"type":"event_msg","payload":{"type":"agent_message","message":"Need your approval before I continue.","phase":"final_answer"}}
    """

    XCTAssertEqual(CodexSessionSnapshotParser.parse(workingJSONL, sessionID: "t1", fallbackTaskLabel: "A").state, .working)
    XCTAssertEqual(CodexSessionSnapshotParser.parse(thinkingJSONL, sessionID: "t2", fallbackTaskLabel: "B").state, .thinking)
    XCTAssertEqual(CodexSessionSnapshotParser.parse(attentionJSONL, sessionID: "t3", fallbackTaskLabel: "C").state, .attention)
}

func testParseSnapshotPrefersLatestUserPromptForTaskLabel() throws {
    let jsonl = """
    {"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"继续向下推进，打磨到除了数据接入之外，其他都完全可用的状态。"}]}}
    """

    let snapshot = CodexSessionSnapshotParser.parse(jsonl, sessionID: "thread-1", fallbackTaskLabel: "Thread title")

    XCTAssertEqual(snapshot.taskLabel, "继续向下推进，打磨到除了数据接入之外，其他都完全可用的状态。")
}

func testParseSnapshotLeavesQuotaAndContextNilWithoutTokenCount() throws {
    let jsonl = """
    {"type":"event_msg","payload":{"type":"task_started","turn_id":"turn-1"}}
    {"type":"turn_context","payload":{"turn_id":"turn-1","model":"gpt-5.4-mini"}}
    """

    let snapshot = CodexSessionSnapshotParser.parse(jsonl, sessionID: "thread-2", fallbackTaskLabel: "Thread title")

    XCTAssertEqual(snapshot.modelLabel, "gpt-5.4-mini")
    XCTAssertNil(snapshot.contextRatio)
    XCTAssertNil(snapshot.fiveHourRatio)
    XCTAssertNil(snapshot.weeklyRatio)
    XCTAssertEqual(snapshot.trustLevel, .eventDerived)
}

func testParseSnapshotUsesFixtureBackedRealisticEventShapes() throws {
    let sessionJSONL = try fixtureText(named: "rollout-sample", ext: "jsonl")

    let snapshot = CodexSessionSnapshotParser.parse(
        sessionJSONL,
        sessionID: "fixture-thread",
        fallbackTaskLabel: "Fixture fallback"
    )

    XCTAssertFalse(snapshot.modelLabel.isEmpty)
    XCTAssertNotNil(snapshot.contextRatio)
}
```

- [ ] **Step 2: Run the focused tests to verify failure**

Run: `xcodebuild test -project <REPO_ROOT>/AIIslandApp.xcodeproj -scheme AIIslandApp -destination 'platform=macOS' -only-testing:AIIslandAppTests/CodexSessionSnapshotParserTests`

Expected: FAIL because the parser does not exist yet.

- [ ] **Step 3: Implement the parser with explicit pure helpers**

```swift
struct CodexSessionSnapshot: Equatable {
    let sessionID: String
    let taskLabel: String
    let modelLabel: String
    let contextRatio: Double?
    let fiveHourRatio: Double?
    let weeklyRatio: Double?
    let state: AgentGlobalState
    let updatedAt: Date?
    let trustLevel: CodexSnapshotTrustLevel
    let hasStructuredTokenSignal: Bool
    let hasStructuredActivitySignal: Bool
}

enum CodexSessionSnapshotParser {
    static func parse(
        _ text: String,
        sessionID: String,
        fallbackTaskLabel: String
    ) -> CodexSessionSnapshot {
        // Fold all lines once, track the latest turn_context model,
        // latest token_count ratios, the latest user input_text,
        // task_started / task_complete boundaries, unresolved command spans,
        // and emit explicit trust metadata so monitor code can distinguish
        // true partial data from total absence of data.
    }
}
```

- [ ] **Step 4: Encode deterministic arbitration metadata in the parser output**

```swift
extension CodexSessionSnapshot {
    var shouldRenderAsThread: Bool {
        state == .attention || state == .working || state == .thinking
    }

    func isRecentlyActive(relativeTo now: Date) -> Bool {
        guard let updatedAt else { return false }
        return now.timeIntervalSince(updatedAt) <= recentThreadWindow
    }
}
```

- [ ] **Step 5: Run the focused tests to verify pass**

Run: `xcodebuild test -project <REPO_ROOT>/AIIslandApp.xcodeproj -scheme AIIslandApp -destination 'platform=macOS' -only-testing:AIIslandAppTests/CodexSessionSnapshotParserTests`

Expected: PASS with parser regressions green.

- [ ] **Step 6: Commit**

```bash
git add AIIslandApp/Monitoring/CodexSessionSnapshotParser.swift AIIslandAppTests/CodexSessionSnapshotParserTests.swift AIIslandAppTests/Fixtures/codex-live
git commit -m "feat: add codex session snapshot parser"
```

## Task 3: Build The Live Codex Monitor

**Files:**
- Create: `AIIslandApp/Monitoring/CodexMonitor.swift`
- Test: `AIIslandAppTests/CodexMonitorSmokeTests.swift`

- [ ] **Step 1: Write the failing smoke test for the full chain**

```swift
@MainActor
func testRefreshNowBuildsCodexStateFromSessionIndexSessionJSONLAndPresentation() throws {
    // Create a temp CODEX_HOME with:
    // - session_index.jsonl
    // - sessions/2026/04/11/rollout-<thread>.jsonl
    // Then assert:
    // - state.online == true
    // - state.globalState == .working
    // - state.threads.count == 1
    // - thread task/model/context are visible
    // - quota fiveHour / weekly ratios are mapped
    // - AgentSectionPresentation renders visible rows and quota copy
}

@MainActor
func testRefreshNowPublishesStatusUnavailableWhenOnlySessionIndexIsReadable() throws {
    // Create a temp CODEX_HOME with session_index.jsonl only.
    // Then assert:
    // - state.online == true
    // - state.availability == .statusUnavailable
    // - state.globalState == .idle
    // - quota is unavailable
    // - primary status copy is "Status unavailable"
}

@MainActor
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
    XCTAssertEqual(AgentSectionPresentation(state: monitor.codexState).primaryStatusCopy, "Not running")
}
```

- [ ] **Step 2: Run the smoke test to verify failure**

Run: `xcodebuild test -project <REPO_ROOT>/AIIslandApp.xcodeproj -scheme AIIslandApp -destination 'platform=macOS' -only-testing:AIIslandAppTests/CodexMonitorSmokeTests`

Expected: FAIL because `CodexMonitor` does not exist yet.

- [ ] **Step 3: Implement a small monitor with injectable file-system roots**

```swift
@MainActor
final class CodexMonitor: ObservableObject {
    @Published private(set) var codexState: AgentState = .init(
        kind: .codex,
        online: false,
        availability: .offline,
        globalState: .offline,
        threads: [],
        quota: nil
    )

    init(
        fileManager: FileManager = .default,
        codexHomePath: String = NSHomeDirectory() + "/.codex"
    ) { ... }

    func start() { ... }
    func stop() { ... }
    func refreshNow() { ... }
}
```

- [ ] **Step 4: Implement deterministic multi-session arbitration and availability mapping**

```swift
let liveCandidates = snapshots.filter { snapshot in
    snapshot.shouldRenderAsThread || snapshot.isRecentlyActive(relativeTo: now)
}

let sortedThreads = liveCandidates.sorted { lhs, rhs in
    if statePriority(lhs.state) != statePriority(rhs.state) {
        return statePriority(lhs.state) > statePriority(rhs.state)
    }

    if lhs.updatedAt != rhs.updatedAt {
        return (lhs.updatedAt ?? .distantPast) > (rhs.updatedAt ?? .distantPast)
    }

    return lhs.threadID < rhs.threadID
}

let availability: AgentAvailability
if hasAnyReadableCodexArtifacts == false {
    availability = .offline
} else if sortedThreads.contains(where: { $0.trustLevel == .eventDerived }) {
    availability = .available
} else {
    availability = .statusUnavailable
}
```

- [ ] **Step 5: Compose monitor output into the existing domain contract**

```swift
let threads = sortedThreads.prefix(3).map {
    AgentThread(
        id: $0.sessionID,
        taskLabel: $0.taskLabel,
        modelLabel: $0.modelLabel,
        contextRatio: $0.contextRatio,
        state: $0.state
    )
}

let quota = AgentQuota(
    availability: fiveHourRatio == nil && weeklyRatio == nil ? .unavailable : .available,
    fiveHourRatio: fiveHourRatio,
    weeklyRatio: weeklyRatio
)
```

Availability semantics must be:

- `online = false` only when the monitor cannot find any readable recent Codex artifacts
- `online = true` with `availability = .statusUnavailable` when only fallback metadata is readable
- `online = true` with `availability = .available` when at least one event-derived live row exists

- [ ] **Step 6: Run the smoke tests to verify pass**

Run: `xcodebuild test -project <REPO_ROOT>/AIIslandApp.xcodeproj -scheme AIIslandApp -destination 'platform=macOS' -only-testing:AIIslandAppTests/CodexMonitorSmokeTests`

Expected: PASS with end-to-end live-data assertions and offline fallback assertions green.

- [ ] **Step 7: Commit**

```bash
git add AIIslandApp/Monitoring/CodexMonitor.swift AIIslandAppTests/CodexMonitorSmokeTests.swift
git commit -m "feat: add codex live monitor"
```

## Task 4: Wire The Root View To Live Codex Data

**Files:**
- Modify: `AIIslandApp/UI/IslandRootView.swift`

- [ ] **Step 1: Write a narrow regression test or preview-only assertion target if needed**

```swift
// If no view test is practical, keep this task implementation-only
// and rely on monitor smoke coverage plus full scheme tests.
```

- [ ] **Step 2: Replace fixture-backed Codex state with a live monitor**

```swift
@StateObject private var codexMonitor = CodexMonitor()

PromotionContainerView(
    coordinator: motionCoordinator,
    codex: codexMonitor.codexState,
    claude: claudeMonitor.claudeState
)
```

- [ ] **Step 3: Keep the current safe fallback semantics**

```swift
.onAppear {
    codexMonitor.start()
    claudeMonitor.start()
    motionCoordinator.configure(reducedMotionEnabled: reduceMotion)
}
```

If the monitor cannot read event-derived live data, it must publish `.statusUnavailable` instead of silently reviving fixture content. Use `.offline` only when recent Codex artifacts are absent or unreadable altogether.

- [ ] **Step 4: Run the app build**

Run: `xcodebuild -project <REPO_ROOT>/AIIslandApp.xcodeproj -scheme AIIslandApp -configuration Debug build`

Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Commit**

```bash
git add AIIslandApp/UI/IslandRootView.swift
git commit -m "feat: wire codex live monitor into island root"
```

## Task 5: Full Verification And Project Notes

**Files:**
- Modify: `PROGRESS.md`

- [ ] **Step 1: Run focused Codex regressions**

Run: `xcodebuild test -project <REPO_ROOT>/AIIslandApp.xcodeproj -scheme AIIslandApp -destination 'platform=macOS' -only-testing:AIIslandAppTests/CodexSessionIndexParserTests -only-testing:AIIslandAppTests/CodexSessionSnapshotParserTests -only-testing:AIIslandAppTests/CodexMonitorSmokeTests`

Expected: PASS.

- [ ] **Step 2: Run the full safe unit-test path**

Run: `xcodebuild test -project <REPO_ROOT>/AIIslandApp.xcodeproj -scheme AIIslandApp -destination 'platform=macOS'`

Expected: PASS with all existing hostless tests still green.

- [ ] **Step 3: Update project progress notes**

Add:
- a new completed task for Codex live monitoring
- the new focused test commands
- the deterministic multi-session arbitration rule
- the offline fallback regression lock
- the `statusUnavailable` partial-data fallback rule
- the source-of-truth hierarchy: JSONL primary, session index fallback, no SQLite / AX
- any gotchas about relying on `session_index.jsonl` and `sessions/*.jsonl`

- [ ] **Step 4: Commit**

```bash
git add PROGRESS.md
git commit -m "docs: record codex live monitor progress"
```

## Manual QA Checklist

- [ ] Launch the app with a live Codex session running and confirm the collapsed Codex side is no longer fixture-static.
- [ ] Confirm the expanded Codex card shows at least one real thread row.
- [ ] Confirm the thread row model label matches the real session model, not a hard-coded string.
- [ ] Confirm `Context XX%` changes when a new `token_count` event is emitted.
- [ ] Confirm the 5-hour and weekly quota bars match the latest `rate_limits.primary/secondary.used_percent`.
- [ ] Confirm a partial-data Codex environment shows `Status unavailable` instead of fake live state.
- [ ] Confirm offline fallback shows `Not running` when no active Codex session files are discoverable.

## Notes For The Reviewer

- No spec document exists in this repo right now. Review this plan against the approved in-chat direction from 2026-04-11:
  - scheme A only
  - no extra Codex bridge
  - prefer local event files over SQLite heuristics
  - preserve current Apple-like UI and feed it better live data instead of widening scope
- This plan intentionally avoids mandatory `ModelLabelFormatter` edits unless the sanitized live fixture reveals a real formatting mismatch.
- Review specifically for over-claiming precision. The implementation must separate verified values from inferred status and degrade to `.statusUnavailable` when only fallback metadata exists.
