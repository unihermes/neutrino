#
# ~/.bashrc
#
# If not running interactively, don't do anything
[[ $- != *i* ]] && return

# Below the interactive guard on purpose: bash sources this file for some
# non-interactive shells too (notably `ssh host command`), and anything that
# writes to stdout there corrupts the stream -- scp and rsync fail with
# "protocol error" when a greeting turns up in the middle of their transfer.
fastfetch

alias ls='ls --color=auto'
alias grep='grep --color=auto'

eval "$(starship init bash)"

# unihermes edits
alias nbash='nvim .bashrc && source ~/.bashrc'
alias ff='clear && fastfetch'

