function gd --description 'Remove the current git worktree and its branch, returning to the main worktree'
    if not git rev-parse --is-inside-work-tree >/dev/null 2>&1
        echo "gd: not inside a git repository" >&2
        return 1
    end
    set -l here (git rev-parse --show-toplevel)
    set -l main (git worktree list --porcelain | string replace -rf '^worktree ' '' | head -n1)
    if test "$here" = "$main"
        echo "gd: refusing to remove the main worktree" >&2
        return 1
    end
    set -l branch (git rev-parse --abbrev-ref HEAD)
    read -l -P "Remove worktree $here and branch $branch? [y/N] " reply
    if not string match -qir '^y' -- $reply
        echo "gd: aborted" >&2
        return 1
    end
    cd $main
    # When herdr opened the checkout it owns the workspace too, so ask it first
    # and the workspace goes away with the directory. herdr never deletes
    # branches, so that stays our job on either path.
    set -l workspace
    if command -q herdr
        set workspace (herdr worktree list --cwd $main 2>/dev/null |
            jq -r --arg b $branch '.result.worktrees[]? | select(.branch == $b) | .open_workspace_id // empty')
    end
    if test -n "$workspace"
        herdr worktree remove --workspace $workspace --force >/dev/null; or return
    else
        git worktree remove --force $here; or return
    end
    if test "$branch" != HEAD
        git branch -D $branch
    end
end
