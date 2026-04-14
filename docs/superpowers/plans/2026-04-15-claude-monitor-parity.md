# Claude Monitor Parity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Upgrade the Claude monitor from a single-session happy-path poller into a multi-session, freshness-aware monitor that matches the trust and arbitration quality already present in the Codex path.

**Architecture:** Keep the app-facing `AgentState` contract unchanged, but rebuild the Claude pipeline around explicit session discovery, transcript snapshot extraction, freshness decay, and deterministic thread arbitration. Reuse the existing realtime signal source and shared freshness policy, and shape the monitor around a pure refresh computation so behavior is easy to test without launching the app.

**Tech Stack:** Swift, Foundation, AppKit, SwiftUI, XCTest, `xcodebuild`

---

## File Structure

- Create: `AIIslandApp/Monitoring/ClaudeSessionCatalog.swift`
  Purpose: discover candidate Claude session metadata files, normalize them into a small typed model, and sort/filter them deterministically.
- Create: `AIIslandApp/Monitoring/ClaudeMonitorCache.swift`
  Purpose: hold shared file-scope cache models such as `ClaudeCachedModel` so the arbitrator and runtime shell do not depend on a private nested monitor type.
- Create: `AIIslandApp/Monitoring/ClaudeMonitorArbitrator.swift`
  Purpose: combine session metadata, transcript snapshots, bridge data, and freshness policy into the final `AgentState` and diagnostics payload.
- Modify: `AIIslandApp/Monitoring/ClaudeCodeMonitor.swift`
  Purpose: become a thin lifecycle/orchestration layer with event+poll scheduling, worker-queue refresh, and watched-path updates.
- Modify: `AIIslandApp/Monitoring/ClaudeCodeSnapshotParser.swift`
  Purpose: expose any extra helpers needed for multi-session task-label/state/model extraction while keeping parsing logic narrow.
- Create: `AIIslandAppTests/ClaudeSessionCatalogTests.swift`
  Purpose: lock candidate-session discovery, newest-first ordering, malformed-file skipping, and duplicate/session-switch edge cases.
- Create: `AIIslandAppTests/ClaudeMonitorArbitratorTests.swift`
  Purpose: lock freshness decay, multi-thread selection, primary-thread/global-state aggregation, availability transitions, model smoothing, and diagnostics source-hit behavior without filesystem coupling.
- Modify: `AIIslandAppTests/ClaudeCodeMonitorSmokeTests.swift`
  Purpose: add end-to-end temp-dir coverage for multiple concurrent Claude sessions, stale-session suppression, and active-session switching.
- Modify: `PROGRESS.md`
  Purpose: record the architecture change, verification summary, and any monitor-specific postmortem notes discovered during implementation.

### Task 1: Lock The Multi-Session Behavior With Tests

**Files:**
- Create: `AIIslandAppTests/ClaudeSessionCatalogTests.swift`
- Create: `AIIslandAppTests/ClaudeMonitorArbitratorTests.swift`
- Modify: `AIIslandAppTests/ClaudeCodeMonitorSmokeTests.swift`

- [ ] **Step 1: Write the failing catalog tests**

```swift
func testCatalogSortsSessionsByObservedAtDescending() throws
func testCatalogSkipsMalformedSessionFiles() throws
func testCatalogKeepsMultipleReadableSessionsInsteadOfOnlyNewestOne() throws
```

- [ ] **Step 2: Write the failing arbitrator tests**

```swift
func testArbitratorPrefersLiveBusySessionsOverOlderIdleSessions() throws
func testArbitratorDegradesCoolingSessionsToIdleButKeepsThemVisible() throws
func testArbitratorHidesExpiredSessionsAndMarksStatusUnavailableWhenNothingLiveRemains() throws
func testArbitratorKeepsLastKnownModelPerSessionDuringTransientTranscriptLoss() throws
func testArbitratorUsesDeterministicTieBreakForPrimaryVisibleThreadAndGlobalState() throws
```

- [ ] **Step 3: Extend the smoke tests with real temp-dir fixtures**

```swift
func testRefreshNowBuildsMultipleClaudeThreadsWhenTwoLiveSessionsExist() throws
func testRefreshNowIgnoresOlderSessionWhenNewerSessionHasRealBusySignals() throws
func testRefreshNowSwitchesVisiblePrimaryThreadWhenLatestLiveSessionChanges() throws
```

- [ ] **Step 4: Run the focused Claude test suites and verify failure**

Run: `xcodebuild test -project /Users/chenyuanjie/developer/ai-dynamic-island-macos/AIIslandApp.xcodeproj -scheme AIIslandApp -destination 'platform=macOS' -only-testing:AIIslandAppTests/ClaudeSessionCatalogTests -only-testing:AIIslandAppTests/ClaudeMonitorArbitratorTests -only-testing:AIIslandAppTests/ClaudeCodeMonitorSmokeTests`

Expected: FAIL with missing-symbol or behavior-mismatch errors proving the new multi-session path is not implemented yet.

- [ ] **Step 5: Commit the red tests**

```bash
git -C /Users/chenyuanjie/developer/ai-dynamic-island-macos add AIIslandAppTests/ClaudeSessionCatalogTests.swift AIIslandAppTests/ClaudeMonitorArbitratorTests.swift AIIslandAppTests/ClaudeCodeMonitorSmokeTests.swift
git -C /Users/chenyuanjie/developer/ai-dynamic-island-macos commit -m "test: lock claude multi-session monitor behavior"
```

### Task 2: Extract Session Discovery And Arbitration Units

**Files:**
- Create: `AIIslandApp/Monitoring/ClaudeMonitorCache.swift`
- Create: `AIIslandApp/Monitoring/ClaudeSessionCatalog.swift`
- Create: `AIIslandApp/Monitoring/ClaudeMonitorArbitrator.swift`
- Test: `AIIslandAppTests/ClaudeSessionCatalogTests.swift`
- Test: `AIIslandAppTests/ClaudeMonitorArbitratorTests.swift`

- [ ] **Step 1: Implement the shared cache model and session catalog**

```swift
struct ClaudeCachedModel: Equatable, Sendable {
    let label: String
    let updatedAt: Date
}

struct ClaudeSessionCandidate: Equatable, Sendable {
    let pid: Int32
    let sessionID: String
    let cwd: String
    let observedAt: Date
    let filePath: String
    let activity: ClaudeCodeSessionActivity?
}

enum ClaudeSessionCatalog {
    static func loadCandidates(
        fileManager: FileManager,
        sessionsDirPath: String
    ) -> [ClaudeSessionCandidate]
}
```

- [ ] **Step 2: Implement a pure arbitrator that preserves the existing UI contract**

```swift
struct ClaudeMonitorArbitrationResult: Equatable {
    let state: AgentState
    let diagnostics: AgentMonitorDiagnostics
    let watchedPaths: [String]
    let updatedModels: [String: ClaudeCachedModel]
}
```

- [ ] **Step 3: Encode deterministic rules in code comments and tests**

Rules to lock:
- prefer live sessions over stale ones
- prefer `attention` > `working` > `thinking` > `idle`
- keep cooling/recent-idle sessions visible as `idle`
- hide expired sessions
- fall back to `statusUnavailable` instead of pretending a live state
- keep model cache per session, not globally
- sort visible threads by:
  - state priority
  - freshness score / recency
  - trustworthiness of transcript/session signals
  - stable session ID tie-break
- derive `AgentState.globalState` from the highest-priority visible live session so collapsed-shell badge color and busy animation remain deterministic

- [ ] **Step 4: Run the focused tests to verify the new units pass**

Run: `xcodebuild test -project /Users/chenyuanjie/developer/ai-dynamic-island-macos/AIIslandApp.xcodeproj -scheme AIIslandApp -destination 'platform=macOS' -only-testing:AIIslandAppTests/ClaudeSessionCatalogTests -only-testing:AIIslandAppTests/ClaudeMonitorArbitratorTests`

Expected: PASS

- [ ] **Step 5: Commit the extraction**

```bash
git -C /Users/chenyuanjie/developer/ai-dynamic-island-macos add AIIslandApp/Monitoring/ClaudeMonitorCache.swift AIIslandApp/Monitoring/ClaudeSessionCatalog.swift AIIslandApp/Monitoring/ClaudeMonitorArbitrator.swift AIIslandAppTests/ClaudeSessionCatalogTests.swift AIIslandAppTests/ClaudeMonitorArbitratorTests.swift
git -C /Users/chenyuanjie/developer/ai-dynamic-island-macos commit -m "refactor: extract claude monitor catalog and arbitration"
```

### Task 3: Refactor ClaudeCodeMonitor Into A Thin Runtime Shell

**Files:**
- Modify: `AIIslandApp/Monitoring/ClaudeCodeMonitor.swift`
- Modify: `AIIslandApp/Monitoring/ClaudeCodeSnapshotParser.swift`
- Test: `AIIslandAppTests/ClaudeCodeMonitorSmokeTests.swift`

- [ ] **Step 1: Replace the single-session `findActiveSession()` flow with multi-session refresh computation**

Target shape:

```swift
private struct RefreshComputation: Sendable {
    let state: AgentState
    let diagnostics: AgentMonitorDiagnostics
    let watchedPaths: [String]
    let updatedModels: [String: ClaudeCachedModel]
}

private nonisolated static func computeRefresh(...) -> RefreshComputation
```

- [ ] **Step 2: Move refresh execution off the main actor**

Add:
- `isRunning`
- `refreshInFlight`
- `refreshDirty`
- `coalescedTrigger`
- `workerQueue`

Behavior to preserve:
- startup refresh
- event debounce
- keepalive poll
- safe stop/invalidation

- [ ] **Step 3: Update watched-path management to include all live candidate session files and transcript directories**

The monitor should keep watching:
- Claude session metadata directory
- Claude projects directory
- a bounded set of hottest live session metadata files
- matching transcript files for the visible/live candidate set only
- transcript parent directories only for the same bounded set
- per-session bridge files only for the visible/live candidate set

Bound the watcher set explicitly:
- define a small max live-watch budget, for example 6 sessions / 18-24 paths total
- prefer currently visible sessions, then freshest live sessions
- keep the base directories always watched so dropped sessions can re-enter without a restart
- document in code comments that this cap exists to avoid file-descriptor exhaustion and watcher restart churn in `VnodeRealtimeSignalSource`

- [ ] **Step 4: Keep parser responsibilities narrow**

Only add helpers to `ClaudeCodeSnapshotParser.swift` when the logic is about parsing transcript/session content. Do not move arbitration or freshness policy into the parser.

- [ ] **Step 5: Run the focused smoke tests**

Run: `xcodebuild test -project /Users/chenyuanjie/developer/ai-dynamic-island-macos/AIIslandApp.xcodeproj -scheme AIIslandApp -destination 'platform=macOS' -only-testing:AIIslandAppTests/ClaudeCodeMonitorSmokeTests`

Expected: PASS

- [ ] **Step 6: Commit the runtime refactor**

```bash
git -C /Users/chenyuanjie/developer/ai-dynamic-island-macos add AIIslandApp/Monitoring/ClaudeCodeMonitor.swift AIIslandApp/Monitoring/ClaudeCodeSnapshotParser.swift AIIslandAppTests/ClaudeCodeMonitorSmokeTests.swift
git -C /Users/chenyuanjie/developer/ai-dynamic-island-macos commit -m "refactor: rebuild claude monitor around multi-session refresh"
```

### Task 4: Verify Product-Level Behavior And Update Repo Notes

**Files:**
- Modify: `PROGRESS.md`
- Test: `AIIslandAppTests/ClaudeCodeMonitorSmokeTests.swift`

- [ ] **Step 1: Run the full regression suite**

Run: `xcodebuild test -project /Users/chenyuanjie/developer/ai-dynamic-island-macos/AIIslandApp.xcodeproj -scheme AIIslandApp -destination 'platform=macOS'`

Expected: PASS

- [ ] **Step 2: Spot-check the diagnostics contract**

Verify in tests or manual assertions that diagnostics now report:
- more than one thread when multiple sessions are live
- per-thread freshness stage
- source hits that distinguish session/transcript/bridge/model

- [ ] **Step 3: Update `PROGRESS.md`**

Record:
- the new Claude monitor architecture
- the added tests
- any discovered edge case such as session switching, stale bridge data, or model loss smoothing

- [ ] **Step 4: Commit the verification and notes**

```bash
git -C /Users/chenyuanjie/developer/ai-dynamic-island-macos add PROGRESS.md
git -C /Users/chenyuanjie/developer/ai-dynamic-island-macos commit -m "docs: record claude monitor parity upgrade"
```
