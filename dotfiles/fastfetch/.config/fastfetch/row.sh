# One boxed row for config.jsonc:  . row.sh LABEL [VALUE]
#
# Sourced, not run: fastfetch finds the terminal by walking up the process
# tree, and a shell of its own between the two fastfetch processes makes the
# Terminal row report "fastfetch".
#
# With no VALUE, LABEL is also the fastfetch module to ask. The nested call
# runs with `-c none` so it doesn't load config.jsonc again and recurse. The
# value is right-padded so the closing border lands in the same column on
# every row -- fastfetch can't pad a module to a fixed width on its own.
label=$1
if (( $# > 1 )); then
  v=$2
else
  v=$(fastfetch -c none -s "$label" --logo none --separator $'\x1f' 2>/dev/null)
  v=${v#*$'\x1f'}
fi
pad=$(( 66 - 5 - ${#label} - ${#v} )); (( pad < 0 )) && pad=0
printf '\033[38;2;122;122;122m%s\033[0m %s%*s \033[38;2;77;77;77m│\033[0m' "$label" "$v" "$pad" ''
