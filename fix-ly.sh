#!/usr/bin/env bash
# Diagnose and fix a greeter that will not start.
#
# ly failing to appear at boot has four separate causes and they need different
# fixes. This works through all of them in order and prints what it found, so
# if it cannot fix the machine the output says why.
set -euo pipefail

log()  { printf '\033[1;34m::\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32mok\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mxx\033[0m %s\n' "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] && die "run as your user, not root"
command -v pacman &>/dev/null || die "this is an Arch script"

# --- 1. is ly installed at all -------------------------------------------
log "checking whether ly is installed"
if pacman -Q ly &>/dev/null; then
  ok "ly $(pacman -Q ly | awk '{print $2}') is installed"
else
  warn "ly is not installed"
  if pacman -Si ly &>/dev/null; then
    log "installing ly from the repos"
    sudo pacman -S --needed --noconfirm ly
  elif command -v yay &>/dev/null; then
    log "ly is not in the repos, trying the AUR"
    yay -S --needed ly || die "could not install ly from the AUR either"
  else
    die "ly is in neither the repos nor reachable via yay. Install it by hand."
  fi
fi

# --- 2. which unit does this version ship --------------------------------
# ly 1.x ships a templated unit bound to a VT; 0.x shipped a plain one. Ask the
# package rather than guessing, since the wrong name fails with the unhelpful
# "Unit ly.service could not be found".
log "finding the unit the package ships"
mapfile -t units < <(
  pacman -Ql ly 2>/dev/null | awk '{print $2}' | grep '\.service$' |
  while read -r f; do basename "$f"; done
)
if (( ${#units[@]} == 0 )); then
  die "the ly package ships no systemd unit at all, which should not happen"
fi
printf '   %s\n' "${units[@]}"

dm_unit=""
for u in "${units[@]}"; do
  [[ $u == ly@.service ]] && dm_unit="ly@tty2.service"
done
[[ -z $dm_unit ]] && for u in "${units[@]}"; do
  [[ $u == ly.service ]] && dm_unit="ly.service"
done
[[ -z $dm_unit ]] && dm_unit="${units[0]}"
ok "using $dm_unit"

# --- 3. is another display manager already in charge ---------------------
log "checking for a display manager already installed"
current=$(readlink -f /etc/systemd/system/display-manager.service 2>/dev/null || true)
if [[ -n $current && $current != *ly* ]]; then
  warn "display-manager.service currently points at:"
  warn "  $current"
  warn "only one greeter can own it. Disable that one first, for example:"
  warn "  sudo systemctl disable $(basename "$current")"
  die "refusing to fight with an existing display manager"
fi

# --- 4. enable it --------------------------------------------------------
log "enabling $dm_unit"
sudo systemctl enable "$dm_unit"

# ly owns the VT it runs on, so the getty there has to go or they contend for
# it and you get a flickering or garbled greeter.
if [[ $dm_unit == ly@* ]]; then
  tty=${dm_unit#ly@}; tty=${tty%.service}
  log "disabling getty@$tty so it does not fight ly for the VT"
  sudo systemctl disable "getty@$tty.service" &>/dev/null || true
fi

# --- 5. boot target ------------------------------------------------------
# Enabling a greeter is not enough. ly installs itself as an alias for
# display-manager.service, and only graphical.target ever pulls that in.
# archinstall's Minimal profile leaves the default at multi-user.target, so the
# greeter stays enabled and simply never starts.
log "checking the default boot target"
target=$(systemctl get-default)
if [[ $target == graphical.target ]]; then
  ok "already graphical.target"
else
  warn "default target is $target, which never starts a display manager"
  sudo systemctl set-default graphical.target
  ok "switched to graphical.target"
fi

# --- 6. report -----------------------------------------------------------
echo
log "state now:"
printf '   unit           %s\n' "$dm_unit"
printf '   enabled        %s\n' "$(systemctl is-enabled "$dm_unit" 2>&1)"
printf '   default target %s\n' "$(systemctl get-default)"
printf '   display-manager %s\n' \
  "$(readlink -f /etc/systemd/system/display-manager.service 2>/dev/null || echo '(not set)')"

echo
if ! systemctl is-enabled "$dm_unit" &>/dev/null; then
  warn "the unit still is not enabled. Recent journal entries:"
  journalctl -b -u "$dm_unit" --no-pager 2>/dev/null | tail -20 || true
  die "paste the above if you need help reading it"
fi

cat <<EOF

done. Reboot to get the greeter:

    sudo reboot

To test without rebooting, start it on its own VT and switch to it:

    sudo systemctl start $dm_unit
    # then ctrl+alt+F2

If it still does not appear after a reboot, this is what to capture:

    systemctl status $dm_unit --no-pager
    journalctl -b -u $dm_unit --no-pager | tail -40
EOF
