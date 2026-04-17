#!/usr/bin/env bash
set -euo pipefail

STATE="${1:-pinnedExpanded}"
SCENARIO="${2:-thread-overflow}"
APP_BUNDLE="${3:-/Users/chenyuanjie/developer/ai-dynamic-island-macos/.worktrees/visual-polish-steady-premium/build/DerivedData-visual/Build/Products/Debug/AIIslandApp.app}"

APP_BINARY="$APP_BUNDLE/Contents/MacOS/AIIslandApp"
LOG_PATH="${TMPDIR:-/tmp}/aiisland-review-app.log"

if [[ ! -x "$APP_BINARY" ]]; then
  echo "AIIslandApp binary not found at: $APP_BINARY" >&2
  exit 1
fi

killall AIIslandApp >/dev/null 2>&1 || true

if [[ "${AIISLAND_REVIEW_FORCE_BINARY:-0}" == "1" ]]; then
  AIISLAND_REVIEW_STATE="$STATE" \
  AIISLAND_REVIEW_SCENARIO="$SCENARIO" \
  "$APP_BINARY" >"$LOG_PATH" 2>&1 &
else
  open -na "$APP_BUNDLE" --args \
    --review-state "$STATE" \
    --review-scenario "$SCENARIO" >"$LOG_PATH" 2>&1
fi

echo "launched:$APP_BINARY"
echo "state:$STATE"
echo "scenario:$SCENARIO"
echo "log:$LOG_PATH"
