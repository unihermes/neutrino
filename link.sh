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

# Move real files out of the way before stowing. Apps write their own configs
# when none exist -- Hyprland regenerates ~/.config/hypr/hyprland.conf on every
# start without one -- and that file then blocks stow from linking ours, so the
# app keeps reading its own default forever. Nothing is deleted: conflicts go
# to a timestamped backup. This is the safe version of `stow --adopt`, which
# would instead pull the app's file into the repo over what you wrote.
backup_conflicts() {
  local backup="$HOME/.config-backup-$(date +%Y%m%d-%H%M%S)"
  local pkg src rel target moved=0
  for pkg in "${stow_pkgs[@]}"; do
    while IFS= read -r -d "" src; do
      rel=${src#"dotfiles/$pkg/"}
      target="$HOME/$rel"
      # A symlink is either already ours or stow's to replace. Only a real
      # file is a genuine conflict.
      if [[ -f $target && ! -L $target ]]; then
        mkdir -p "$backup/$(dirname "$rel")"
        mv "$target" "$backup/$rel"
        log "  displaced $rel"
        moved=1
      fi
    done < <(find "dotfiles/$pkg" -type f -print0)
  done
  (( moved )) && log "originals saved in $backup"
  return 0
}

backup_conflicts

log "linking: ${stow_pkgs[*]}"
(cd dotfiles && stow -t "$HOME" -R "${stow_pkgs[@]}")

log "done. verify a link with: ls -l ~/.config/hypr/hyprland.conf"
