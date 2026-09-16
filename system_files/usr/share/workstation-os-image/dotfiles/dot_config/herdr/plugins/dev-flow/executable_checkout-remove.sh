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

# The parked-work seam, sourced the way spaces.sh and agent-freshness.sh source
# it: image payload rather than plugin, so a machine without the image half
# keeps the behaviour it had before probes existed instead of failing the popup
# at its first line.
# shellcheck source=../../../../../../../libexec/workstation-agent-probes/lib.sh
if [ -r /usr/libexec/workstation-agent-probes/lib.sh ]; then
    . /usr/libexec/workstation-agent-probes/lib.sh
else
    agent_parked_probe() { printf '[]\n'; }
fi

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

# What the spaces about to close are running, and which of it a close would
# interrupt.
#
# herdr kills every pane in a space it closes, and until this existed it did so
# unasked wherever the group prompt below did not apply: a repo space with no
# worktree spaces open under it took no answer at all, so one keystroke ended a
# turn in flight with nothing said. A close touches no file, branch or commit --
# the panes are the whole loss -- which is exactly why it was invisible.
#
# Three states mean something is in flight. `working` is a foreground turn,
# `blocked` is an agent waiting on an answer that dies with its pane, and
# `parked` is herdr's idle over background work the probe found still alive --
# the state herdr has no word for, and the only reason this reads a probe at
# all. `done` is deliberately not one of them: it is the normal state after
# every turn, and a question asked on every close is a question nobody reads.
AGENT_BUSY_STATES="working blocked parked"

agent_activity=
agent_busy_spaces=
agent_probe_failed=no

# One `pane list` read answers both halves: it carries `.agent` and
# `.agent_status` on every pane, and the parked probe takes that same blob.
#
# The probe, never spaces.sh's sweep. The sweep WRITES -- it stamps the recency
# clock and pushes the sidebar token -- and a popup that asks a question must not
# also record a turn as finished. One clock, two writers, and this is neither.
#
# A probe that could not answer is not a probe that said no, and for a close the
# two point opposite ways: the picker keeps its last answer, while this has to
# ask. So a failed probe makes every space that runs an agent busy and says why,
# rather than closing quietly over work it could not see.
read_agent_activity() {
    local panes parked
    panes=$(herdr_cli pane list 2>/dev/null | jq -c '.result.panes' 2>/dev/null) || return 0
    [ -n "$panes" ] || return 0
    if ! parked=$(agent_parked_probe "$panes"); then
        agent_probe_failed=yes
    fi
    printf '%s' "${parked:-}" | jq -e 'type == "array"' >/dev/null 2>&1 || parked='[]'

    agent_activity=$(printf '%s' "$panes" | jq -r --argjson parked "$parked" '
        .[]
        | select(.agent != null)
        | [ (.workspace_id // ""),
            .agent,
            (if (.pane_id | IN($parked[])) and ((.agent_status == "idle") or (.agent_status == "done"))
               then "parked"
               else (.agent_status // "unknown")
             end),
            (.terminal_title_stripped // "") ]
        | @tsv') || agent_activity=

    if [ "$agent_probe_failed" = yes ]; then
        agent_busy_spaces=$(printf '%s' "$agent_activity" | awk -F'\t' 'NF { print $1 }' | sort -u)
    else
        agent_busy_spaces=$(printf '%s' "$agent_activity" |
            awk -F'\t' -v busy=" $AGENT_BUSY_STATES " \
                'NF && index(busy, " " $3 " ") { print $1 }' | sort -u)
    fi
}

# The agents of one space, indented under whatever named it. Nothing for a space
# that runs none, so every caller can print it unconditionally.
agent_state_block() {
    local indent=$1 workspace=$2
    printf '%s' "$agent_activity" |
        awk -F'\t' -v ws="$workspace" -v indent="$indent" \
            '$1 == ws { printf "%s%s %s%s\n", indent, $2, $3, ($4 == "" ? "" : "  " $4) }'
}

# Is closing any of these spaces going to interrupt something?
agents_busy_in() {
    local workspace
    for workspace in "$@"; do
        [ -n "$workspace" ] || continue
        printf '%s\n' "$agent_busy_spaces" | grep -qxF "$workspace" && return 0
    done
    return 1
}

# What a close costs, worded once. The folded group answer and the delete paths
# print the same three sentences, because it is the same keystroke either way.
agent_interrupt_note() {
    if [ "$agent_probe_failed" = yes ]; then
        printf 'background work could not be checked -- the probe did not answer -- so\n'
        printf 'this cannot say whether anything above is still running.\n'
    fi
    printf 'closing takes their panes with them, and the turn ends where it is.\n'
    printf 'reopening the space is not the same as resuming it: the dev layout\n'
    printf 'resumes a conversation only where the checkout has finished a turn once.\n'
}

# The answer, for a path that has already displayed the agents. Asked FIRST
# wherever questions follow it: there is nothing to weigh about a tree or a
# branch while the work that would be interrupted is still running.
agent_answer_or_exit() {
    agents_busy_in "$@" || return 0
    agent_interrupt_note
    printf '\n'
    ask 'interrupt them? [y/N] ' || exit 0
}

# Rows and answer together, for a path that displays nothing else.
agent_guard() {
    local heading=$1 workspace
    shift
    agents_busy_in "$@" || return 0
    printf '\n%s\n' "$heading"
    for workspace in "$@"; do
        agent_state_block '  ' "$workspace"
    done
    printf '\n'
    agent_answer_or_exit "$@"
}

# Close the repo workspace, and say so when that takes its worktree spaces with
# it.
#
# herdr models a repo workspace and the worktree workspaces opened under it as
# one group, and closing the repo one closes the whole group. 0.8.2 did that
# silently -- one keystroke on the repo space closed every checkout's spaces and
# killed every pane in them, agents included, with nothing asked and nothing
# said, which is what was reported here. 0.9.0 refuses instead: `workspace
# close` answers `workspace_group_close_required` and leaves the group open
# unless the caller states the intent with `--group`. This is where that intent
# is formed, so the flag is never passed without the group having been named
# first.
#
# Nothing is deleted. This closes SPACES: every checkout, branch and uncommitted
# change stays exactly where it is, and reopening one from the prefix+s picker
# gives it its layout back. The prompt says so, because the popup that owns the
# other half of this script does delete checkouts and the two must not read
# alike.
close_repo_workspace() {
    local workspace=$1 repo=$2 label=$3 members count member_ws member_label member_path
    # The workspace id rides with each member so the agent rows can be hung
    # under the checkout they belong to, and so the busy test covers the whole
    # group rather than only the space in front of you.
    local -a spaces=("$workspace")
    members=
    if [ -n "$repo" ]; then
        members=$(herdr_cli workspace list |
            jq -r --arg repo "$repo" '
                .result.workspaces[]
                | select((.worktree.is_linked_worktree // false)
                         and (.worktree.repo_root // "") == $repo)
                | [.workspace_id, (.label // ""), (.worktree.checkout_path // "")] | @tsv')
    fi

    if [ -z "$members" ]; then
        # No group: this space closes, nothing else does, and nothing is
        # deleted -- so its own agents are the only thing that can be lost, and
        # the only thing worth an answer. A space whose agents are quiet still
        # closes on the one keystroke, which is what it always did.
        agent_guard "space: ${label:-$workspace}" "$workspace"
        herdr_cli workspace close "$workspace" >/dev/null
        return 0
    fi

    count=$(printf '%s\n' "$members" | grep -c .)
    printf '\nproject: %s\n' "${label:-$workspace}"
    agent_state_block '  ' "$workspace"
    printf 'herdr closes this space and its worktree spaces together, %s of them:\n' "$count"
    while IFS=$'\t' read -r member_ws member_label member_path; do
        [ -n "$member_ws$member_label$member_path" ] || continue
        printf '  %s\n' "${member_path:-$member_label}"
        agent_state_block '    ' "$member_ws"
        spaces+=("$member_ws")
    done <<<"$members"
    printf '\nnothing is deleted: every checkout, branch and uncommitted change stays.\n'
    # One keystroke, one answer: the agent state is folded into the question that
    # was already here rather than asked again behind it. A second prompt about
    # the same close reads as a second thing happening.
    if agents_busy_in "${spaces[@]}"; then
        agent_interrupt_note
    fi
    printf '\n'
    ask 'close them? [y/N] ' || exit 0
    herdr_cli workspace close "$workspace" --group >/dev/null
}

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

# Before any path asks anything, because every one of them ends in a close.
read_agent_activity

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
        agent_guard 'agents in this space:' "$workspace"
        ask 'delete this directory from disk? [y/N] ' || exit 0
        remove_or_exit "$orphan" "${orphan_parent%__worktrees}"
        herdr_cli workspace close "$workspace" >/dev/null
        exit 0
    fi
    if [ "$close_plain" = "--close-plain" ]; then
        close_repo_workspace "$workspace" "$repo" "$label"
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
agent_display=$(agent_state_block '  ' "$workspace")
if [ -n "$agent_display" ]; then
    printf 'agents:\n%s\n' "$agent_display"
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
#
# The agents go first of all. The display above has already named them, and the
# questions below are about a checkout and a branch -- neither worth weighing
# while the work that would be interrupted is still running.
agent_answer_or_exit "$workspace"

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
