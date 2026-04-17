# Progress

## Snapshot

- Repo: `ai-dynamic-island-macos`
- Current branch: `main`
- Current HEAD: `dca3131` (polish promotion container glow effects)
- Phase: phase-1 prototype, subagent-driven execution

---

## Current Status

### Thread Naming P0 Hardening Completed (2026-04-17)

- Added semantic thread naming for Codex and Claude rows:
  - Codex titles are derived from cleaned user prompt candidates before falling back to session-index hints or workspace labels
  - Claude titles prefer `task-summary`, then quality-gated user prompt candidates / `last-prompt`, then workspace fallback
  - dirty HTML fragments, replacement characters, absolute paths, username-only workspaces, and execution-only prompts are filtered before they can become primary titles
- Added Claude prompt extraction from transcript tails:
  - `last-prompt` is captured as candidate material without changing fallback state
  - external user text / `input_text` content is captured as title candidates, while explicit non-external user entries are excluded
  - `tool_result` blocks remain excluded, including mixed user-message content blocks
  - state-only noise classification is named separately from prompt extraction so `last-prompt` remains valuable title material without driving fallback state
- Tightened Claude visibility gating after subagent review:
  - raw prompt presence no longer makes an idle Claude thread visible by itself
  - only prompt candidates that survive `ThreadTitleResolver` as `.claudePromptSummary` can act as a visibility signal
  - waiting/approval state remains detail copy, not the primary title
  - `task-summary` is sanitized before viability checks so harmless formatting fragments do not force a weaker fallback
- Tightened Codex title fallback after diagnosis review:
  - acknowledgement-only prompts such as `go`, `ok`, `继续`, and `review` no longer become primary titles
  - topic-like earlier prompts now outrank later low-context follow-up prompts
  - `session_index.thread_name` is cleaned before viability checks and trims `<br>` / `<br/>` / `<br />` tails before garbled suffixes can leak into UI
  - Codex-specific prompt rewrites stay source-aware so Claude prompt candidates do not receive Codex-branded quota titles
  - container-only workspaces such as `/Users/chenyuanjie/developer` still fall back to `Codex 任务` instead of showing a low-value directory name
- Verification:
  - focused red/green coverage added for Claude `last-prompt`, user prompt candidates, prompt-summary fallback, and execution-only prompt suppression
  - focused Claude/Codex monitor/title regression green:
    `xcodebuild test -project AIIslandApp.xcodeproj -scheme AIIslandApp -destination 'platform=macOS' -only-testing:AIIslandAppTests/ClaudeCodeMonitorSmokeTests -only-testing:AIIslandAppTests/ClaudeMonitorArbitratorTests -only-testing:AIIslandAppTests/ClaudeCodeSnapshotParserTests -only-testing:AIIslandAppTests/ThreadTitleResolverTests -only-testing:AIIslandAppTests/CodexMonitorArbitratorTests -only-testing:AIIslandAppTests/CodexMonitorSmokeTests`

### Codex Monitor Hardening Completed (2026-04-15)

- Reworked the Codex monitor toward the same layered shape proven by the Claude refactor, while keeping Codex-specific realtime orchestration intact:
  - session discovery and watched-path shaping now live in `CodexSessionCatalog`
  - bounded tail expansion for large `rollout-*.jsonl` files now lives in `CodexSessionTailReader`
  - freshness/state/quota/model arbitration now lives in `CodexMonitorArbitrator`
  - transient per-session model smoothing now uses `CodexCachedModel`
- Refactored `CodexMonitor` into a thinner runtime shell:
  - keeps the existing debounce + worker queue + keepalive refresh behavior
  - keeps Codex-specific session-index fallback semantics instead of copying Claude watcher behavior wholesale
  - narrows the monitor file so future freshness and ordering changes land in isolated helpers instead of a single long refresh path
- Locked the extraction with focused regression coverage:
  - `CodexSessionCatalogTests` for ordering, max-scan cap, and rollout filename thread-ID recovery
  - `CodexSessionTailReaderTests` for partial-line trimming, adaptive tail growth, and max-window bounding
  - `CodexMonitorArbitratorTests` for fallback availability, priority ordering, quota selection, and expired-event suppression
- Verification:
  - focused Codex regression green:
    `xcodebuild test -project AIIslandApp.xcodeproj -scheme AIIslandApp -destination 'platform=macOS' -only-testing:AIIslandAppTests/CodexSessionCatalogTests -only-testing:AIIslandAppTests/CodexSessionTailReaderTests -only-testing:AIIslandAppTests/CodexMonitorArbitratorTests -only-testing:AIIslandAppTests/CodexMonitorSmokeTests`
  - full `xcodebuild test -project AIIslandApp.xcodeproj -scheme AIIslandApp -destination 'platform=macOS'` green
  - validated edge cases:
    - rollout tails expand only when the recent window is too short to recover structured events
    - fallback session-index rows still publish `statusUnavailable` instead of pretending the agent is offline
    - expired event-derived snapshots no longer keep stale fallback threads visible
    - transient model loss remains isolated per Codex session instead of leaking across threads
    - stale in-flight refreshes no longer overwrite newer manual or event-triggered refresh results after restart
    - subagent review threads no longer surface as main Codex task rows such as `Please re-review...`
    - subagent detection now survives UTF-8 truncation windows and oversized first `session_meta` lines

### Claude/Codex Realtime Guardrails Completed (2026-04-15)

- Added shared regression helpers for monitor concurrency checks so both monitor pipelines now lock the same refresh-ordering guarantees.
- Hardened refresh lifecycle behavior in both monitor shells:
  - startup/manual/event refreshes now preserve the newest visible state when older worker-queue results complete late
  - restart while a stale refresh is still blocked no longer drops the current in-flight gate
- Added Codex-specific noise suppression for real-world multi-agent sessions:
  - lightweight session-head reads detect `session_meta` subagent markers before tail parsing
  - subagent-originated review prompts are filtered out of the primary thread list and watched-path set
- Verification:
  - focused smoke regressions green for both Claude and Codex monitor concurrency paths
  - full `xcodebuild test -project AIIslandApp.xcodeproj -scheme AIIslandApp -destination 'platform=macOS'` green after the guardrail pass

### Claude Monitor Parity Completed (2026-04-15)

- Rebuilt the Claude monitor from a single-session happy path into a multi-session pipeline:
  - session discovery now lives in `ClaudeSessionCatalog`
  - freshness/state/model arbitration now lives in `ClaudeMonitorArbitrator`
  - shared per-session model smoothing now uses `ClaudeCachedModel`
- Refactored `ClaudeCodeMonitor` into a thinner runtime shell:
  - keeps event debounce + keepalive poll behavior
  - runs refresh computation through a worker queue instead of doing all filesystem work on the main actor
  - bounds realtime watched-session fanout while always keeping the base Claude directories under watch
- Locked the new Claude behavior with dedicated tests:
  - `ClaudeSessionCatalogTests` for ordering, malformed-file skipping, and multi-session retention
  - `ClaudeMonitorArbitratorTests` for freshness decay, availability transitions, deterministic tie-breaks, and per-session model cache smoothing
  - `ClaudeCodeMonitorSmokeTests` for multi-live-session rendering and visible primary-thread switching
- Verification:
  - focused Claude regression green:
    `xcodebuild test -project AIIslandApp.xcodeproj -scheme AIIslandApp -destination 'platform=macOS' -only-testing:AIIslandAppTests/ClaudeSessionCatalogTests -only-testing:AIIslandAppTests/ClaudeMonitorArbitratorTests -only-testing:AIIslandAppTests/ClaudeCodeMonitorSmokeTests`
  - full `xcodebuild test -project AIIslandApp.xcodeproj -scheme AIIslandApp -destination 'platform=macOS'` green
  - validated edge cases:
    - multiple live Claude sessions render deterministically
    - cooling/recent-idle sessions decay to `idle` without disappearing too early
    - fully expired sessions collapse to `statusUnavailable`
    - transient transcript model loss keeps the last known model per session instead of leaking across sessions

### v0.2 Polish In Progress (2026-04-12)

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

### Release v0.1.0 (2026-04-11)

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

---

## Completed Tasks (Chronological Order)

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

### Task 6/7/8: Expanded card, real notch geometry, and interactive canvas

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

### Task 8/9: Wire shell interaction state into the motion root

- `ShellInteractionController` is now the source of truth for shell state and publishes `state` changes.
- `IslandWindowController` owns the controller and forwards passive hover enter/leave input from `HotzoneTrackingView`.
- `IslandRootView` now observes the live shell controller instead of hard-coding `.collapsed`, so motion phases can follow real shell input.
- Click-through remains intact; click monitoring is intentionally deferred until it can be added without swallowing menu-bar interaction.

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

### Task 11 Follow-up Hotfix: Codex realtime lag + context ratio correction

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

---

## Visual & UI Polish

### Shadow Cleanup and Edge Halo Pass

- Removed the visible shallow black drop shadow that sat underneath the island/card surfaces during live review.
- Replaced it with a narrower, much lighter black edge halo that stays tight to the shell/card silhouette instead of falling downward.
- Current visual intent:
  - no floating "panel shadow" under the collapsed island
  - expanded card reads as the same material family as the shell
  - glow remains subtle enough not to break the Apple-like restrained look

### Visual Clarity Pass (collapsed shell + quota colors)

- Collapsed shell now uses pure black fill (`#000`) to fuse with physical notch black; removed top highlight texture to avoid gray-film mismatch.
- Codex quota strip colors are now semantically separated from agent identity colors:
  - `5h`: light green
  - `Weekly`: deep green
- Goal:
  - avoid user confusion between "agent identity color" and "quota metric color" while improving notch fusion in default state.

### Expand Animation Polish

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

### Expanded Card Layout Alignment

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

---

## UI Postmortems

### Notch Geometry Miss

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

### Inner Lobe Geometry Was Still Too Timid

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

### Parameterized Notch Geometry Drifted Away From The Source Drawing

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

### Hover Expand Regression (v0.2)

- User-visible defect:
  - hover expand had early jump and stutter under pointer tracking
- Root cause:
  - default motion gain too aggressive + `Timer.scheduledTimer` default runloop mode caused event-loop-dependent stutter
- Missed QA step:
  - no guardrail test for "early hover frames must stay in lift/promote bands" and no explicit runloop-mode check for motion timer
- Systemic correction:
  - added regression test `testDefaultTuningKeepsEarlyHoverExpansionInLiftingOrPromotingBand`
  - moved motion timer to `.common` runloop mode
  - reduced default gains and removed first-frame forced step
- Prevention rule:
  - any interaction-critical motion change must ship with timing-band tests and non-default runloop-mode verification before visual sign-off

### Two Horizontal "Dark Lines" In Default State

- User-visible defect:
  - users could see two thin horizontal lines on screen/screenshot even when shell was not expanded.
- Root cause:
  - `CoreAnimationShellEffectsNSView` left/right reveal layers had non-zero baseline opacity when `progress == 0`:
    - `0.10 + (0.46 * p) + resonanceBoost`
  - this made the reveal glow permanently visible as two idle scanline-like bars.
- Missed QA step:
  - no assertion existed for "rest state (`p=0`) must render zero reveal opacity".
- Systemic correction:
  - added a gated `glowActivation` derived from progress (`(p - 0.08)/0.92`, clamped to `0...1`)
  - changed reveal and bridge opacities to multiply by `glowActivation`, so rest state is guaranteed `0`.
- Prevention rule:
  - all optional CA accent layers must use an explicit activation gate with a tested zero-output rest state.

### Expanded-State Glow Rendered At Bottom Of Screen

- User-visible defect:
  - during expansion, two blurred glow bars and a center smear appeared near the lower part of the desktop instead of under the top shell.
- Root cause:
  - CA overlay geometry was computed with `shellY = 0`, which maps to bottom-origin coordinates in the AppKit layer tree.
  - SwiftUI surface is top-aligned, so CA effects became vertically inverted relative to the shell/card.
- Missed QA step:
  - no explicit check that CA overlay anchor and SwiftUI anchor use the same vertical origin.
- Systemic correction:
  - changed CA shell anchor to top placement via `shellY = bounds.height - shellHeight`.
  - retained progress gating so idle state stays fully clean.
- Prevention rule:
  - for mixed SwiftUI + AppKit/CA surfaces, assert coordinate-origin alignment before tuning opacity/timing.

### Browser Typing Focus Was Stolen By Island Window

- User-visible defect:
  - while typing in browser, input focus could be interrupted and users saw cursor/focus being stolen.
- Root cause:
  - island panel was allowed to become key/main (`IslandPanel.canBecomeKey/canBecomeMain == true`)
  - island click path used `makeKeyAndOrderFront`, which could promote the island as key window.
- Missed QA step:
  - no regression check existed for "overlay shell must never become key/main while other apps are typing targets".
- Systemic correction:
  - force panel to stay non-key/non-main
  - replace click-time `makeKeyAndOrderFront` with non-activating `orderFront`
  - add hostless unit test `IslandPanelFocusTests` to lock focus policy.
- Prevention rule:
  - all overlay/notch windows must remain non-key unless there is an explicit text-input feature requiring focus ownership.

---

## Technical Fixes & Hotfixes

### Hover/Leave Jank Hotfix (v0.2 Runtime)

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

### Notch Alignment Fix: Runtime Detection Replaces Hardcoded Dimensions

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

### Leave Animation Fine-Tune Hook (reserved)

- If we need a later polish pass for "pointer leave feels too abrupt", tune in this order:
  - interaction delay gate: `ShellInteractionController.graceDelay` (`AIIslandCore/Shell/ShellInteractionController.swift`)
  - collapse easing speed: `IslandMotionTuning.snapBackGain` (`AIIslandApp/UI/Motion/IslandMotionCoordinator.swift`)
  - CA visual tail length: `animationDuration(for: .gentleSnapBack)` (`AIIslandApp/UI/Motion/PromotionContainerView.swift`)
  - card fade threshold: `cardOpacity = clamp((p - 0.34) / 0.58)` (`AIIslandApp/UI/Motion/PromotionContainerView.swift`)
- Rule:
  - keep delay + motion + opacity changes bundled in one QA round, otherwise perception often becomes "pause then snap"

---

## Debug Notes & Review Harness

### Task 3 Review / Debug Notes

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

### Task 9 Review / Debug Notes

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

### Review Harness Upgrade: Dimensions Notch Silhouette

- Root problem:
  - naked desktop screenshots on a notched Mac don't reliably communicate whether the island really fuses with the physical hardware zone
  - the first Apple top-strip overlay restored only a black band, not the actual notch cutout shape, so it was not valid for notch review
- New source of truth:
  - use the `Dimensions.com` engineering drawing for `Apple MacBook Pro - 14" (5th Gen)` as the primary notch-shape reference
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

---

## Incidents & Blockers

### Important Gotcha: UI Tests Popup Incident

There was a real user-visible popup incident during bootstrap.

- Symptom: repeated macOS popups saying `AIIslandAppUITests-Runner` was damaged and could not be opened.
- Root cause: a placeholder UI smoke test was added to the default shared scheme too early.
- Fix: the shared scheme was changed so default `xcodebuild test` runs unit tests only.
- Rule: keep `AIIslandAppUITests` scaffolded but out of the default `TestAction` until the harness phase is ready.

If this popup comes back, inspect:

- `AIIslandApp.xcodeproj/xcshareddata/xcschemes/AIIslandApp.xcscheme`
- whether any new UI test target was re-enabled in the shared scheme

### Packaging Incident

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

### QA Blocker: Desktop Screenshot Regression

- Symptom:
  - after the interactive canvas refactor, OS-level full-screen screenshots started returning black images even though focused xcodebuild verification stayed green
- Impact:
  - functional verification and hostless tests are green, but desktop screenshot-based visual QA is temporarily degraded
- Containment:
  - keep using build/test as the source of truth for behavior while this capture path is investigated
  - do not claim final visual polish complete until screenshot capture is reliable again

---

## Verified Test Coverage

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

---

## Architecture Notes

### Plan Drift To Keep In Mind

The implementation plan still mentions Task 2 files under `AIIslandApp/...`.
Actual repo architecture now uses a shared framework target:

- `AIIslandCore/...` for pure domain and fixture code
- `AIIslandApp/...` for app shell and UI

Update the plan before continuing too far with later tasks so future work does not target the wrong module.

---

## Next Recommended Steps

1. Codex live data integration — quota, model, thread list, and context usage still need the same level of contract locking Claude now has.
2. Claude multi-session arbitration — current monitor still picks the most recently modified session file, not an explicit active session.
3. Shell–card transition continuity — make the expanded card feel like a material extension of the island, not a separate popover.
4. Debug the black-screen desktop screenshot regression so visual QA can resume on the real desktop surface.
5. Keep future shell and motion logic hostless/testable whenever possible; only the AppKit shell should stay app-target-specific.

---

## Design Locks

- Keep the two-lobe top-attached shell that leaves the physical notch band open.
- Keep locked mascot references from the spec docs.
- `Claude` displays real backend third-party model names.
- `Codex` quota stays only in the Codex section header.
- Motion must feel like a smooth material promotion, not a generic popover animation.

---

## 2026-04-17: P0 thread naming and display uplift

Shipped the first pass of the P0 thread-title/detail redesign without increasing the expanded card height.

- `AgentThread` now separates stable `title` from live `detail`, carries `workspaceLabel`, `lastUpdatedAt`, and `titleSource`, and keeps legacy `taskLabel` JSON compatibility in both decode and encode paths.
- Added `ThreadTitleResolver` so Codex and Claude no longer surface raw latest prompts, dirty session-index titles, or home-directory usernames as thread names.
- Codex titles now prefer higher-quality prompt summaries, reject execution-only prompts such as “按这份 plan 开始 coding”, reject absolute-path fallbacks, and derive repo labels correctly from worktree paths.
- Claude titles now use `taskSummary` as the stable thread title and reserve `waitingFor` for compact detail copy such as `等待批准 Bash`.
- Suppressed Codex subagents still stay out of the top-level thread list, but recent child activity now folds back into the parent detail as a compact “`N 个子任务有更新`” signal.
- Expanded thread rows remain two-line rows with the same overall card height budget, but now render as `title + detail/status/context/recency` instead of raw prompt text plus a generic state pill.

Verification:

- `xcodebuild build -project AIIslandApp.xcodeproj -scheme AIIslandApp -destination 'platform=macOS'`
- `xcodebuild test -project AIIslandApp.xcodeproj -scheme AIIslandApp -destination 'platform=macOS' -only-testing:AIIslandAppTests/ThreadTitleResolverTests -only-testing:AIIslandAppTests/CodexSessionSnapshotParserTests -only-testing:AIIslandAppTests/CodexMonitorArbitratorTests -only-testing:AIIslandAppTests/CodexMonitorSmokeTests`
- `xcodebuild test -project AIIslandApp.xcodeproj -scheme AIIslandApp -destination 'platform=macOS' -only-testing:AIIslandAppTests/FallbackRenderingRulesTests -only-testing:AIIslandAppTests/ClaudeMonitorArbitratorTests -only-testing:AIIslandAppTests/ExpandedIslandReviewLayoutTests -only-testing:AIIslandAppTests/VisualSnapshotSmokeTests`
- Real desktop QA was re-run with `scripts/launch_review_app.sh pinnedExpanded thread-overflow` followed by `python3 scripts/capture_review_bundle.py --app AIIslandApp`; the captured review window stayed at `449x628pt`, confirming this pass did not grow the expanded island vertically.
