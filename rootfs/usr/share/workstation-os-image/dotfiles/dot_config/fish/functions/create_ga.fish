function ga --description 'Create or open a git worktree for BRANCH under ~/.herdr/worktrees and go there'
    set -l branch $argv[1]
    if test -z "$branch"
        echo "usage: ga <branch>" >&2
        return 1
    end
    if not git rev-parse --is-inside-work-tree >/dev/null 2>&1
        echo "ga: not inside a git repository" >&2
        return 1
    end
    # The first worktree listed is the main one; herdr keys its checkouts off
    # that repository name, and slugifies the branch by replacing / with -.
    set -l main (git worktree list --porcelain | string replace -rf '^worktree ' '' | head -n1)
    set -l dir $HOME/.herdr/worktrees/(path basename $main)/(string replace -a / - $branch)

    # Inside herdr, hand the whole job over: `worktree create` shells out to
    # `git worktree add`, so the post-checkout hook still copies the
    # .worktreeinclude files, and the checkout opens as its own workspace
    # grouped under the parent repository.
    if set -q HERDR_ENV; and command -q herdr
        if test -e $dir
            herdr worktree open --cwd $main --branch $branch --focus >/dev/null; or return
        else
            herdr worktree create --cwd $main --branch $branch --focus >/dev/null; or return
        end
        echo $dir
        return
    end

    # No herdr session (a plain terminal, an IDE, a script): plain git at the
    # same path, then cd into it.
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
    # Belt and braces for a repository whose post-checkout hook is not installed
    # yet; the script is a no-op when it has already run.
    if type -q workstation-worktree-sync
        workstation-worktree-sync
    end
end
