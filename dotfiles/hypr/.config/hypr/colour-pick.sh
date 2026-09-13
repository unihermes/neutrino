#!/usr/bin/env bash
# Pick a colour anywhere on screen and copy its hex to the clipboard, with a
# notification showing what was copied. Started from the bar's Quick Actions.
set -uo pipefail

if ! command -v hyprpicker >/dev/null; then
    notify-send -a "Colour Picker" "hyprpicker is not installed" "pacman -S hyprpicker" &>/dev/null
    exit 1
fi

# -a copies on its own; the hex also comes back on stdout for the toast.
# Empty on Esc, which is a cancel, not an error.
hex=$(hyprpicker -a -f hex 2>/dev/null) || exit 0
[[ -n $hex ]] || exit 0

notify-send -a "Colour Picker" "Copied $hex" &>/dev/null || true
