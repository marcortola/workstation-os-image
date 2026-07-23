# Navigation
alias ..="cd .."
alias ...="cd ../.."
alias cdp="cd ~/projects"

# ls/eza
alias ls="eza"
alias ll="eza -l --icons"
alias la="eza -la --icons"
alias lt="eza --tree --level=2"

# Fuzzy file finder with syntax-highlighted preview
alias ff="fzf --preview 'bat --style=numbers --color=always {}'"

# General
alias grep="grep --color=auto"

# Git
alias gaa="git add -A"
alias gc="git commit"
alias gs="git status -sb"
alias gf="git fetch --all -p"
alias gps="git push"
alias gpsf="git push --force"
alias gpl="git pull --rebase --autostash"
alias gb="git branch"
alias gco="git checkout"
alias glog="git log --oneline --graph --decorate -20"
alias gdiff="git diff --stat"

# Docker
alias dc="docker compose"
alias dps="docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'"
alias dlog="docker compose logs -f --tail=100"

# Container UI
alias dtop="lazydocker"

# Coding agents and projects
# Claude alias credits to Arnau Vendrell
alias cc="claude"
alias cco="claude --model opus"
alias ccs="claude --model sonnet"
alias ccf="claude --model fable"
alias oc="opencode"
alias wjust='just --justfile "$HOME/projects/personal/workstation-os-image/justfile" --working-directory "$HOME/projects/personal/workstation-os-image"'
