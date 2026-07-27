function ga --description 'Add a git worktree for BRANCH at ../<repo>--<branch> and cd into it'
    set -l branch $argv[1]
    if test -z "$branch"
        echo "usage: ga <branch>" >&2
        return 1
    end
    if not git rev-parse --is-inside-work-tree >/dev/null 2>&1
        echo "ga: not inside a git repository" >&2
        return 1
    end
    # The first worktree listed is the main one; base the sibling dir on it.
    set -l main (git worktree list --porcelain | string replace -rf '^worktree ' '' | head -n1)
    set -l dir (path dirname $main)/(path basename $main)--$branch
    if test -e $dir
        cd $dir
        return
    end
    if git show-ref --quiet --verify refs/heads/$branch
        git worktree add $dir $branch; or return
    else
        git worktree add $dir -b $branch; or return
    end
    cd $dir
    # Populate the new worktree with .worktreeinclude-listed gitignored files
    # (.env, .idea, ...) from the main worktree, matching the workmux/IDE flows.
    if type -q workstation-worktree-sync
        workstation-worktree-sync
    end
end
