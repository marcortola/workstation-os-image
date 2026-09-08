#!/usr/bin/env bash
# prefix+alt+a popup: give this checkout another agent.
#
# One tab per agent, labelled with the agent's own name, which is the whole
# record: herdr persists a tab's custom_name, so the set of agents in a checkout
# survives a server restart, the tab bar says which is which, and every lookup
# in layout-common.sh matches the label exactly. Nothing here writes state of its
# own.
#
# The tab is built and started the way both layouts build and start theirs --
# `tab create` then `pane run` with agent_command -- so a checkout reached from
# here and one reached from the layout resume the same way. `herdr agent start`
# would be a second mechanism for the same thing, and it does not know about the
# per-agent stamp that decides whether there is a conversation to resume.
#
# One slot per kind. A kind already in the workspace is not offered: the label is
# the key, and two tabs sharing it would make every lookup take whichever came
# first, permanently.
set -euo pipefail

plugin_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=layout-common.sh
. "$plugin_dir/layout-common.sh"

# The popup dies with the script, so a failure has to hold the window open long
# enough to be read. 130 is the interrupt path and closes silently.
on_exit() {
    local status=$?
    if [ "$status" -ne 0 ] && [ "$status" -ne 130 ]; then
        printf '\nfailed (exit %s). press enter to close\n' "$status"
        read -r _ </dev/tty || true
    fi
}
trap on_exit EXIT
trap 'exit 0' INT TERM

workspace=${HERDR_ACTIVE_WORKSPACE_ID:-${HERDR_WORKSPACE_ID:-$(focused_workspace)}}
if [ -z "$workspace" ]; then
    printf 'no workspace in context\n' >&2
    exit 1
fi

# Where the new agent starts. The workspace knows its checkout when herdr made
# the worktree; otherwise any pane of it is standing in the right place, which is
# the same fallback layout_anchor takes.
cwd=$(herdr_cli workspace get "$workspace" |
    jq -r '.result.workspace.worktree.checkout_path // empty')
if [ -z "$cwd" ]; then
    cwd=${HERDR_ACTIVE_PANE_CWD:-}
fi
if [ -z "$cwd" ]; then
    cwd=$(workspace_cwd "$workspace")
fi
if [ -z "$cwd" ]; then
    printf 'no directory to start an agent in\n' >&2
    exit 1
fi

# A kind already here, and a kind this machine has no binary for, are both
# nothing to offer. The second matters because a tab would otherwise be created
# and immediately fall back to a shell, leaving a slot named after an agent that
# is not installed for the layouts to keep restarting.
# The slot LABEL is the kind, except for a tab still called `main`, which names
# no agent at all. Resolving each slot the way the layouts do is what stops this
# offering a second claude beside the one already running in a workspace laid out
# before the rename.
present=
while IFS=$'\t' read -r slot_tab slot_pane slot_label; do
    [ -n "$slot_tab" ] || continue
    [ -n "$slot_pane" ] || slot_pane=$(first_pane_of_tab "$workspace" "$slot_tab")
    present="$present$(agent_kind_of "$slot_label" "$slot_pane")"$'\n'
done < <(agent_slots_of "$workspace")
present=${present%$'\n'}

available=()
# shellcheck disable=SC2086 # AGENT_KINDS is a space-separated list, split on purpose
for kind in $AGENT_KINDS; do
    if printf '%s\n' "$present" | grep -qxF "$kind"; then
        continue
    fi
    # The kind is also the binary's name for all three, which is why there is no
    # table here mapping one to the other.
    command -v "$kind" >/dev/null 2>&1 || continue
    available+=("$kind")
done

if [ "${#available[@]}" -eq 0 ]; then
    printf 'this checkout already runs every agent it can: %s\n' "$(printf '%s' "$present" | tr '\n' ' ')"
    printf 'press enter to close\n'
    read -r _ </dev/tty || true
    exit 0
fi

printf 'checkout: %s\n' "$cwd"
if [ -n "$present" ]; then
    printf 'running:  %s\n' "$(printf '%s' "$present" | tr '\n' ' ')"
fi
printf '\n'

index=0
for kind in "${available[@]}"; do
    index=$((index + 1))
    printf '  %s) %s\n' "$index" "$kind"
done
printf '\nenter nothing (or q) to cancel\n'
read -r -p 'agent: ' answer </dev/tty || exit 0

case ${answer:-} in
    '' | q | quit) exit 0 ;;
esac

# Answer by number or by name, because a three-line list is quicker to type than
# to count.
chosen=
case $answer in
    *[!0-9]* | '') ;;
    *)
        if [ "$answer" -ge 1 ] && [ "$answer" -le "${#available[@]}" ]; then
            chosen=${available[$((answer - 1))]}
        fi
        ;;
esac
if [ -z "$chosen" ]; then
    for kind in "${available[@]}"; do
        [ "$kind" = "$answer" ] || continue
        chosen=$kind
        break
    done
fi

if [ -z "$chosen" ]; then
    printf 'no such agent, nothing started\n' >&2
    exit 1
fi

agent_cmd=$(agent_command "$chosen" "$cwd") || {
    printf 'no command for agent %s\n' "$chosen" >&2
    exit 1
}

read -r tab pane <<<"$(create_agent_tab "$workspace" "$cwd" "$chosen")"
if [ -z "$pane" ]; then
    printf 'herdr created no pane for the %s tab\n' "$chosen" >&2
    exit 1
fi

herdr_cli pane run "$pane" "$agent_cmd" >/dev/null
herdr_cli tab focus "$tab" >/dev/null
