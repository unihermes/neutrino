#!/usr/bin/env bash
# Maximize the focused window, but only in monocle mode and only when it
# isn't already filling the screen.
#
# Shared by alt-tab.sh and the window.close hook so the "should this be
# maximized?" rule lives in one place. See alt-tab.sh for why the fullscreen
# flag alone is not a sufficient test.
set -euo pipefail

state="${XDG_RUNTIME_DIR:-/tmp}/neutrino-layout"
[[ $(cat "$state" 2>/dev/null || echo monocle) == monocle ]] || exit 0

# Focus does not move until after the closing window is gone, so callers
# firing on window.close need to let it settle before asking who is focused.
[[ ${1:-} == --settle ]] && sleep 0.12

needs_maximize=$(python3 - <<'PY' 2>/dev/null || echo 0
import json, subprocess, sys

def hypr(*args):
    out = subprocess.run(["hyprctl", "-j", *args], capture_output=True, text=True)
    return json.loads(out.stdout) if out.returncode == 0 and out.stdout.strip() else None

win = hypr("activewindow")
if not win or not win.get("class") or win.get("fullscreen"):
    print(0); sys.exit()
if win.get("floating"):
    print(0); sys.exit()

mons = hypr("monitors") or []
mon = next((m for m in mons if m.get("focused")), mons[0] if mons else None)
if not mon:
    print(0); sys.exit()

scale = mon.get("scale") or 1
left, top, right, bottom = (mon.get("reserved") or [0, 0, 0, 0])
usable_w = mon["width"] / scale - left - right
usable_h = mon["height"] / scale - top - bottom

w, h = win["size"]
already_full = abs(w - usable_w) <= 4 and abs(h - usable_h) <= 4
print(0 if already_full else 1)
PY
)

if [[ $needs_maximize == 1 ]]; then
  hyprctl dispatch 'hl.dsp.window.fullscreen({mode="maximized"})' >/dev/null
fi
exit 0
