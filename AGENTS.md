# AGENTS.md

## Repo Scope

This repository is a macOS Dynamic Island prototype around the MacBook notch area.
Treat the notch relationship as a product constraint, not just a visual preference.

## Design Guardrails

- The top shell bar must read as one continuous island with the physical notch.
- The original top bar stays pure black in all states, including collapsed, hover-expanded, and pinned-expanded. Do not tint it toward blue, brown, gray, or any brand hue.
- If a visual pass makes the top bar look like a separate floating chip instead of notch hardware continuation, treat that as a regression.
- Premium quality should come from silhouette, spacing, typography, restrained highlights, and motion discipline, not from colorful material effects in the top shell bar.
- Expanded content below the bar can carry more material nuance, but it must emerge from an always-black top anchor.

## Verification

- Before handing off UI changes, build the `AIIslandApp` scheme successfully.
- For visual work, do not rely on ad hoc full-screen or offscreen-only screenshots as the primary evidence path.
- Primary visual QA artifact for this repo must come from `scripts/capture_review_bundle.py`, which exports one real desktop capture plus a same-frame crop and the capture metadata together.
- Offscreen reference snapshots can be used as secondary evidence for layout inspection, but not as the sole sign-off artifact.
