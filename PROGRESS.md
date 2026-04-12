# Progress

## Snapshot

- Repo: `ai-dynamic-island-macos`
- Current branch: `main`
- Current HEAD: `506c6707fce61df83a26049f56b89d565f5089ec`
- Phase: phase-1 prototype, subagent-driven execution

## Release Prep (2026-04-11)

- Completed Codex/Claude thread sunset strategy implementation:
  - `<= 2m` keep live status
  - `2m ~ 15m` degrade to `idle`
  - `> 15m` hide stale thread row
  - `> 30m` mark status as unavailable
- Fixed Codex context-ratio source to prefer per-update token usage (`last_token_usage`) and remove the persistent `Context 100%` artifact.
- Added smoke-test coverage for the full monitor pipeline:
  - `CodexMonitor -> AgentState -> UI`
  - `ClaudeCodeMonitor -> AgentState -> UI`
- Performed publish-safe desensitization for public release:
  - replaced machine-specific absolute paths in docs/tests
  - replaced personal bundle identifiers with generic identifiers
- Release package produced:
  - `build/release/AIIslandApp-v0.1.0-macos.zip`
  - `sha256: 5267ea60bc1ef6b8743cd5cb995d695b87df64a4502ad3023b2242c9b3778e6d`

## v0.2 Polish In Progress (2026-04-12)

- Completed v0.2 architecture uplift with light hybrid motion:
  - added shared freshness policy contract in `AIIslandCore` (`3m / 12m / 25m / 45m`)
  - upgraded shell motion to continuous `phase + progress + interruption policy`
  - introduced CA-driven shell/glow bridge and mascot resonance matrix while keeping SwiftUI card rendering
- Completed monitor runtime refactor:
  - event-first + keepalive poll refresh pipeline
  - session-level `lastKnownModel` smoothing for transient model loss
  - status-priority + freshness-score mixed ordering for multi-thread display
- Added diagnostics tooling for tuning and live verification:
  - diagnostics panel in expanded card
  - per-thread freshness stage / source hits visibility
  - runtime toggle via `Cmd+Shift+D` / `AIISLAND_DIAGNOSTICS=1`
- Stabilized v0.2 regression tests:
  - converted Codex monitor smoke fixtures to relative-now timestamps so tests no longer silently rot by calendar date
  - adjusted motion coordinator phase-band test to deterministic gain/phase checkpoints
  - full `xcodebuild test` regression green after refresh-policy migration
- UI defect postmortem (hover expand regression):
  - root cause: default motion gain too aggressive + `Timer.scheduledTimer` default runloop mode caused early jump and event-loop-dependent stutter under pointer tracking
  - missed QA step: no guardrail test for "early hover frames must stay in lift/promote bands" and no explicit runloop-mode check for motion timer
  - systemic correction: added regression test `testDefaultTuningKeepsEarlyHoverExpansionInLiftingOrPromotingBand`; moved motion timer to `.common` runloop mode; reduced default gains and removed first-frame forced step
  - prevention rule: any interaction-critical motion change must ship with timing-band tests and non-default runloop-mode verification before visual sign-off

## Completed

### Task 1: Bootstrap repo and macOS app shell

- Created the dedicated macOS repo and Xcode project.
- Added `AIIslandApp` app target plus `AIIslandAppTests` and `AIIslandAppUITests`.
- Kept the app bootstrap minimal: menu-bar style app with no default window.
- Commit history:
  - `9c4effd6074ff976a66a66492477269a12a9898a` `chore: bootstrap macOS dynamic island app`
  - `4830ba951df49bcb301597cacab13d1e508c4088` `test: keep task 1 default tests unit-only`

### Task 2: Lock domain contracts and canonical fixtures

- Extracted pure domain and fixture logic into shared framework target `AIIslandCore`.
- Added normalized state contract:
  - `AIIslandCore/Domain/AgentState.swift`
  - `AIIslandCore/Domain/FixtureScenario.swift`
- Added deterministic fixture loading and scenario switching:
  - `AIIslandCore/Fixtures/FixtureBundleLoader.swift`
  - `AIIslandCore/Fixtures/FixtureStore.swift`
- Copied the canonical fixture bundle into repo resources:
  - `AIIslandCore/Resources/Fixtures/phase1-fixtures.json`
- Added hostless tests that import the real framework target:
  - `AIIslandAppTests/FixtureBundleLoaderTests.swift`
- Commit history:
  - `7626750d461f07f9e3b5aa8e4e6eca7477740c64` `feat: add canonical domain state and fixtures`
  - `cc9b1df1d3aa422ceca5a33efc4687ae78c509d7` `refactor: extract fixture logic into AIIslandCore`

### Task 3: Add shell interaction state machine

- Added pure shell interaction types under the shared framework:
  - `AIIslandCore/Shell/ShellInteractionState.swift`
  - `AIIslandCore/Shell/ShellInteractionController.swift`
- Added hostless state-machine tests:
  - `AIIslandAppTests/ShellInteractionControllerTests.swift`
- Current behavior locks:
  - `collapsed + pointerEnterHotzone -> hoverExpanded`
  - `hoverExpanded + pointerLeaveHotzone` schedules delayed collapse through an injectable scheduler
  - `hoverExpanded + clickIsland -> pinnedExpanded`
  - `collapsing + clickExpandedCard` remains a no-op per spec
  - `collapsing + collapseAnimationCompleted -> collapsed`

### Task 4: Import locked mascot assets

- Copied the locked mascot references into repo resources:
  - `AIIslandApp/Resources/Mascots/claude-mascot-reference.svg`
  - `AIIslandApp/Resources/Mascots/codex-soft-compute-blob-reference.svg`
  - `AIIslandApp/Resources/Mascots/mascot-asset-sheet.svg`
- Added deterministic runtime pixel renderers:
  - `AIIslandApp/UI/Mascots/MascotPixelGlyph.swift`
  - `AIIslandApp/UI/Mascots/PixelMascotView.swift`
  - `AIIslandApp/UI/Mascots/ClaudeMascotView.swift`
  - `AIIslandApp/UI/Mascots/CodexMascotView.swift`
- Runtime mascot rendering no longer depends on SVG parsing.

### Task 5: Build the unified collapsed island shell

- Added collapsed-shell styling tokens:
  - `AIIslandApp/UI/Styling/IslandPalette.swift`
- Added unified single-capsule collapsed shell:
  - `AIIslandApp/UI/Collapsed/CollapsedIslandView.swift`
- Added root fixture bridge:
  - `AIIslandApp/UI/IslandRootView.swift`
- AppKit shell now hosts the SwiftUI root inside the panel:
  - `AIIslandApp/Shell/IslandWindowController.swift`
- Default shell content resolves the `both-idle` fixture and renders locked Codex / Claude mascots inside one elongated capsule.

### Task 8/9: Wire shell interaction state into the motion root

- `ShellInteractionController` is now the source of truth for shell state and publishes `state` changes.
- `IslandWindowController` owns the controller and forwards passive hover enter/leave input from `HotzoneTrackingView`.
- `IslandRootView` now observes the live shell controller instead of hard-coding `.collapsed`, so motion phases can follow real shell input.
- Click-through remains intact; click monitoring is intentionally deferred until it can be added without swallowing menu-bar interaction.

### Task 6/7/8 follow-up: Expanded card, real notch geometry, and interactive canvas

- Added the expanded information layer under `AIIslandApp/UI/Expanded/`:
  - `ExpandedIslandCardView.swift`
  - `AgentSectionView.swift`
  - `AgentSectionPresentation.swift`
  - `ThreadRowView.swift`
  - `QuotaStripView.swift`
- Added `ModelLabelFormatter.swift` plus hostless tests so Codex and Claude backend model labels normalize correctly.
- Added fallback rendering rules and tests for:
  - offline
  - status unavailable
  - missing context
  - quota unavailable
  - overflow as `+N more`
- Replaced the old fake single-capsule notch silhouette with measured 14-inch MacBook Pro hardware metrics:
  - `32pt` top hardware band height
  - `185pt` physical notch avoidance gap
- Added:
  - `AIIslandApp/UI/Styling/IslandHardwareMetrics.swift`
  - `AIIslandApp/Shell/IslandCanvasLayout.swift`
- Current shell/canvas behavior:
  - collapsed shell is two top-attached lobes that leave the physical notch gap open
  - lobe inner edges stay visually straight along the top band, then widen inward in the lower half so the shell eats into the physical notch's bottom corner radius instead of stopping short
  - shell hit-testing matches the rendered lobe geometry instead of a fake center nick
  - expanded card lives in a larger interactive canvas below the 32pt top band
  - hover and pinned states now treat the expanded card area as part of the active region
  - clicking the shell pins expansion; clicking the expanded card upgrades hover to pinned; clicking outside / escape collapses

### Task 10: Rebuild Claude live monitoring around session metadata and transcript parsing

- Added a dedicated Claude monitor parsing layer:
  - `AIIslandApp/Monitoring/ClaudeCodeSnapshotParser.swift`
- Reworked `ClaudeCodeMonitor` so it now:
  - prefers Claude session PID metadata (`status`, `waitingFor`) for live activity
  - uses transcript `task-summary` for thread labels
  - distinguishes `thinking` vs `working` by tracking unresolved `tool_use` / `tool_result`
  - ignores custom bridge `agent_state` inference and only reads `used_pct` for context ratio
  - keeps active Claude rows visible even when the transcript temporarily lacks a model field
- Added focused parser coverage:
  - `AIIslandAppTests/ClaudeCodeSnapshotParserTests.swift`
- Added an end-to-end temp-dir smoke test that locks the chain:
  - fake `.claude/sessions/*.json`
  - fake transcript `.jsonl`
  - fake `claude-ctx-<session>.json`
  - `ClaudeCodeMonitor -> AgentState -> AgentSectionPresentation`
  - file: `AIIslandAppTests/ClaudeCodeMonitorSmokeTests.swift`
- To make the smoke test possible without touching the real machine state, `ClaudeCodeMonitor` now supports test-only injection of:
  - Claude root directory path
  - bridge temp directory path
  - process-alive checker
  - plus a narrow `refreshNow()` helper for deterministic test execution

### Task 11: Ship Codex live monitoring with trust-aware fallback semantics

- Added dedicated Codex parsing and monitoring components:
  - `AIIslandApp/Monitoring/CodexSessionIndexParser.swift`
  - `AIIslandApp/Monitoring/CodexSessionSnapshotParser.swift`
  - `AIIslandApp/Monitoring/CodexMonitor.swift`
- Added sanitized Codex live fixtures:
  - `AIIslandAppTests/Fixtures/codex-live/session_index.jsonl`
  - `AIIslandAppTests/Fixtures/codex-live/rollout-sample.jsonl`
  - `AIIslandAppTests/Fixtures/codex-live/README.md`
- Added focused Codex parser/monitor regression tests:
  - `AIIslandAppTests/CodexSessionIndexParserTests.swift`
  - `AIIslandAppTests/CodexSessionSnapshotParserTests.swift`
  - `AIIslandAppTests/CodexMonitorSmokeTests.swift`
- Rewired `IslandRootView` to live Codex state:
  - replaced fixture-backed Codex injection with `@StateObject private var codexMonitor = CodexMonitor()`
  - starts/stops Codex monitor lifecycle with the root view (`onAppear` / `onDisappear`)
- New runtime behavior locks:
  - source of truth hierarchy is now `sessions/**/*.jsonl` primary + `session_index.jsonl` fallback
  - `statusUnavailable` is used when only fallback metadata is readable (instead of pretending live status)
  - `offline` is reserved for truly unreadable / absent Codex artifacts
  - context/quota render only when `token_count` and `rate_limits` signals are present
  - `working` / `thinking` / `attention` are explicitly event-derived inference states

### Task 11 follow-up hotfix: Codex realtime lag + context ratio correction

- Fixed stale/laggy Codex thread inference in `CodexMonitor`:
  - rollout filename is now mapped back to real thread id (`rollout-...-<threadID>.jsonl`)
  - session tail reader is now adaptive (line-count aware, max-window capped) instead of fixed-byte-only
  - old active snapshots are freshness-gated to avoid historical thread bleed-through
- Fixed context ratio source in `CodexSessionSnapshotParser`:
  - now prefers `token_count.info.last_token_usage.total_tokens`
  - falls back to `total_token_usage.total_tokens` only when `last_token_usage` is absent
  - this removes the persistent `Context 100%` artifact caused by cumulative-session token totals
- Added regression coverage:
  - `CodexMonitorSmokeTests.testRefreshNowUsesThreadIDExtractedFromRolloutFilename`
  - `CodexMonitorSmokeTests.testRefreshNowExpandsSessionTailWhenRecentChunkContainsTooFewLines`
  - `CodexSessionSnapshotParserTests.testParseSnapshotPrefersLastTokenUsageForContextRatio`
- Runtime validation:
  - app restarted after hotfix and verified running from Debug build (`PID` updated in-session)

### Visual polish: shadow cleanup and edge halo pass

- Removed the visible shallow black drop shadow that sat underneath the island/card surfaces during live review.
- Replaced it with a narrower, much lighter black edge halo that stays tight to the shell/card silhouette instead of falling downward.
- Current visual intent:
  - no floating "panel shadow" under the collapsed island
  - expanded card reads as the same material family as the shell
  - glow remains subtle enough not to break the Apple-like restrained look

## Verified

### Safe default test path

Do not reintroduce UI tests into the default shared scheme yet.

This command is currently safe and passes:

```bash
xcodebuild test -project <REPO_ROOT>/AIIslandApp.xcodeproj -scheme AIIslandApp -destination 'platform=macOS'
```

The default scheme only runs unit tests now.

### Task 2 focused tests

This focused command passes:

```bash
xcodebuild test -project <REPO_ROOT>/AIIslandApp.xcodeproj -scheme AIIslandApp -destination 'platform=macOS' -only-testing:AIIslandAppTests/FixtureBundleLoaderTests
```

Covered tests:

- `testFixtureScenarioDeclaresAllCanonicalCases`
- `testFixtureBundleLoadsAllRequiredScenarios`
- `testFixtureStoreResolvesInitialScenario`
- `testFixtureStoreSwitchesScenario`
- `testFixtureStoreThrowsWhenInitialScenarioIsMissing`

### Task 2/3 focused regression

This command now passes:

```bash
xcodebuild test -project <REPO_ROOT>/AIIslandApp.xcodeproj -scheme AIIslandApp -destination 'platform=macOS' -only-testing:AIIslandAppTests/AIIslandAppBootstrapTests -only-testing:AIIslandAppTests/FixtureBundleLoaderTests -only-testing:AIIslandAppTests/ShellInteractionControllerTests
```

Covered tests include:

- all `FixtureBundleLoaderTests`
- all `ShellInteractionControllerTests`
- `AIIslandAppBootstrapTests.testUnitTestBundleLoadsWithoutHostApp()`

### Current app-shell build

This command passes with the current shell + mascot + collapsed UI wiring:

```bash
xcodebuild -project <REPO_ROOT>/AIIslandApp.xcodeproj -scheme AIIslandApp -configuration Debug build
```

### Current full hostless test path

This command passes:

```bash
xcodebuild test -project <REPO_ROOT>/AIIslandApp.xcodeproj -scheme AIIslandApp -destination 'platform=macOS'
```

Current passing coverage includes:

- `AIIslandAppBootstrapTests`
- `ClaudeCodeMonitorSmokeTests`
- `ClaudeCodeSnapshotParserTests`
- `FixtureBundleLoaderTests`
- `ShellInteractionControllerTests`
- `ModelLabelFormatterTests`
- `FallbackRenderingRulesTests`
- `IslandHardwareMetricsTests`
- `IslandShellHitRegionTests`
- `IslandCanvasLayoutTests`

### Current notch-overlap regression

This focused command passes:

```bash
xcodebuild test -project <REPO_ROOT>/AIIslandApp.xcodeproj -scheme AIIslandApp -destination 'platform=macOS' -only-testing:AIIslandAppTests/IslandShellHitRegionTests -only-testing:AIIslandAppTests/IslandCanvasLayoutTests
```

It currently locks:

- the top-edge physical notch gap remains non-interactive
- the lobe inner edges stay square at the top of the band
- the lower band overlaps inward enough to cover the notch's bottom corner radius
- the expanded card frame still sits below the top shell band

### Claude monitor regression locks

These focused commands pass:

```bash
xcodebuild test -project <REPO_ROOT>/AIIslandApp.xcodeproj -scheme AIIslandApp -destination 'platform=macOS' -only-testing:AIIslandAppTests/ClaudeCodeSnapshotParserTests
```

```bash
xcodebuild test -project <REPO_ROOT>/AIIslandApp.xcodeproj -scheme AIIslandApp -destination 'platform=macOS' -only-testing:AIIslandAppTests/ClaudeCodeMonitorSmokeTests
```

They currently lock:

- `waiting -> Attention` via session activity, not bridge-inferred state
- `busy + unresolved tool_use -> Working`
- `task-summary` contributes task label but does not overwrite fallback live state
- bridge `used_pct` still reaches thread `contextRatio`
- Claude thread rows stay visible through the monitor/presentation chain
- model labels continue to format as backend provider names in the expanded card

### Codex monitor regression locks

This focused command passes:

```bash
xcodebuild test -project <REPO_ROOT>/AIIslandApp.xcodeproj -scheme AIIslandApp -destination 'platform=macOS' -derivedDataPath <REPO_ROOT>/build/DerivedData -only-testing:AIIslandAppTests/CodexSessionIndexParserTests -only-testing:AIIslandAppTests/CodexSessionSnapshotParserTests -only-testing:AIIslandAppTests/CodexMonitorSmokeTests
```

It currently locks:

- Codex session-index parsing is deterministic and ignores malformed rows
- Codex snapshot parsing captures live model/context/quota/task signals from realistic JSONL
- partial-data sessions keep quota/context nil and avoid fabricated metrics
- monitor emits `.statusUnavailable` when only session-index fallback exists
- monitor emits `.offline` only when Codex artifacts are absent/unreadable
- end-to-end `CodexMonitor -> AgentState -> AgentSectionPresentation` remains stable
- context ratio uses per-update token usage (`last_token_usage`) when available, avoiding cumulative-token saturation at 100%

## Important Gotcha

There was a real user-visible popup incident during bootstrap.

- Symptom: repeated macOS popups saying `AIIslandAppUITests-Runner` was damaged and could not be opened.
- Root cause: a placeholder UI smoke test was added to the default shared scheme too early.
- Fix: the shared scheme was changed so default `xcodebuild test` runs unit tests only.
- Rule: keep `AIIslandAppUITests` scaffolded but out of the default `TestAction` until the harness phase is ready.

If this popup comes back, inspect:

- `AIIslandApp.xcodeproj/xcshareddata/xcschemes/AIIslandApp.xcscheme`
- whether any new UI test target was re-enabled in the shared scheme

## Packaging Incident

There was a second block-level launch incident while wiring `AIIslandCore` into the app target.

- Symptom: macOS popup saying `AIIslandApp` could not be opened because of a problem.
- Root cause:
  - app target was only linked against `AIIslandCore`
  - the framework was not embedded into `AIIslandApp.app/Contents/Frameworks`
  - `AIIslandCore` still advertised `/Library/Frameworks/...` as its install name
- Fix:
  - add an `Embed Frameworks` copy phase for `AIIslandCore`
  - set framework install name to `@rpath/$(EXECUTABLE_PATH)`
- Durable silent verifier:
  - `scripts/verify_packaging.sh`
  - builds into `build/DerivedData/packaging`
  - checks framework embedding and `@rpath` linkage without launching the app
- Silent verification path:

```bash
<REPO_ROOT>/scripts/verify_packaging.sh
```

Expected silent proof:

- framework exists under `Contents/Frameworks`
- framework install id is `@rpath/AIIslandCore.framework/Versions/A/AIIslandCore`
- app debug dylib links to `@rpath/AIIslandCore.framework/Versions/A/AIIslandCore`

## Plan Drift To Keep In Mind

The implementation plan still mentions Task 2 files under `AIIslandApp/...`.
Actual repo architecture now uses a shared framework target:

- `AIIslandCore/...` for pure domain and fixture code
- `AIIslandApp/...` for app shell and UI

Update the plan before continuing too far with later tasks so future work does not target the wrong module.

## Task 3 Review / Debug Notes

There was a compile-time block after tightening the shell controller to `@MainActor`.

- Symptom:
  - `ShellInteractionControllerTests.swift` failed to compile with actor-isolation errors against `send`, `state`, and the manual scheduler.
- Root cause:
  - the test class was still nonisolated while the controller, scheduler protocol, and helper types had moved onto `MainActor`
- Fix:
  - move the test class into `@MainActor`
  - make the scheduled closure contract explicitly `@MainActor`
  - remove the extra `Task { @MainActor ... }` hop inside the controller, because it introduced a race where tests could assert before the collapse state transition landed
- Result:
  - the shell interaction tests are deterministic again and pass under the main-actor contract

## Task 9 Review / Debug Notes

The first AppKit shell draft had two real interaction risks that were fixed before moving on:

- Symptom:
  - the transparent top panel could swallow clicks near the menu bar
  - top anchoring was only a one-time screen-top-center calculation with no notch/safe-area awareness
- Root cause:
  - the hotzone relied on tracking-view hit-testing instead of passive pointer-state sync
  - the window was positioned from `NSScreen.main` once at startup
- Fix:
  - switch the panel to click-through and make hover detection passive via pointer-state sync
  - re-anchor from a menu-bar-bearing screen, prefer notch-adjacent geometry when available, and re-run anchoring on screen-parameter / active-space changes
  - keep a shell-level forced hover reset path so later state-machine integration does not get stuck in a stale hover state
- Result:
  - the current shell remains buildable, click-through, and safer to evolve into real hover/pinned behavior

## UI Postmortem: Notch Geometry Miss

- User-visible defects:
  - shell sat visibly below the top edge
  - center used a fake V-shaped inward notch instead of a real physical notch gap
  - collapsed height did not match the real hardware notch band
- Root cause:
  - the first collapsed shell treated the MacBook notch like a decorative shape detail inside one pill, instead of treating the notch as a hard hardware exclusion zone
  - visual QA was done on the component in isolation, not against measured screen geometry
- Missed QA step:
  - we did not validate the shell against actual `NSScreen.safeAreaInsets` and `auxiliaryTopLeftArea` / `auxiliaryTopRightArea`
  - we also failed to inspect the collapsed shell in a real top-edge screenshot before iterating further
- Systemic correction:
  - promote measured hardware metrics into first-class layout data
  - use a real `IslandCanvasLayout` for shell frame + expanded card frame + hit regions
  - keep shell hit-testing and shell drawing on the same lobe geometry
- Prevention rule:
  - any notch-adjacent macOS UI must be verified against real screen metrics before visual polish work continues

## UI Postmortem: Inner Lobe Geometry Was Still Too Timid

- User-visible defect:
  - even after switching to two lobes, the inner edges still read like two separate rounded capsules because they did not push inward far enough to visually absorb the notch's lower corner radius
- Root cause:
  - the first lobe revision only made the inner edges technically straight and only added a conservative overlap, which satisfied geometry logic but not the real desktop silhouette
- Missed QA step:
  - we validated the presence of a physical notch gap, but we did not review whether the lower notch corners still visually leaked through between the lobes
- Systemic correction:
  - promote lower-notch overlap to an explicit palette metric and drive both rendering and hit-testing from the same overlap value
  - strengthen the regression probe so test points sit deeper inside the lower overlap zone, not just barely across the line
- Prevention rule:
  - for notch-fused chrome, passing geometry tests is not enough; we must also check that the lower notch radius is visually eaten, not merely respected

## QA Blocker: Desktop Screenshot Regression

- Symptom:
  - after the interactive canvas refactor, OS-level full-screen screenshots started returning black images even though focused xcodebuild verification stayed green
- Impact:
  - functional verification and hostless tests are green, but desktop screenshot-based visual QA is temporarily degraded
- Containment:
  - keep using build/test as the source of truth for behavior while this capture path is investigated
  - do not claim final visual polish complete until screenshot capture is reliable again

## Review Harness Upgrade: Dimensions Notch Silhouette

- Root problem:
  - naked desktop screenshots on a notched Mac don't reliably communicate whether the island really fuses with the physical hardware zone
  - the first Apple top-strip overlay restored only a black band, not the actual notch cutout shape, so it was not valid for notch review
- New source of truth:
  - use the `Dimensions.com` engineering drawing for `Apple MacBook Pro - 14” (5th Gen)` as the primary notch-shape reference
  - derive both a visual reference crop and a black silhouette directly from the downloaded `SVG/JPG`, not from hand-drawn geometry
- Repo assets:
  - `AIIslandApp/Resources/Hardware/macbook-pro-14-notch-reference-dimensions.jpg`
  - `AIIslandApp/Resources/Hardware/macbook-pro-14-notch-silhouette-dimensions.svg`
  - `AIIslandApp/Resources/Hardware/macbook-pro-14-notch-silhouette-dimensions.png`
  - `AIIslandApp/Resources/Hardware/APPLE_DESIGN_RESOURCES_NOTICE.md`
  - `scripts/overlay_notch_review.swift`
- Review rule:
  - do not review notch fusion from a raw screenshot anymore
  - do not use the old top-strip-only overlay as the primary notch reference
  - every notch-adjacent screenshot must first be composited with the `Dimensions`-derived notch silhouette

## UI Postmortem: Parameterized Notch Geometry Drifted Away From The Source Drawing

- User-visible defect:
  - even after moving to a top-attached shell, the negative space still looked hand-drawn because the runtime notch curve and the review overlay were both parameterized guesses rather than an extracted source path
- Root cause:
  - we treated the `Dimensions` drawing as a loose visual reference and reduced it to guessed metrics like shoulder height and overlap, instead of extracting the real inner display-boundary subpath and using that as the notch truth
- Missed QA step:
  - we did not isolate the inner display boundary curve from the front-view SVG before implementing runtime geometry
  - we also trusted raw macOS screenshots too early, even though screenshots include logical pixels behind the physical notch
- Systemic correction:
  - lock the front-view inner display boundary (`path #283` in `dimensions-mbp14.svg`) as the source of truth
  - derive the notch cutout directly from that closed path and reuse the same extracted cutout in runtime shell geometry, hit-testing, and review SVG assets
- Prevention rule:
  - for notch-adjacent chrome, never ship or review a hand-fit approximation when an authoritative vector source exists; extract the real cutout path first and keep all consumers on that same geometry

## Notch Alignment Fix: Runtime Detection Replaces Hardcoded Dimensions

- User-visible defect:
  - left and right lobe bars were offset ~10px left relative to the physical notch, breaking the illusion of a continuous horizontal "island"
  - the gap was not a simple center offset — it was a width mismatch causing both lobes to be too far apart
- Root cause:
  - `IslandHardwareMetrics.macBookPro14` used a notch width of `193.549pt` sourced from Dimensions.com engineering drawings
  - macOS `NSScreen.auxiliaryTopLeftArea` / `auxiliaryTopRightArea` APIs report the actual notch width as `185pt` — 8.5pt narrower
  - the 8.5pt difference caused each lobe to sit ~4.25pt away from where it should, creating visible gaps on both sides
  - `notchAnchorCenterX(for:)` was already using the correct API for centering, but `IslandPalette.physicalNotchWidth` / `lobeSpacing` still used the wrong 193.549pt value
- Fix:
  - added `IslandHardwareMetrics.detectFromScreen()` — queries `NSScreen` auxiliary areas at runtime for actual notch geometry
  - changed `IslandPalette.hardware` from `macBookPro14` to `detectFromScreen()`
  - set `notchCenterXCorrection = 0` (no longer needed with correct API-based dimensions)
  - `detectFromScreen()` falls back to `macBookPro14` when the API is unavailable (e.g., non-notched Macs)
- Verified alignment (on MacBook Pro 14"):
  - `auxiliaryTopLeftArea.maxX = 663`, `auxiliaryTopRightArea.minX = 848` → notch width = 185pt, center = 755.5pt
  - left lobe right edge: 663pt (matches API notch left boundary)
  - right lobe left edge: 848pt (matches API notch right boundary)
  - window: x=539, size=433×280, center=755.5pt
- All 8 test files still pass after the change

## Expand Animation Polish

- User-visible defects:
  - rounded corners of the shell were clipped when the island expanded outward on hover
  - the bottom edge of the shell lifted upward during expand, breaking alignment with the physical notch
  - an unwanted black shadow surrounded the island in the default (collapsed) state
- Root cause:
  - canvas width equaled shell width, so `scaleEffect(1.016)` caused the scaled shell to extend beyond the window bounds and get clipped
  - `shellYOffset` was negative during expansion (e.g., -1.05 at `.expanded`), and `scaleEffect(anchor: .center)` lifted the bottom edge
  - `ShellBandChrome` had two `.shadow()` modifiers (`shellDepthShadow` radius 16, `shellBottomShadow` radius 3) that rendered a dark halo around the shell
- Fix:
  - added `IslandPalette.scaleOverflowMargin = 8` and included it in `canvasWidth` calculation so the scaled shell has room to breathe
  - changed all motion phases' `shellYOffset` to 0 and switched `scaleEffect` from bidirectional to horizontal-only: `.scaleEffect(x:shellScale, y:1.0, anchor:.center)`
  - removed `.shadow()` modifiers from `ShellBandChrome` and `promotedShellBackdrop`
- Result: shell expands horizontally without clipping or lifting, no shadow in collapsed state

## Expanded Card Layout Alignment

- User-visible defects:
  - gap between the island shell and the expanded card was too large (12pt), making them look like separate objects
  - expanded card width (392pt) didn't match the shell width (~433pt), creating visual misalignment
  - bottom of the expanded card was truncated because the canvas height (280pt) was insufficient
- Root cause:
  - `expandedCardTopSpacing = 12` was set conservatively during initial layout
  - `expandedCardWidth` was hardcoded to 392 in `IslandHardwareMetrics` instead of aligning with the shell
  - `expandedCanvasHeight = 280` didn't account for the full card content height
- Fix:
  - reduced `expandedCardTopSpacing` from 12 to 4
  - changed `expandedCardWidth` to use `shellWidth` instead of the hardcoded hardware metric
- increased `expandedCanvasHeight` from 280 to 340

## Hover/Leave Jank Hotfix (v0.2 Runtime)

- User-visible defect:
  - pointer enter had ~1s delay before expansion
  - pointer leave could stall for ~3s before collapse
- Root cause:
  - heavy Codex refresh (`readSessionTail + JSON parse + ISO8601 parse`) ran on main actor
  - `sample` showed main thread blocked in `CodexMonitor.refresh -> CodexSessionSnapshotParser.parseDate -> CFDateFormatter`
- Fix:
  - reworked `CodexMonitor` to `event + poll` with async worker refresh and main-thread publish only
  - added in-flight coalescing and generation guard to avoid stale refresh overwrite
  - ensured poll timer runs in `.common` mode, preserving updates during tracking loops
  - moved parser date path from per-line formatter allocation to per-parse formatter reuse:
    - `CodexSessionSnapshotParser`
    - `CodexSessionIndexParser`
  - resolved Swift 6 actor/sendable constraints for the new pipeline
- Verification:
  - targeted tests:
    - `CodexMonitorSmokeTests`
    - `CodexSessionSnapshotParserTests`
    - `CodexSessionIndexParserTests`
  - full regression: `xcodebuild test -project AIIslandApp.xcodeproj -scheme AIIslandApp -destination 'platform=macOS'` passed
  - runtime sample now shows Codex parsing work on `com.aiisland.monitor.codex.worker`, not `com.apple.main-thread`

## Leave Animation Fine-Tune Hook (reserved)

- If we need a later polish pass for "pointer leave feels too abrupt", tune in this order:
  - interaction delay gate: `ShellInteractionController.graceDelay` (`AIIslandCore/Shell/ShellInteractionController.swift`)
  - collapse easing speed: `IslandMotionTuning.snapBackGain` (`AIIslandApp/UI/Motion/IslandMotionCoordinator.swift`)
  - CA visual tail length: `animationDuration(for: .gentleSnapBack)` (`AIIslandApp/UI/Motion/PromotionContainerView.swift`)
  - card fade threshold: `cardOpacity = clamp((p - 0.34) / 0.58)` (`AIIslandApp/UI/Motion/PromotionContainerView.swift`)
- Rule:
  - keep delay + motion + opacity changes bundled in one QA round, otherwise perception often becomes "pause then snap"

## Visual Clarity Pass (collapsed shell + quota colors)

- Collapsed shell now uses pure black fill (`#000`) to fuse with physical notch black; removed top highlight texture to avoid gray-film mismatch.
- Codex quota strip colors are now semantically separated from agent identity colors:
  - `5h`: light green
  - `Weekly`: deep green
- Goal:
  - avoid user confusion between "agent identity color" and "quota metric color" while improving notch fusion in default state.

## Next Recommended Steps

1. Codex live data integration — quota, model, thread list, and context usage still need the same level of contract locking Claude now has.
2. Claude multi-session arbitration — current monitor still picks the most recently modified session file, not an explicit active session.
3. Shell–card transition continuity — make the expanded card feel like a material extension of the island, not a separate popover.
4. Debug the black-screen desktop screenshot regression so visual QA can resume on the real desktop surface.
5. Keep future shell and motion logic hostless/testable whenever possible; only the AppKit shell should stay app-target-specific.

## Design Locks

- Keep the two-lobe top-attached shell that leaves the physical notch band open.
- Keep locked mascot references from the spec docs.
- `Claude` displays real backend third-party model names.
- `Codex` quota stays only in the Codex section header.
- Motion must feel like a smooth material promotion, not a generic popover animation.
