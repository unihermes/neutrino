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

log "installing repo packages"
list packages/pacman.txt | xargs -r sudo pacman -S --needed --noconfirm

log "installing AUR packages"
# Not --noconfirm: you want to see the PKGBUILD diffs.
list packages/aur.txt | xargs -r yay -S --needed

log "linking dotfiles"
mkdir -p "$HOME/.config"
if ! (cd dotfiles && stow -t "$HOME" -R -- */); then
  die "stow refused to link. A real file or directory is probably in the way;
      move the conflicting path out of ~/.config and rerun."
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
else
  warn "ly.service not found, nothing will start a graphical session at boot"
fi

log "verifying font and icon names actually resolve"
fc-match sans-serif
fc-match monospace
[[ -d /usr/share/icons/kora ]] || warn "kora icon theme not found in /usr/share/icons"

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
