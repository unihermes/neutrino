#!/usr/bin/env bash
# Neutrino - wallpaper
# ~/.config/hypr/wallpaper.sh
#
#   wallpaper.sh            at login: the saved wallpaper, or a random one when
#                           shuffle is on or nothing is saved yet
#   wallpaper.sh set PATH   show PATH now
#   wallpaper.sh list       every image in wallpapers/, one per line
#   wallpaper.sh current    the image swaybg is showing
#
# The choice is saved by Quickshell's Appearance page (Wallpaper.qml) to
# ~/.local/state/neutrino/wallpaper.state as key=value lines rather than JSON,
# so this can read it without jq.
set -euo pipefail

# relative to this script's real location, so the repo can live anywhere
wallpaper_dir="$(realpath -m "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../../../../wallpapers")"
state="$HOME/.local/state/neutrino/wallpaper.state"

list() {
  find "$wallpaper_dir" -maxdepth 1 -type f \
    \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) | sort
}

# swaybg has no IPC, so changing the image means a new instance. The new one
# is started before the old one is killed: the other way round shows a frame
# of bare background between them.
show() {
  local old
  old=$(pgrep -x swaybg || true)
  swaybg -i "$1" -m fill &>/dev/null &
  disown
  if [[ -n $old ]]; then
    sleep 0.4
    kill $old 2>/dev/null || true
  fi
}

case "${1:-login}" in
  list) list ;;
  current)
    pid=$(pgrep -xn swaybg) || exit 0
    tr '\0' '\n' < "/proc/$pid/cmdline" | sed -n '/^-i$/{n;p;q}'
    ;;
  set)
    [[ -f ${2:-} ]] || { echo "no such image: ${2:-}" >&2; exit 1; }
    show "$2"
    ;;
  login)
    shuffle=1 saved=""
    if [[ -r $state ]]; then
      while IFS='=' read -r k v; do
        case $k in
          shuffle) shuffle=$v ;;
          wallpaper) saved=$v ;;
        esac
      done < "$state"
    fi
    if [[ $shuffle != 1 && -f $saved ]]; then
      show "$saved"
    else
      mapfile -t images < <(list)
      (( ${#images[@]} > 0 )) || exit 0
      show "${images[RANDOM % ${#images[@]}]}"
    fi
    ;;
  *) echo "usage: wallpaper.sh [login | set PATH | list | current]" >&2; exit 2 ;;
esac
