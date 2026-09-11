#
# ~/.bashrc
#

# If not running interactively, don't do anything
[[ $- != *i* ]] && return

alias ls='ls --color=auto'
alias grep='grep --color=auto'

eval "$(starship init bash)"

# unihermes edits
alias nbash='nvim .bashrc && source ~/.bashrc'
alias ff='clear && fastfetch'

