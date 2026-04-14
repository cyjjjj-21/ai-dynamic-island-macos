# Codex Monitor Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Harden the Codex monitor for long-running use by decomposing its oversized refresh pipeline into smaller tested units without changing the current UI-facing behavior.

**Architecture:** Preserve the current `AgentState` output, trust semantics, and freshness behavior, but split filesystem discovery, tail reading, snapshot arbitration, and monitor orchestration into separate units. This keeps the working behavior intact while reducing future bug surface area and making performance-sensitive paths easier to reason about and optimize.

**Tech Stack:** Swift, Foundation, XCTest, `xcodebuild`

---

## File Structure

- Create: `AIIslandApp/Monitoring/CodexSessionCatalog.swift`
  Purpose: discover candidate session files, sort them by recency, and cap the scan window deterministically.
- Create: `AIIslandApp/Monitoring/CodexSessionTailReader.swift`
  Purpose: encapsulate adaptive tail-window growth and partial-line trimming so the monitor no longer owns raw file IO details.
- Create: `AIIslandApp/Monitoring/CodexMonitorCache.swift`
  Purpose: hold shared cache models such as `CodexCachedModel` so cross-refresh model smoothing has a clear home outside the runtime shell.
- Create: `AIIslandApp/Monitoring/CodexMonitorArbitrator.swift`
  Purpose: own snapshot filtering, freshness decay, sorting, quota selection, diagnostics construction, and input/output cache threading for model-label smoothing.
- Modify: `AIIslandApp/Monitoring/CodexMonitor.swift`
  Purpose: become a smaller orchestration shell responsible for lifecycle, debounce, worker-queue execution, and publishing.
- Modify: `AIIslandApp/Monitoring/CodexSessionSnapshotParser.swift`
  Purpose: stay parser-only; only accept minimal helper extraction when it clarifies parser boundaries.
- Create: `AIIslandAppTests/CodexSessionCatalogTests.swift`
  Purpose: lock scan ordering, file cap behavior, UUID extraction, and watched-path inputs.
- Create: `AIIslandAppTests/CodexSessionTailReaderTests.swift`
  Purpose: lock adaptive tail growth, partial-first-line trimming, and large-file ceiling behavior.
- Create: `AIIslandAppTests/CodexMonitorArbitratorTests.swift`
  Purpose: lock trust-aware thread selection, availability transitions, fallback suppression rules, quota selection, model-cache threading, and diagnostics output independent of filesystem reads.
- Modify: `AIIslandAppTests/CodexMonitorSmokeTests.swift`
  Purpose: keep end-to-end protection while shrinking its responsibility to integration, not internal algorithm details.
- Modify: `PROGRESS.md`
  Purpose: record the hardening pass and any newly discovered monitor-runtime constraints.

### Task 1: Add Characterization Tests Around The Current Pipeline

**Files:**
- Create: `AIIslandAppTests/CodexSessionCatalogTests.swift`
- Create: `AIIslandAppTests/CodexSessionTailReaderTests.swift`
- Create: `AIIslandAppTests/CodexMonitorArbitratorTests.swift`
- Modify: `AIIslandAppTests/CodexMonitorSmokeTests.swift`

- [ ] **Step 1: Write failing catalog tests**

```swift
func testCatalogSortsNewestSessionFilesFirst() throws
func testCatalogCapsReturnedFilesAtConfiguredMaximum() throws
func testCatalogExtractsThreadIDFromRolloutFilenameWhenUUIDSuffixExists() throws
```

- [ ] **Step 2: Write failing tail-reader tests**

```swift
func testTailReaderTrimsPartialFirstLineWhenReadingFromMiddleOfFile() throws
func testTailReaderExpandsWindowUntilMinimumLineCountIsReached() throws
func testTailReaderStopsGrowingAtMaxWindowForLargeFiles() throws
```

- [ ] **Step 3: Write failing arbitrator tests**

```swift
func testArbitratorPublishesStatusUnavailableWhenOnlyFallbackIndexThreadsExist() throws
func testArbitratorPrefersAttentionThenWorkingThenThinkingThenIdle() throws
func testArbitratorSelectsQuotaFromNewestLiveSnapshotWithTokenSignals() throws
func testArbitratorBuildsDiagnosticsFromRecentParsedSnapshots() throws
func testArbitratorSuppressesFallbackThreadsWhenOnlyExpiredEventDerivedSnapshotsExist() throws
```

- [ ] **Step 4: Keep the existing smoke tests but trim them to integration-only assertions**

Keep:
- temp-dir fixture plumbing
- end-to-end `CodexMonitor -> AgentState`

Move pure algorithm assertions into the new focused test files, including:
- thread ID extraction
- stale snapshot suppression
- fallback suppression when expired `eventDerived` snapshots coexist with index-only fallback rows

- [ ] **Step 5: Run the focused Codex suites and verify failure**

Run: `xcodebuild test -project /Users/chenyuanjie/developer/ai-dynamic-island-macos/AIIslandApp.xcodeproj -scheme AIIslandApp -destination 'platform=macOS' -only-testing:AIIslandAppTests/CodexSessionCatalogTests -only-testing:AIIslandAppTests/CodexSessionTailReaderTests -only-testing:AIIslandAppTests/CodexMonitorArbitratorTests -only-testing:AIIslandAppTests/CodexMonitorSmokeTests`

Expected: FAIL because the extracted units do not exist yet and the old monitor still owns those responsibilities directly.

- [ ] **Step 6: Commit the red characterization tests**

```bash
git -C /Users/chenyuanjie/developer/ai-dynamic-island-macos add AIIslandAppTests/CodexSessionCatalogTests.swift AIIslandAppTests/CodexSessionTailReaderTests.swift AIIslandAppTests/CodexMonitorArbitratorTests.swift AIIslandAppTests/CodexMonitorSmokeTests.swift
git -C /Users/chenyuanjie/developer/ai-dynamic-island-macos commit -m "test: lock codex monitor hardening behavior"
```

### Task 2: Extract Session Discovery And Tail Reading

**Files:**
- Create: `AIIslandApp/Monitoring/CodexSessionCatalog.swift`
- Create: `AIIslandApp/Monitoring/CodexSessionTailReader.swift`
- Test: `AIIslandAppTests/CodexSessionCatalogTests.swift`
- Test: `AIIslandAppTests/CodexSessionTailReaderTests.swift`

- [ ] **Step 1: Implement the session catalog**

```swift
struct CodexSessionFileCandidate: Sendable {
    let url: URL
    let modifiedAt: Date
    let fileSize: UInt64
    let threadID: String
}

enum CodexSessionCatalog {
    static func discoverSessionFiles(
        fileManager: FileManager,
        sessionsDirectoryURL: URL,
        maxFiles: Int
    ) -> [CodexSessionFileCandidate]
}
```

- [ ] **Step 2: Implement the adaptive tail reader**

```swift
enum CodexSessionTailReader {
    static func readTail(
        atPath path: String,
        fileSize: UInt64,
        initialWindow: UInt64,
        maxWindow: UInt64,
        minimumLineCount: Int
    ) -> String?
}
```

- [ ] **Step 3: Move UUID/thread-ID extraction beside the catalog**

The monitor should no longer own filename parsing. Put the rollout/thread-ID mapping rules in the discovery unit and cover them with tests.

- [ ] **Step 4: Run focused extraction tests**

Run: `xcodebuild test -project /Users/chenyuanjie/developer/ai-dynamic-island-macos/AIIslandApp.xcodeproj -scheme AIIslandApp -destination 'platform=macOS' -only-testing:AIIslandAppTests/CodexSessionCatalogTests -only-testing:AIIslandAppTests/CodexSessionTailReaderTests`

Expected: PASS

- [ ] **Step 5: Commit the extraction**

```bash
git -C /Users/chenyuanjie/developer/ai-dynamic-island-macos add AIIslandApp/Monitoring/CodexSessionCatalog.swift AIIslandApp/Monitoring/CodexSessionTailReader.swift AIIslandAppTests/CodexSessionCatalogTests.swift AIIslandAppTests/CodexSessionTailReaderTests.swift
git -C /Users/chenyuanjie/developer/ai-dynamic-island-macos commit -m "refactor: extract codex session discovery and tail reading"
```

### Task 3: Extract Snapshot Arbitration And Shrink CodexMonitor

**Files:**
- Create: `AIIslandApp/Monitoring/CodexMonitorCache.swift`
- Create: `AIIslandApp/Monitoring/CodexMonitorArbitrator.swift`
- Modify: `AIIslandApp/Monitoring/CodexMonitor.swift`
- Test: `AIIslandAppTests/CodexMonitorArbitratorTests.swift`
- Test: `AIIslandAppTests/CodexMonitorSmokeTests.swift`

- [ ] **Step 1: Implement the arbitrator around the current refresh semantics**

Start by defining a shared cache model and result contract:

```swift
struct CodexCachedModel: Equatable, Sendable {
    let label: String
    let updatedAt: Date
}

struct CodexMonitorArbitrationResult: Equatable {
    let state: AgentState
    let diagnostics: AgentMonitorDiagnostics
    let updatedModels: [String: CodexCachedModel]
}
```

The arbitrator should own:
- readable-artifact detection
- fallback-index conversion
- freshness decay
- visible-thread sorting
- global-state resolution
- quota snapshot selection
- diagnostics payload construction
- application of cross-refresh model smoothing via `[String: CodexCachedModel] -> [String: CodexCachedModel]`

- [ ] **Step 2: Keep the existing behavior byte-for-byte where possible**

Preserve:
- `offline` vs `statusUnavailable` split
- trust-level ordering
- `maxVisibleThreads == 3`
- state priority ordering
- model cache application semantics
- the existing rule that fallback index threads stay suppressed when any event-derived snapshots exist, even if those event-derived rows have already aged out of the visible live window

- [ ] **Step 3: Refactor `CodexMonitor` into orchestration only**

After extraction, `CodexMonitor.swift` should mainly do:
- start/stop lifecycle
- debounce and coalescing
- worker-queue execution
- publish `AgentState`
- update watched paths
- hold the current cache dictionary as runtime state and thread it through the arbitrator result

It should stop owning the bulk of filesystem and arbitration logic.

- [ ] **Step 4: Run focused arbitration and smoke tests**

Run: `xcodebuild test -project /Users/chenyuanjie/developer/ai-dynamic-island-macos/AIIslandApp.xcodeproj -scheme AIIslandApp -destination 'platform=macOS' -only-testing:AIIslandAppTests/CodexMonitorArbitratorTests -only-testing:AIIslandAppTests/CodexMonitorSmokeTests`

Expected: PASS

- [ ] **Step 5: Commit the monitor shrink**

```bash
git -C /Users/chenyuanjie/developer/ai-dynamic-island-macos add AIIslandApp/Monitoring/CodexMonitorCache.swift AIIslandApp/Monitoring/CodexMonitorArbitrator.swift AIIslandApp/Monitoring/CodexMonitor.swift AIIslandAppTests/CodexMonitorArbitratorTests.swift AIIslandAppTests/CodexMonitorSmokeTests.swift
git -C /Users/chenyuanjie/developer/ai-dynamic-island-macos commit -m "refactor: shrink codex monitor refresh pipeline"
```

### Task 4: Full Regression, Runtime Sanity, And Notes

**Files:**
- Modify: `PROGRESS.md`
- Test: `AIIslandAppTests/CodexSessionCatalogTests.swift`
- Test: `AIIslandAppTests/CodexSessionTailReaderTests.swift`
- Test: `AIIslandAppTests/CodexMonitorArbitratorTests.swift`
- Test: `AIIslandAppTests/CodexMonitorSmokeTests.swift`

- [ ] **Step 1: Run the full regression suite**

Run: `xcodebuild test -project /Users/chenyuanjie/developer/ai-dynamic-island-macos/AIIslandApp.xcodeproj -scheme AIIslandApp -destination 'platform=macOS'`

Expected: PASS

- [ ] **Step 2: Do a quick complexity sanity check**

Run: `wc -l /Users/chenyuanjie/developer/ai-dynamic-island-macos/AIIslandApp/Monitoring/CodexMonitor.swift /Users/chenyuanjie/developer/ai-dynamic-island-macos/AIIslandApp/Monitoring/CodexMonitorArbitrator.swift /Users/chenyuanjie/developer/ai-dynamic-island-macos/AIIslandApp/Monitoring/CodexSessionCatalog.swift /Users/chenyuanjie/developer/ai-dynamic-island-macos/AIIslandApp/Monitoring/CodexSessionTailReader.swift`

Expected: `CodexMonitor.swift` is materially smaller than before, with the extracted files carrying the separated responsibilities.

- [ ] **Step 3: Update `PROGRESS.md`**

Capture:
- the new monitor decomposition
- why the hardening was needed
- which focused tests now protect the runtime
- any discovered performance or correctness edge case

- [ ] **Step 4: Commit the hardening notes**

```bash
git -C /Users/chenyuanjie/developer/ai-dynamic-island-macos add PROGRESS.md
git -C /Users/chenyuanjie/developer/ai-dynamic-island-macos commit -m "docs: record codex monitor hardening pass"
```
