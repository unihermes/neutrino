#!/usr/bin/env bash
# Link the dotfiles into $HOME and nothing else. No packages, no services, no
# sudo. Use this when you only want configs on a machine, or to relink after
# adding a new directory under dotfiles/.
set -euo pipefail

cd "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log() { printf '\033[1;34m::\033[0m %s\n' "$*"; }
die() { printf '\033[1;31mxx\033[0m %s\n' "$*" >&2; exit 1; }

command -v stow &>/dev/null || die "stow is not installed: sudo pacman -S stow"
[[ -d dotfiles ]] || die "no dotfiles/ directory next to this script"

mkdir -p "$HOME/.config"

# Enumerate the packages explicitly rather than passing a `*/` glob. Two traps
# there: stow collects package names during option parsing, so a `--` before
# them terminates parsing and leaves stow with an empty list ("No packages to
# stow or unstow"), and `*/` hands it names with trailing slashes.
mapfile -t stow_pkgs < <(find dotfiles -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort)
(( ${#stow_pkgs[@]} > 0 )) || die "no package directories found under dotfiles/"

# --simulate first, so a conflict is reported before anything is touched.
if ! (cd dotfiles && stow -t "$HOME" -R --simulate "${stow_pkgs[@]}") 2>/dev/null; then
  log "conflicts found, showing what stow objects to:"
  (cd dotfiles && stow -t "$HOME" -R --simulate "${stow_pkgs[@]}") || true
  die "move the real files named above out of the way, then rerun."
fi

log "linking: ${stow_pkgs[*]}"
(cd dotfiles && stow -t "$HOME" -R "${stow_pkgs[@]}")

log "done. verify a link with: ls -l ~/.config/hypr/hyprland.conf"
