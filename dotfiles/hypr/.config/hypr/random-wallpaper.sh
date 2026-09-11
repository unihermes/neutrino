#!/usr/bin/env bash
# Sets the wallpaper via swaybg to a random image from wallpapers/, once,
# at startup. Started from hyprland.lua's autostart block.
set -euo pipefail

wallpaper_dir="/home/giordano/Git/neutrino/wallpapers"

mapfile -t images < <(find "$wallpaper_dir" -maxdepth 1 -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' \) | sort)
(( ${#images[@]} > 0 )) || exit 0

swaybg -i "${images[RANDOM % ${#images[@]}]}" -m fill &
