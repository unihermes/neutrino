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
./link.sh

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
# so it is the wrong test for "is this installed". The file check is a fallback
# for template units, which some systemd versions will not `cat`.
have_unit() {
  systemctl cat "$1" &>/dev/null     || [[ -f /usr/lib/systemd/system/$1 || -f /etc/systemd/system/$1 ]]
}

# Display manager. Deliberately NOT --now: ly takes over a VT, and starting it
# here would pull the terminal out from under this script mid-run. It comes up
# on the next boot instead.
# ly 1.x ships a templated unit that has to be bound to a VT (ly@tty2.service);
# 0.x shipped a plain ly.service. Detect rather than guess.
dm_unit=""
if have_unit ly@.service; then
  dm_unit="ly@tty2.service"
elif have_unit ly.service; then
  dm_unit="ly.service"
fi

if [[ -n $dm_unit ]]; then
  sudo systemctl enable "$dm_unit"
  # ly owns the VT it runs on, so the getty there has to go or the two fight
  # over tty2 and you get a garbled or flickering greeter.
  if [[ $dm_unit == ly@* ]]; then
    sudo systemctl disable getty@tty2.service &>/dev/null || true
  fi
  # Enabling a greeter is not enough on its own. archinstall's Minimal profile
  # leaves the default target at multi-user.target, which never pulls in
  # display-manager.service, so ly stays enabled and never actually starts.
  if [[ $(systemctl get-default) != graphical.target ]]; then
    log "switching default boot target to graphical.target"
    sudo systemctl set-default graphical.target
  fi
else
  warn "no ly unit found. Units the package ships:"
  pacman -Ql ly 2>/dev/null | grep '\.service$' || warn "  (none)"
fi

log "verifying font and icon names actually resolve"
fc-match sans-serif
fc-match monospace
[[ -d /usr/share/icons/kora ]] || warn "kora icon theme not found in /usr/share/icons"
if [[ ! -d /usr/share/icons/Bibata-Modern-Crosshair ]]; then
  warn "Bibata-Modern-Crosshair not found. Variants actually installed:"
  ls /usr/share/icons 2>/dev/null | grep -i bibata || warn "  (none)"
  warn "correct the name in hyprland.conf, gtk settings.ini and .icons/default"
fi

if (( aur_failed )); then
  warn "AUR packages did not all install. Rerun ./install.sh, or install the"
  warn "failures one at a time with: yay -S <name>"
fi

cat <<'EOF'

done. reboot, and ly will greet you -- pick Hyprland from the session list
with the left/right arrow keys.

If Hyprland does not start you land back at the greeter with no explanation.
Drop to a TTY with ctrl+alt+F3, log in, and run it by hand to see the error:

    Hyprland
    hyprctl configerrors
EOF
