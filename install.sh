#!/usr/bin/env bash
set -euo pipefail

cd "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log()  { printf '\033[1;34m::\033[0m %s\n'    "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n'    "$*" >&2; }
die()  { printf '\033[1;31mxx\033[0m %s\n'    "$*" >&2; exit 1; }

# Strip comments and blank lines from a package list.
list() { sed -e 's/#.*//' -e '/^[[:space:]]*$/d' "$1"; }

if [[ $EUID -eq 0 ]]; then
  die "run as your user, not root (sudo is called where it is needed)"
fi
command -v pacman &>/dev/null || die "this is an Arch provisioning script"

# Ask for sudo once up front so the rest of the run is unattended.
sudo -v

log "syncing and installing base tooling"
sudo pacman -Syu --needed --noconfirm base-devel git stow

if ! command -v yay &>/dev/null; then
  log "bootstrapping yay"
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT
  git clone --depth=1 https://aur.archlinux.org/yay-bin.git "$tmp/yay-bin"
  (cd "$tmp/yay-bin" && makepkg -si --noconfirm)
  rm -rf "$tmp"
  trap - EXIT
fi
yay --version >/dev/null || die "yay bootstrap failed"

# Read a package list into an array. NOT `| xargs`: xargs points its child's
# stdin at /dev/null, so any package manager that stops to ask a question
# reads EOF and aborts instead. That silently killed the whole AUR step.
read_list() {
  local -n _out=$1
  mapfile -t _out < <(list "$2")
}

log "installing repo packages"
read_list pacman_pkgs packages/pacman.txt
if (( ${#pacman_pkgs[@]} > 0 )); then
  sudo pacman -S --needed --noconfirm "${pacman_pkgs[@]}"
fi

log "installing AUR packages"
# Not --noconfirm: you want to see the PKGBUILD diffs before anything builds.
# --answerclean None only skips the "rebuild from scratch?" prompt; diffs and
# the install confirmation still stop for you.
aur_failed=0
read_list aur_pkgs packages/aur.txt
if (( ${#aur_pkgs[@]} > 0 )); then
  yay -S --needed --answerclean None "${aur_pkgs[@]}" || aur_failed=1
fi
# An AUR build breaking should not stop dotfiles and services from being set
# up. It gets reported again at the end so it cannot be missed.
if (( aur_failed )); then
  warn "one or more AUR packages failed, continuing"
fi

log "linking dotfiles"
mkdir -p "$HOME/.config"
# Enumerate the packages explicitly rather than passing a `*/` glob. Two traps
# there: stow collects package names during option parsing, so a `--` before
# them terminates parsing and leaves stow with an empty list ("No packages to
# stow or unstow"), and `*/` hands it names with trailing slashes.
mapfile -t stow_pkgs < <(find dotfiles -mindepth 1 -maxdepth 1 -type d -printf '%f
' | sort)
if (( ${#stow_pkgs[@]} == 0 )); then
  die "no package directories found under dotfiles/"
fi
log "  ${stow_pkgs[*]}"
if ! (cd dotfiles && stow -t "$HOME" -R "${stow_pkgs[@]}"); then
  die "stow failed; see its output above. If it names a conflict, move that
      real file or directory out of ~/.config and rerun."
fi

log "applying system settings"
fc-cache -f
gtk-update-icon-cache -f /usr/share/icons/kora 2>/dev/null || true
xdg-user-dirs-update || true
xdg-mime default thunar.desktop inode/directory
xdg-mime default org.pwmt.zathura.desktop application/pdf
xdg-settings set default-url-scheme-handler file thunar.desktop || true

log "enabling services"
sudo systemctl enable --now NetworkManager
systemctl --user enable --now pipewire pipewire-pulse wireplumber

# `systemctl cat` exits non-zero on a missing unit; `list-unit-files` does not,
# so it is the wrong test for "is this installed".
have_unit() { systemctl cat "$1" &>/dev/null; }

# VMware guest integration: clipboard sharing, resolution, drag and drop.
if have_unit vmtoolsd.service; then
  sudo systemctl enable --now vmtoolsd.service
  sudo systemctl enable --now vmware-vmblock-fuse.service || true
fi

# Display manager. Deliberately NOT --now: ly takes over a VT, and starting it
# here would pull the terminal out from under this script mid-run. It comes up
# on the next boot instead.
if have_unit ly.service; then
  sudo systemctl enable ly.service
  # Enabling a greeter is not enough on its own. archinstall's Minimal profile
  # leaves the default target at multi-user.target, which never pulls in
  # display-manager.service, so ly stays enabled and never actually starts.
  if [[ $(systemctl get-default) != graphical.target ]]; then
    log "switching default boot target to graphical.target"
    sudo systemctl set-default graphical.target
  fi
else
  warn "ly.service not found, nothing will start a graphical session at boot"
fi

log "verifying font and icon names actually resolve"
fc-match sans-serif
fc-match monospace
[[ -d /usr/share/icons/kora ]] || warn "kora icon theme not found in /usr/share/icons"

if (( aur_failed )); then
  warn "AUR packages did not all install. Rerun ./install.sh, or install the"
  warn "failures one at a time with: yay -S <name>"
fi

cat <<'EOF'

done. reboot, and ly will greet you -- pick Hyprland from the session list
with the left/right arrow keys.

If Hyprland fails to start on VMware's virtual GPU you will land back at the
greeter with no explanation. Drop to a TTY with ctrl+alt+F2, log in, and run
Hyprland by hand to see the actual error:

    Hyprland
    tail -40 ~/.local/share/hyprland/hyprland.log

Then uncomment the software-rendering env lines at the top of
~/.config/hypr/hyprland.conf, one block at a time.
EOF
