#!/usr/bin/env bash
# Strip a system back to base Arch so install.sh can provision it from a known
# state. Removes every explicitly-installed package that is not on the keep
# list, then their orphaned dependencies, then unlinks this repo's dotfiles.
#
# DRY RUN BY DEFAULT. Prints what it would do and exits. Pass --apply to act.
set -euo pipefail

cd "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log()  { printf '\033[1;34m::\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mxx\033[0m %s\n' "$*" >&2; exit 1; }

APPLY=0
[[ ${1:-} == --apply ]] && APPLY=1

[[ $EUID -eq 0 ]] && die "run as your user, not root"
command -v pacman &>/dev/null || die "this is an Arch script"

# Never removable, whatever the keep list says. These are the packages whose
# loss means an unbootable or unrecoverable machine, and `linux` is not a
# dependency of `base`, so pacman would not stop you on its own.
PROTECTED='^(base|base-devel|linux|linux-lts|linux-zen|linux-hardened|linux-firmware.*|systemd|systemd-libs|pacman|sudo|bash|glibc|coreutils|filesystem|mkinitcpio|efibootmgr|networkmanager|intel-ucode|amd-ucode|git)$'

list() { sed -e 's/#.*//' -e '/^[[:space:]]*$/d' "$1"; }

mapfile -t keep < <(list packages/keep.txt)
mapfile -t explicit < <(pacman -Qqe)

# Everything explicitly installed, minus the keep list, minus the protected set.
remove=()
for pkg in "${explicit[@]}"; do
  [[ " ${keep[*]} " == *" $pkg "* ]] && continue
  [[ $pkg =~ $PROTECTED ]] && continue
  remove+=("$pkg")
done

# Ask pacman to resolve the set, and rescue whatever it objects to.
#
# A package on the remove list may turn out to be required by one that is
# staying. pacman rejects the whole transaction when that happens, naming the
# offender as "removing X breaks dependency 'Y' required by Z". Rather than
# giving up and making you edit keep.txt by hand, pull X out of the removal set
# and ask again. Each pass can expose blockers hidden behind the last, so this
# repeats until pacman is satisfied.
rescued=()
txn=""
if (( ${#remove[@]} > 0 )); then
  log "${#remove[@]} explicitly-installed packages are candidates for removal"
  pass=0
  while (( ${#remove[@]} > 0 )); do
    # The real removal is -Rns, but pacman rejects --nosave alongside --print,
    # so the preview drops the -n. It makes no difference to which packages are
    # listed: --nosave only controls whether owned config files are kept as
    # .pacsave, and --print resolves the same dependency set either way.
    if txn=$(sudo pacman -Rs --print "${remove[@]}" 2>&1); then
      break
    fi

    mapfile -t blockers < <(
      sed -n "s/.*removing \([^ ]*\) breaks dependency.*/\1/p" <<<"$txn" | sort -u
    )
    if (( ${#blockers[@]} == 0 )); then
      printf '%s\n' "$txn" >&2
      die "pacman refused this set for a reason this script cannot parse.
      The output above is the whole error."
    fi
    if (( ++pass > 20 )); then
      die "still unresolved after 20 passes, giving up rather than looping."
    fi

    kept=()
    for pkg in "${remove[@]}"; do
      [[ " ${blockers[*]} " == *" $pkg "* ]] || kept+=("$pkg")
    done
    remove=("${kept[@]}")
    rescued+=("${blockers[@]}")
    log "keeping ${blockers[*]} -- needed by a package that is staying"
  done
fi

if (( ${#remove[@]} == 0 )); then
  log "nothing left to remove, this system is already at base"
else
  log "${#remove[@]} packages would go:"
  printf '   %s\n' "${remove[@]}"
  echo
  log "with dependencies, the full transaction is:"
  printf '%s\n' "$txn"
fi

if (( ${#rescued[@]} > 0 )); then
  echo
  warn "${#rescued[@]} rescued automatically, something kept depends on them:"
  printf '   %s\n' "${rescued[@]}"
  warn "this is worked out fresh on every run, so nothing needs saving. Add"
  warn "them to packages/keep.txt anyway if you want the decision recorded."
fi

# Symlinks into this repo. Removing a link never touches the repo file.
links=()
if [[ -d dotfiles ]]; then
  repo=$PWD
  while IFS= read -r -d "" l; do
    [[ $(readlink -f "$l") == "$repo"/* ]] && links+=("$l")
  done < <(find "$HOME/.config" -maxdepth 3 -type l -print0 2>/dev/null)
fi
if (( ${#links[@]} > 0 )); then
  echo
  log "${#links[@]} dotfile symlinks into this repo would be unlinked:"
  printf '   %s\n' "${links[@]}"
fi

if (( ! APPLY )); then
  cat <<'EOF'

DRY RUN. Nothing was changed.

Read the list above properly. Anything you need that is not in
packages/keep.txt should be added there first, especially a network daemon
other than NetworkManager, or a bootloader package.

Rerun with --apply when the list looks right.
EOF
  exit 0
fi

echo
warn "This removes the packages listed above and cannot be undone."
warn "Make sure you can get back online without them."
read -r -p "Type STRIP to continue: " answer
[[ $answer == STRIP ]] || die "aborted"

if (( ${#remove[@]} > 0 )); then
  log "removing packages"
  sudo pacman -Rns --noconfirm "${remove[@]}"
fi

log "removing orphaned dependencies"
while true; do
  mapfile -t orphans < <(pacman -Qqdt 2>/dev/null || true)
  (( ${#orphans[@]} == 0 )) && break
  sudo pacman -Rns --noconfirm "${orphans[@]}"
done

for l in "${links[@]:-}"; do
  [[ -n $l ]] && rm -f "$l"
done

log "clearing the package cache"
sudo pacman -Scc --noconfirm || true

cat <<'EOF'

done. The system is back to base plus whatever packages/keep.txt protects.

Reboot before provisioning, so nothing removed is still running, then:

    cd ~/neutrino && git pull && ./install.sh
EOF
