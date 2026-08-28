function ssh --description 'SSH with a portable TERM so minimal remote hosts render correctly'
    # foot advertises TERM=foot and ships that terminfo entry only locally. SSH
    # sends the name, never the terminfo db, so hosts lacking the entry
    # (Synology, busybox, old boxes) get broken backspace and vim's E558.
    # Downgrade to a near-universal entry for the remote session only; the local
    # terminal keeps its own TERM. Inside a herdr pane TERM is already
    # xterm-256color, so this is inert there. scp, rsync and git invoke the ssh
    # binary directly and bypass this wrapper.
    #
    # `set -lx` is scoped to its enclosing block, so ssh must run inside the
    # `if` for the override to reach the child; hoisting it out would silently
    # stop downgrading.
    if string match -qr '^(foot|tmux|screen)' -- "$TERM"
        set -lx TERM xterm-256color
        command ssh $argv
    else
        command ssh $argv
    end
end
