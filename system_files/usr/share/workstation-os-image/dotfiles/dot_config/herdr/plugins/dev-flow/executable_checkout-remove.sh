#!/usr/bin/env bash
# Close a herdr workspace and, when it holds a linked worktree, offer to delete
# the checkout from disk.
#
# Shared by the two popups that end this way -- close-workspace.sh
# (prefix+shift+x) and worktree-ship.sh (prefix+shift+m) -- which had grown two
# implementations of "is this a worktree", two prompts, and two different
# dirty-tree behaviours.
#
# It never deletes a branch. `/worktree-remove` owns that, because it is the one
# that checks whether the merge actually landed.
#
# Usage: checkout-remove.sh <workspace-id> [--close-plain]
#   --close-plain  close a workspace that is NOT a linked worktree. Without it
#                  such a workspace is left alone, which is what shipping wants:
#                  merging from the main repo must not close the main repo.
set -euo pipefail

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

info=$(herdr_cli workspace get "$workspace" |
    jq -r '[((.result.workspace.worktree.is_linked_worktree // false) | tostring),
            (.result.workspace.worktree.checkout_path // ""),
            (.result.workspace.label // "")] | @tsv')
linked=$(printf '%s' "$info" | cut -f1)
checkout=$(printf '%s' "$info" | cut -f2)
label=$(printf '%s' "$info" | cut -f3)

if [ "$linked" != "true" ] || [ -z "$checkout" ]; then
    if [ "$close_plain" = "--close-plain" ]; then
        herdr_cli workspace close "$workspace" >/dev/null
    fi
    exit 0
fi

printf '\nworktree: %s\n' "$label"
printf 'checkout: %s\n' "$checkout"
printf 'the branch is never deleted\n\n'

pending=$(git -C "$checkout" status --porcelain 2>/dev/null || true)

if [ -z "$pending" ]; then
    ask 'delete this checkout from disk? [y/N] ' || exit 0

    # No --force while the tree looks clean. If git disagrees with the status
    # probe there is something the probe cannot see, and that is the one case
    # worth stopping on rather than steamrollering.
    err=$(mktemp)
    if herdr_cli worktree remove --workspace "$workspace" >/dev/null 2>"$err"; then
        rm -f "$err"
        exit 0
    fi
    printf '\ngit refused to remove the checkout:\n'
    sed 's/^/  /' "$err"
    rm -f "$err"
    printf '\ngit status showed nothing, so this is state the probe cannot see.\n\n'
    ask 'FORCE: remove it anyway, losing that state? [y/N] ' || exit 0
else
    printf 'UNCOMMITTED WORK:\n%s\n\n' "$(printf '%s\n' "$pending" | head -15)"
    ask 'this work is committed nowhere. delete the checkout? [y/N] ' || exit 0

    # Two answers, not one. The first agreed to remove a checkout; this one
    # agrees to lose what is inside it, which is the part that cannot be undone.
    printf '\n'
    ask 'FORCE: discard the work listed above? [y/N] ' || exit 0
fi

herdr_cli worktree remove --workspace "$workspace" --force >/dev/null
