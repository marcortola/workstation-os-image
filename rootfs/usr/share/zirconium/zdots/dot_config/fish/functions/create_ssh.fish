function ssh --description 'SSH with a portable TERM so minimal remote hosts render correctly'
    # config.fish auto-starts tmux, so interactive shells export
    # TERM=tmux-256color. SSH sends only that name, never the terminfo db, so
    # hosts lacking the entry (Synology, busybox, old boxes) get broken
    # backspace and vim's E558. Downgrade to a near-universal entry for the
    # remote session only; the local terminal keeps tmux-256color. scp, rsync
    # and git invoke the ssh binary directly and bypass this wrapper.
    #
    # `set -lx` is scoped to its enclosing block, so ssh must run inside the
    # `if` for the override to reach the child; hoisting it out would silently
    # stop downgrading.
    if string match -qr '^(tmux|screen)' -- "$TERM"
        set -lx TERM xterm-256color
        command ssh $argv
    else
        command ssh $argv
    end
end
