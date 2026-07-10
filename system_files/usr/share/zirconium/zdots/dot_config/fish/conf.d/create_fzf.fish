if status is-interactive; and command -q fzf
    set -gx FZF_DEFAULT_OPTS "
        --color=bg+:#283457,bg:#1a1b26,spinner:#7dcfff,hl:#f7768e
        --color=fg:#a9b1d6,header:#f7768e,info:#bb9af7,pointer:#7dcfff
        --color=marker:#9ece6a,fg+:#c0caf5,prompt:#bb9af7,hl+:#f7768e
        --border=rounded --height=60% --layout=reverse
    "

    fzf --fish | source
end
