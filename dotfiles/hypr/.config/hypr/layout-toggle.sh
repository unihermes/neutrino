#!/usr/bin/env bash
# Toggle between monocle (every tiled window maximized, one visible at a
# time) and plain dwindle tiling.
#
# Hyprland has no monocle layout -- it ships dwindle and master only -- so
# monocle is emulated: dwindle stays the underlying layout and a window rule
# maximizes every tiled window as it opens. Toggling the rule is what
# switches "layout".
#
# The rule's handle is a Lua global in hyprland.lua, reachable here because
# `hyprctl eval` shares the config's Lua state. (`hyprctl keyword` refuses to
# run at all under the Lua parser -- it answers "can't work with non-legacy
# parsers. Use eval.")
#
# A window rule only applies as a window opens, so toggling also fixes the
# window you're looking at. The rest settle as you alt-tab onto them.
#
# State lives in XDG_RUNTIME_DIR so it is cleared on reboot, which puts it
# back in step with the config's default of monocle. A mid-session
# `hyprctl reload` re-enables the rule and can desync it; toggling twice
# fixes that.
set -euo pipefail

STATE="${XDG_RUNTIME_DIR:-/tmp}/neutrino-layout"
# absent means monocle -- the state hyprland.lua starts in
current=$(cat "$STATE" 2>/dev/null || echo monocle)

# 0 when the window is not maximized/fullscreen
is_full() {
  hyprctl activewindow -j 2>/dev/null \
    | python3 -c 'import json,sys; print(json.load(sys.stdin).get("fullscreen") or 0)' 2>/dev/null \
    || echo 0
}

if [[ $current == monocle ]]; then
  echo dwindle > "$STATE"
  hyprctl eval 'NeutrinoMonocleRule:set_enabled(false)' >/dev/null
  # drop the focused window out of maximized, otherwise the tiling it just
  # switched to is invisible
  [[ $(is_full) != 0 ]] && hyprctl dispatch 'hl.dsp.window.fullscreen({mode="maximized"})' >/dev/null
else
  echo monocle > "$STATE"
  hyprctl eval 'NeutrinoMonocleRule:set_enabled(true)' >/dev/null
  [[ $(is_full) == 0 ]] && hyprctl dispatch 'hl.dsp.window.fullscreen({mode="maximized"})' >/dev/null
fi

exit 0
