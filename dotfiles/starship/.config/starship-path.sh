#!/usr/bin/env bash
# Emits $PWD with each segment a step brighter than the last, for starship's
# custom.path module.
#
# This exists because starship's own `directory` module renders the whole
# path as one string with one style -- it has no per-segment styling, only
# repo-root-vs-not. A custom module is the only way to colour each segment,
# and starship passes raw ANSI from a custom module through unmodified.
#
# Every segment re-asserts the background rather than resetting: a bare
# \033[0m would clear the capsule's background mid-path and split the block
# in half. The single reset at the very end is deliberate.
set -uo pipefail

BG='48;2;36;36;36'          # overlay #242424, the capsule's ground
SEP='38;2;77;77;77'         # muted   #4d4d4d, the slashes
RAMP=(
  '38;2;77;77;77'           # muted   #4d4d4d
  '38;2;122;122;122'        # subtext #7a7a7a
  '38;2;194;194;194'        # text    #c2c2c2
)
LAST='1;38;2;235;235;235'   # bright  #ebebeb, bold -- where you actually are

p=${PWD/#"$HOME"/\~}

# Leading "/" on an absolute path would otherwise produce an empty first
# segment and a doubled separator.
lead=""
[[ $p == /* ]] && { lead="/"; p=${p#/}; }

IFS='/' read -ra parts <<< "$p"
n=${#parts[@]}

out=$'\033['"$BG"'m '          # open the block with its padding space

# At "/" the only thing to show IS the slash, so it takes the current-location
# style rather than the dim separator one.
if [[ -n $lead ]]; then
  if (( n == 0 )) || [[ -z ${parts[0]} ]]; then
    out+=$'\033['"$BG;$LAST"'m/'
  else
    out+=$'\033['"$BG;$SEP"'m/'
  fi
fi

for i in "${!parts[@]}"; do
  seg=${parts[$i]}
  [[ -z $seg ]] && continue
  if (( i == n - 1 )); then
    style=$LAST
  else
    idx=$(( i < ${#RAMP[@]} ? i : ${#RAMP[@]} - 1 ))
    style=${RAMP[$idx]}
  fi
  (( i > 0 )) && out+=$'\033['"$BG;$SEP"'m/'
  out+=$'\033['"$BG;$style"'m'"$seg"
done

out+=$'\033['"$BG"'m '         # trailing padding space, still on the block
printf '%s\033[0m' "$out"
