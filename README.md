# AI Dynamic Island macOS Prototype

`ai-dynamic-island-macos` is a dedicated macOS prototype for an AI-first Dynamic Island experience centered around the MacBook notch area. The app combines an AppKit shell with SwiftUI presentation and renders live Codex and Claude activity into a compact island that can expand into a richer status card.

The project is no longer just a static shell. It already includes:

- a notch-aware two-lobe island layout instead of a fake center capsule
- live Codex and Claude monitoring pipelines with fallback semantics
- deterministic fixtures and hostless tests for core presentation and monitor logic
- motion, hover, pin, diagnostics, and quota/context presentation behaviors

## Current State

This repository is still a prototype, but it is a working prototype rather than a blank scaffold.

What is implemented today:

- Collapsed island shell attached to the top hardware band
- Expanded card with per-agent sections, thread rows, quota strip, and fallback copy
- Codex monitor with session index fallback, structured snapshot parsing, realtime refresh orchestration, and bounded tail reads
- Claude monitor with multi-session discovery, transcript parsing, freshness decay, and per-session model smoothing
- Diagnostics panel and test-backed freshness policy behavior

What is intentionally not claimed yet:

- production packaging/distribution workflow
- hardened background daemon integration
- polished onboarding or settings UI
- long-running field telemetry or benchmark instrumentation

## Architecture

The repo is split so that domain logic and UI shell concerns stay testable:

- `AIIslandCore/`
  Shared domain contracts, fixtures, shell interaction state machine, and other pure logic that should remain hostless.
- `AIIslandApp/`
  The macOS app target, including AppKit shell, SwiftUI views, monitoring runtime, styling, and mascot rendering.
- `AIIslandAppTests/`
  Unit and smoke tests covering fixtures, shell interaction, monitor parsers, monitor arbitration, presentation behavior, and layout rules.
- `docs/`
  Planning, releases, and superpowers workflow artifacts used to steer the prototype.
- `scripts/`
  Small project utilities such as packaging verification and overlay review helpers.

## Monitor Design

Both live monitors now follow a layered approach, but each keeps its own platform-specific behavior.

### Codex

- Reads `~/.codex/session_index.jsonl` for index-level fallback state
- Scans `~/.codex/sessions/**/rollout-*.jsonl` for structured live session events
- Uses a bounded tail reader so large rollout logs do not force full-file reads on every refresh
- Preserves Codex-specific `event + poll + debounce + worker queue` orchestration
- Marks the agent as `statusUnavailable` when artifacts exist but no fresh live signal remains

### Claude

- Reads Claude session metadata plus transcript tails
- Supports multiple concurrent readable sessions
- Uses arbitration logic to decide visible threads, primary status, and model continuity
- Keeps transient model drops from wiping the last known model label too aggressively

## UI Behavior

The shell behavior is more specific than a generic menu-bar widget:

- The island leaves the physical notch gap open across the hardware band
- Hover expands the island, click pins it, and outside click or `Esc` collapses it
- Expanded-card hit regions are intentionally part of the active interaction canvas
- Motion uses a staged freshness-aware system instead of one-shot transitions
- Diagnostics can be surfaced for live monitor tuning

## Requirements

- macOS 14.0+
- Xcode with Swift 6 toolchain support

The project is configured with:

- `MACOSX_DEPLOYMENT_TARGET = 14.0`
- `SWIFT_VERSION = 6.0`

## Getting Started

### Open in Xcode

```bash
open AIIslandApp.xcodeproj
```

Then run the `AIIslandApp` scheme on macOS.

### Build and Test from the Command Line

Run the full test suite:

```bash
xcodebuild test \
  -project AIIslandApp.xcodeproj \
  -scheme AIIslandApp \
  -destination 'platform=macOS'
```

Run focused monitor regression suites:

```bash
xcodebuild test \
  -project AIIslandApp.xcodeproj \
  -scheme AIIslandApp \
  -destination 'platform=macOS' \
  -only-testing:AIIslandAppTests/CodexMonitorSmokeTests \
  -only-testing:AIIslandAppTests/ClaudeCodeMonitorSmokeTests
```

### Canonical Visual Review Capture

For UI work in this repo, the primary review artifact should come from the real running app window, not only from offscreen SwiftUI snapshots.

For deterministic expanded-state review, launch the app in a fixed scenario first:

```bash
scripts/launch_review_app.sh pinnedExpanded thread-overflow
```

The launcher uses `open -na ... --args` so the review app survives outside the current shell lifecycle while still receiving the explicit review state and scenario.

Then export the canonical same-frame review bundle:

```bash
python3 scripts/capture_review_bundle.py --app AIIslandApp
```

The script writes a bundle directory containing:

- `window.png`
  A same-frame crop taken from `desktop.png` using the discovered on-screen AI Island window bounds.
- `desktop.png`
  A full desktop capture for context.
- `metadata.json`
  The selected window id, bounds, display scale, and crop rectangle used for the capture.

This is the preferred “what you saw is what I reviewed” evidence path for visual QA because the context image and the focused crop come from the same real desktop frame.

If the real desktop is too dark to inspect fine details, keep this bundle as the primary on-screen evidence and use `AIIslandAppTests/VisualSnapshotSmokeTests` as secondary offscreen evidence for pixel inspection of the island itself.

## Notable Test Coverage

The repo intentionally leans on regression coverage because monitor behavior can drift subtly.

- `CodexMonitorSmokeTests`
  Verifies `CodexMonitor -> AgentState -> presentation` behavior, including fallback semantics, stale-signal decay, and rollout filename thread recovery.
- `CodexSessionCatalogTests`
  Locks session discovery ordering, scan limits, and thread ID extraction.
- `CodexSessionTailReaderTests`
  Locks tail expansion, partial-line trimming, and max-window behavior.
- `CodexMonitorArbitratorTests`
  Locks availability transitions, visible-thread ordering, quota selection, and expired-event suppression.
- `ClaudeCodeMonitorSmokeTests`
  Verifies multi-session Claude rendering and primary-thread switching.
- `ClaudeMonitorArbitratorTests`
  Verifies freshness decay, deterministic tie-breaks, and per-session model cache behavior.

## Diagnostics and Fixtures

- Canonical fixtures live under `AIIslandCore/Resources/Fixtures/`
- Sanitized Codex live fixtures live under `AIIslandAppTests/Fixtures/codex-live/`
- Runtime diagnostics are available in the expanded card for monitor tuning

## Packaging and Project Utilities

Available helper scripts:

- `scripts/verify_packaging.sh`
  Checks packaged output expectations.
- `scripts/overlay_notch_review.swift`
  Assists with notch/overlay review workflows.
- `scripts/launch_review_app.sh`
  Launches a deterministic review scenario using LaunchServices plus explicit review arguments.
- `scripts/capture_review_bundle.py`
  Exports a canonical visual review bundle using the real running app window plus desktop context and capture metadata.
- `scripts/macos_window_info.swift`
  Discovers the current on-screen macOS window metadata used by the review capture script.
- `scripts/macos_display_info.swift`
  Reports active display geometry and backing scale for same-frame crop calculation.

## Progress and Roadmap Context

If you want the full implementation history instead of the high-level project summary, read:

- `PROGRESS.md` for milestone-by-milestone status and completed tasks
- `docs/superpowers/` for plan and execution artifacts

## Status Summary

As of `2026-04-18`, the prototype has:

- Claude/Codex monitor hardening merged (multi-session arbitration, refresh ordering, and stale-signal guardrails)
- P0 thread naming/display uplift merged (stable semantic titles/details for Codex and Claude thread rows)
- latest spacing polish merged for the shell-to-expanded-card seam (`expandedCardTopSpacing` tightened from `4` to `2`)
- current `main` build verified with `xcodebuild build -project AIIslandApp.xcodeproj -scheme AIIslandApp -configuration Debug -derivedDataPath build/DerivedData/relaunch`

That keeps the repo on a stable prototype baseline for continued UI polish, packaging checks, and benchmark-oriented iteration.
