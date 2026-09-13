#!/usr/bin/env bash
# ALT+Tab: cycle focus by recency on the current workspace, then hand off to
# maximize-focused.sh, which maximizes what you landed on -- but only in
# monocle mode, and only if it isn't already filling the screen.
#
# That guard matters more than it looks. Testing the fullscreen *flag* is not
# enough: a window that is the only one on its workspace already occupies the
# whole usable area while still reporting fullscreen=0, so a flag-based guard
# re-maximizes it on every single alt-tab. The geometry never changes, but it
# is still a state change, so the window animates and its contents reflow --
# a visible resize for no reason.
set -euo pipefail

hyprctl dispatch 'hl.dsp.window.cycle_next()' >/dev/null
exec "$(dirname "$0")/maximize-focused.sh"
