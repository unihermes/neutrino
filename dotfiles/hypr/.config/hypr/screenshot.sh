#!/usr/bin/env bash
# Region screenshot: slurp picks the area, grim captures it, the result is
# saved to disk and copied to the clipboard at the same time via tee. Bound
# to Print in hyprland.lua.
set -euo pipefail

dir="$HOME/Pictures/Screenshots"
mkdir -p "$dir"

geometry=$(slurp) || exit 0   # empty on Esc/cancel -- nothing to capture
[[ -n $geometry ]] || exit 0

file="$dir/screenshot_$(date +%Y-%m-%d_%H-%M-%S).png"
grim -g "$geometry" - | tee "$file" | wl-copy --type image/png

notify-send -a Screenshot -i "$file" "Screenshot saved" "$(basename "$file")" &>/dev/null || true
