#!/usr/bin/env bash
# Close a herdr workspace and, when it holds a linked worktree, offer to delete
# the checkout from disk -- and the branch with it, but only when the branch is
# already in its base.
#
# Shared by the two popups that end this way -- close-workspace.sh
# (prefix+shift+x) and worktree-ship.sh (prefix+shift+m) -- which had grown two
# implementations of "is this a worktree", two prompts, and two different
# dirty-tree behaviours.
#
# Two things it was taught the hard way, and neither is optional:
#
#   * A rootful container writes into the checkout as root -- vendor/, var/cache,
#     .phpunit.result.cache -- and git can neither see that (all of it gitignored)
#     nor delete it. `git worktree remove` then fails part way through, having
#     already deleted the admin dir: "there's no going back from here" is git's
#     own comment on doing that unconditionally. What is left is a directory git
#     no longer knows about, so the obvious retry answers "is not a working
#     tree" and can never succeed. Six of those had piled up before it was
#     found. Hence the foreign-owner probe BEFORE the removal, and `sudo rm -rf`
#     plus a prune rather than a `--force` aimed at the wrong refusal.
#   * The branch goes only on a `merged` verdict from merge-state.sh, behind one
#     answer that covers the local branch and the one on origin together. They
#     were two answers, with origin gated on a merged PR rather than the merge
#     itself; what that produced was remote branches whose checkout and local
#     branch were both already gone, invisible to this popup ever after and left
#     for a sweep to find. A branch deleted here is deleted in both places or in
#     neither. Anything short of `merged` keeps it and prints both commands:
#     weighing an unmerged branch needs a judgement this popup does not have,
#     which is what `/worktree-remove` is for.
#
# Usage: checkout-remove.sh <workspace-id> [--close-plain]
#   --close-plain  close a workspace that is NOT a linked worktree. Without it
#                  such a workspace is left alone, which is what shipping wants:
#                  merging from the main repo must not close the main repo.
set -euo pipefail

plugin_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=merge-state.sh
. "$plugin_dir/merge-state.sh"

herdr_cli() {
    "${HERDR_BIN_PATH:-herdr}" "$@"
}

trap 'exit 0' INT TERM

workspace=${1:-}
close_plain=${2:-}
[ -n "$workspace" ] || exit 0

# Every prompt here defaults to no: the window can be closed, the popup can die,
# and a read that returns nothing must never be read as consent.
ask() {
    local answer
    printf '%s' "$1"
    read -r answer </dev/tty || return 1
    case $answer in
        y | Y | yes) return 0 ;;
        *) return 1 ;;
    esac
}

# $HOME is /home/marc while every real path is /var/home/marc, so the guard in
# remove_as_root has to compare resolved paths or it refuses every checkout.
home=$(realpath -- "$HOME" 2>/dev/null || printf '%s' "$HOME")

# The paths git cannot delete, because another user owns them. One traversal
# answers both questions the display asks: how many, and under which top-level
# entries.
foreign_paths() {
    find "$1" -mindepth 1 ! -uid "$(id -u)" -printf '%P\n' 2>/dev/null || true
}

# `sudo rm -rf` is the only irreversible thing this script runs, so the path is
# proved to be a checkout before root ever sees it: still a directory, resolved,
# under $HOME, not the repository itself, and sitting directly inside a
# `*__worktrees` parent -- the layout every checkout here is created with.
# Anything else prints the command instead of running it.
#
# Returns 0 removed, 1 could not, 2 declined.
remove_as_root() {
    local dir=$1 repo=$2 resolved parent
    resolved=$(realpath -- "$dir" 2>/dev/null || true)
    parent=$(dirname -- "${resolved:-/}")
    if [ -z "$resolved" ] || [ ! -d "$resolved" ] ||
        [ "$resolved" = "$home" ] || [ "$resolved" = "$repo" ] ||
        [ "${resolved#"$home"/}" = "$resolved" ] ||
        [ "${parent%__worktrees}" = "$parent" ]; then
        printf '\nrefusing to remove %s as root:\n' "$dir"
        printf 'it is not a checkout inside a __worktrees directory.\n'
        printf 'if that is wrong, do it by hand:\n  sudo rm -rf %s\n' "$dir"
        return 1
    fi
    printf '\nthis needs root, and sudo will ask for your password:\n'
    printf '  sudo rm -rf %s\n\n' "$resolved"
    ask 'run it? [y/N] ' || return 2
    printf '\n'
    if ! sudo rm -rf -- "$resolved"; then
        printf '\nsudo could not remove it. the command above is the whole fix;\n'
        printf 'run it from a normal shell.\n'
        return 1
    fi
    # The registration outlives the directory when git deleted the admin dir on
    # its way out of a failed removal, and it does not when we got here first.
    # Prune settles both without having to know which.
    if [ -n "$repo" ] && git -C "$repo" rev-parse --git-dir >/dev/null 2>&1; then
        git -C "$repo" worktree prune
    fi
    printf 'removed %s\n' "$resolved"
}

# Declining is not a failure, so it must not exit non-zero -- the callers' popups
# read that as "failed" and say so. But by the time this runs the branch may
# already be gone, and a popup that closes on its own would take that news with
# it, so a decline that left something behind waits to be read.
remove_or_exit() {
    local status=0
    remove_as_root "$1" "$2" || status=$?
    case $status in
        0) return 0 ;;
        2)
            printf '\nkept: %s\n' "$1"
            if [ "${delete_branch:-no}" = yes ]; then
                printf 'the branch is already deleted; the sha above recreates it'
                if [ "${delete_remote:-no}" = yes ]; then
                    printf ', and a push puts it back on origin'
                fi
                printf '.\n'
            fi
            printf '\npress enter to close '
            read -r _ </dev/tty || true
            exit 0
            ;;
        *) exit 1 ;;
    esac
}

info=$(herdr_cli workspace get "$workspace" |
    jq -r '[((.result.workspace.worktree.is_linked_worktree // false) | tostring),
            (.result.workspace.worktree.checkout_path // ""),
            (.result.workspace.worktree.repo_root // ""),
            (.result.workspace.label // "")] | @tsv')
linked=$(printf '%s' "$info" | cut -f1)
checkout=$(printf '%s' "$info" | cut -f2)
repo=$(printf '%s' "$info" | cut -f3)
label=$(printf '%s' "$info" | cut -f4)

if [ "$linked" != "true" ] || [ -z "$checkout" ]; then
    # The state a failed removal leaves behind: git dropped the registration, the
    # directory survived, and herdr reports no worktree at all. It is recognised
    # by the layout the create popup pins -- <repo>__worktrees/<slug> -- and
    # never by guessing, because what follows is rm -rf as root.
    orphan=${checkout:-${HERDR_ACTIVE_PANE_CWD:-}}
    orphan_parent=$(dirname -- "${orphan:-/}")
    if [ -n "$orphan" ] && [ -d "$orphan" ] &&
        [ "${orphan_parent%__worktrees}" != "$orphan_parent" ] &&
        ! git -C "$orphan" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        printf '\nleftovers: %s\n' "$orphan"
        printf 'git does not list this as a worktree any more, so a removal here\n'
        printf 'failed part way and left the directory behind.\n'
        printf 'any branch it held is untouched.\n\n'
        ask 'delete this directory from disk? [y/N] ' || exit 0
        remove_or_exit "$orphan" "${orphan_parent%__worktrees}"
        herdr_cli workspace close "$workspace" >/dev/null
        exit 0
    fi
    if [ "$close_plain" = "--close-plain" ]; then
        herdr_cli workspace close "$workspace" >/dev/null
    fi
    exit 0
fi

# Everything that has to be read while the checkout still exists. The merge
# check reaches the network, so it runs behind the local probes rather than in
# front of them.
merge_answer=$(mktemp)
branch=$(git -C "$checkout" symbolic-ref --quiet --short HEAD 2>/dev/null || true)
if [ -n "$branch" ] && [ -n "$repo" ]; then
    merge_state "$repo" "$branch" >"$merge_answer" 2>/dev/null &
fi
pending=$(git -C "$checkout" status --porcelain 2>/dev/null || true)
foreign=$(foreign_paths "$checkout")
wait

verdict=unknown
base=
unmerged=unknown
pr_number=-
pr_state=-
remote=no
if [ -s "$merge_answer" ]; then
    IFS=$'\t' read -r verdict base unmerged pr_number pr_state remote \
        <"$merge_answer" || true
fi
rm -f "$merge_answer"

printf '\nworktree: %s\n' "$label"
printf 'checkout: %s\n' "$checkout"
if [ -n "$branch" ]; then
    printf 'branch:   %s\n' "$branch"
    case $verdict in
        merged) printf '          merged into %s' "$base" ;;
        unmerged) printf '          NOT merged: %s commit(s) not in %s' "$unmerged" "$base" ;;
        *) printf '          merge state unknown, so the branch is kept' ;;
    esac
    if [ "$pr_number" != - ]; then
        printf ' (PR #%s %s)\n' "$pr_number" "$pr_state"
    else
        printf '\n'
    fi
    if [ "$remote" = yes ]; then
        printf '          origin still has it\n'
    fi
fi
if [ -n "$foreign" ]; then
    printf 'root-owned: %s (%s file(s))\n' \
        "$(printf '%s\n' "$foreign" | cut -d/ -f1 | sort -u | head -5 | paste -sd' ' -)" \
        "$(printf '%s\n' "$foreign" | grep -c .)"
    printf '            written by a rootful container. git can neither see nor\n'
    printf '            delete them, so removing this checkout needs sudo.\n'
fi
printf '\n'

# Answers first, actions after. `herdr worktree remove` closes the workspace
# itself, and a prompt asked after that runs in a popup whose window may already
# be gone -- which is why nothing past this block reads the tty again, except
# the one sudo prompt that cannot be moved earlier.
force=
if [ -z "$pending" ]; then
    ask 'delete this checkout from disk? [y/N] ' || exit 0
else
    printf 'UNCOMMITTED WORK:\n%s\n\n' "$(printf '%s\n' "$pending" | head -15)"
    ask 'this work is committed nowhere. delete the checkout? [y/N] ' || exit 0

    # Two answers, not one. The first agreed to remove a checkout; this one
    # agrees to lose what is inside it, which is the part that cannot be undone.
    printf '\n'
    ask 'FORCE: discard the work listed above? [y/N] ' || exit 0
    force=--force
fi

# One answer for the whole branch. The prompt names both places when origin has
# it, because that is what the keystroke does -- the display above has already
# said `origin still has it`, and an answer whose scope is wider than the
# question it was asked is the one thing this popup must never do.
delete_branch=no
delete_remote=no
if [ -n "$branch" ] && [ "$verdict" = merged ]; then
    printf '\n'
    if [ "$remote" = yes ]; then
        prompt="delete branch $branch, local and on origin? it is already in $base [y/N] "
    else
        prompt="delete branch $branch too? it is already in $base [y/N] "
    fi
    if ask "$prompt"; then
        delete_branch=yes
        if [ "$remote" = yes ]; then
            delete_remote=yes
        fi
    fi
elif [ -n "$branch" ]; then
    printf '\nbranch %s is kept. delete it yourself with:\n' "$branch"
    printf '  git -C %s branch -D %s\n' "$repo" "$branch"
    if [ "$remote" = yes ]; then
        printf '  git -C %s push origin --delete %s\n' "$repo" "$branch"
    fi
fi

# The branch goes first, and the checkout is detached to let it: a branch cannot
# be deleted while a worktree has it checked out, and the removal that would
# free it may take this popup's window with it. Detaching writes no files --
# HEAD already points at that commit -- and `branch -D` prints the sha it
# deleted, which is the whole recovery if the removal below then fails.
if [ "$delete_branch" = yes ]; then
    printf '\n'
    if ! (git -C "$checkout" checkout --detach --quiet && git -C "$repo" branch -D "$branch"); then
        printf 'could not delete the branch; it is still there.\n'
        delete_branch=no
    fi
fi

# Also before the removal, and for the same reason: this reaches the network and
# must not be racing a workspace close. A failure here is reported and does not
# stop the rest -- the checkout still has to go.
if [ "$delete_remote" = yes ]; then
    if ! git -C "$repo" push origin --delete "$branch"; then
        printf '\norigin/%s was not deleted; the branch is still on the remote.\n' "$branch"
    fi
fi

if [ -n "$foreign" ]; then
    remove_or_exit "$checkout" "$repo"
    herdr_cli workspace close "$workspace" >/dev/null
    exit 0
fi

err=$(mktemp)
# shellcheck disable=SC2086 # $force is one optional flag, never a path
if herdr_cli worktree remove --workspace "$workspace" $force >/dev/null 2>"$err"; then
    rm -f "$err"
    exit 0
fi
printf '\ngit refused to remove the checkout:\n'
sed 's/^/  /' "$err"
rm -f "$err"
if [ "$delete_branch" = yes ]; then
    printf '\nthe branch was deleted before this; the sha above recreates it'
    if [ "$delete_remote" = yes ]; then
        printf ', and a push puts it back on origin'
    fi
    printf '.\n'
fi

# Two different refusals reach here, and they need opposite answers. git may
# still see something the status probe could not -- a modified submodule, say --
# and --force is what removes that. Or another user owns files inside, in which
# case git has already dropped the admin dir on its way out and no git command
# can finish the job at all.
if [ -d "$checkout" ] && [ -z "$force" ] && [ -z "$(foreign_paths "$checkout")" ]; then
    printf '\ngit status showed nothing, so this is state the probe cannot see.\n\n'
    ask 'FORCE: remove it anyway, losing that state? [y/N] ' || exit 0
    err=$(mktemp)
    if herdr_cli worktree remove --workspace "$workspace" --force >/dev/null 2>"$err"; then
        rm -f "$err"
        exit 0
    fi
    printf '\nstill refused:\n'
    sed 's/^/  /' "$err"
    rm -f "$err"
fi

if [ ! -d "$checkout" ]; then
    # git took the tree and failed at something after it. The workspace pointing
    # at a path that no longer exists is the state this whole script exists to
    # avoid leaving behind.
    if [ -n "$repo" ]; then
        git -C "$repo" worktree prune
    fi
    herdr_cli workspace close "$workspace" >/dev/null
    exit 0
fi
printf '\nthe checkout is still on disk and git has dropped its registration.\n'
remove_or_exit "$checkout" "$repo"
herdr_cli workspace close "$workspace" >/dev/null
