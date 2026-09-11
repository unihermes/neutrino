#!/usr/bin/env bash
# ALT+Tab: cycle focus (by recency, current workspace), then maximize
# whatever became active if it is not already -- so switching always lands
# on a full-screen window, like Windows alt-tab between maximized apps.
#
# hl.dsp.window.fullscreen(...) only toggles; there is no reliable "set"
# action in this Hyprland build (tested directly, it silently no-ops), so
# the toggle is guarded by checking the actual state first to avoid
# un-maximizing a window that was already maximized.
set -euo pipefail

hyprctl dispatch 'hl.dsp.window.cycle_next()' >/dev/null

fullscreen=$(hyprctl activewindow -j | python3 -c "import json,sys; print(json.load(sys.stdin).get('fullscreen', 0))" 2>/dev/null || echo 0)

if [[ $fullscreen == 0 ]]; then
  hyprctl dispatch 'hl.dsp.window.fullscreen({mode="maximized"})' >/dev/null
fi
