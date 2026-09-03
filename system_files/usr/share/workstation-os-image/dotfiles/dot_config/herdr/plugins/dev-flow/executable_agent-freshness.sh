#!/usr/bin/env bash
# pane.agent_status_changed hook: record when an agent finished, and badge the
# space for as long as that stays recent.
#
# Two surfaces, two mechanisms, on purpose. The sidebar badge is a herdr
# workspace token with a TTL, so herdr expires it and nothing has to sweep it.
# The stamp file outlives the workspace, which the token cannot, and is what
# the space picker and the dev layout read.
set -euo pipefail

plugin_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=agent-finished.sh
. "$plugin_dir/agent-finished.sh"

# See lib.sh: a turn that ends leaving background work running is not a finish,
# and only a per-agent probe can tell the two apart. Absent the image half,
# nothing is ever parked and this hook behaves as it did before.
# shellcheck source=../../../../../../../libexec/workstation-agent-probes/lib.sh
if [ -r /usr/libexec/workstation-agent-probes/lib.sh ]; then
    . /usr/libexec/workstation-agent-probes/lib.sh
else
    agent_parked_probe() { printf '[]\n'; }
fi

# Is this pane parked -- turn over, background work alive? Asked of the live
# pane list rather than the event, which carries a status and nothing else.
pane_is_parked() {
    [ -n "$1" ] || return 1
    herdr_cli pane list 2>/dev/null |
        jq -c '.result.panes' 2>/dev/null |
        { read -r panes || exit 1; agent_parked_probe "$panes"; } |
        jq -e --arg p "$1" 'IN(.[]; $p)' >/dev/null 2>&1
}

herdr_cli() {
    "${HERDR_BIN_PATH:-herdr}" "$@"
}

event=${HERDR_PLUGIN_EVENT_JSON:-}
[ -n "$event" ] || exit 0

# herdr's plugin envelope nests the payload under `data`; read both shapes so a
# direct invocation with the event body alone still resolves.
IFS=$'\t' read -r status pane workspace < <(
    printf '%s' "$event" |
        jq -r '(.data // .) | [(.agent_status // ""), (.pane_id // ""), (.workspace_id // "")] | @tsv'
)

[ -n "$workspace" ] || exit 0

previous=$(agent_status_previous "$pane")
if [ -n "$pane" ]; then
    agent_status_remember "$pane" "$status"
fi

# The badge is only for the two states that also mean "and you have not looked
# yet". herdr derives `done` itself and drops it back to `idle` the moment the
# pane is viewed, so a badge on `idle` would outlive the thing it announces.
case $status in
    done | blocked)
        # A turn that ended with background work still running has not finished,
        # whatever herdr calls the pane. The sweep in spaces.sh sets this token
        # when that work actually exits.
        if ! pane_is_parked "$pane"; then
            herdr_cli workspace report-metadata "$workspace" \
                --source dev.flow --token fresh=new --ttl-ms "$((AGENT_FRESH_SECONDS * 1000))" >/dev/null 2>&1 || true
        fi
        ;;
    working)
        herdr_cli workspace report-metadata "$workspace" --source dev.flow --clear-token fresh >/dev/null 2>&1 || true
        ;;
    idle)
        # done -> idle is herdr saying the pane was viewed, which is the
        # dismissal this clear exists for. Any other idle is a re-detection, and
        # must not wipe a token the sweep has just set.
        if [ "$previous" = "done" ]; then
            herdr_cli workspace report-metadata "$workspace" --source dev.flow --clear-token fresh >/dev/null 2>&1 || true
        fi
        ;;
esac

# The stamp is a wider question than the badge: did work end here, viewed or
# not. `done` and `blocked` always answer yes. `idle` answers yes only as the
# far side of a working transition -- a turn that ended while you watched it
# never reaches `done` -- and no otherwise, or every re-detection of a pane
# that has been sitting at its prompt for a week would reset the clock.
finished=no
case $status in
    done | blocked) finished=yes ;;
    idle)
        if [ "$previous" = working ]; then
            finished=yes
        fi
        ;;
esac
# The stamp is written on time and never suppressed, even while parked:
# layout-common.sh reads a missing stamp as "start clean", so a deferred stamp
# silently downgrades the next dev layout from resuming the conversation to
# starting a new one. The sweep re-stamps when the work ends; it does not wait
# for this one.
[ "$finished" = yes ] || exit 0

# The workspace knows its checkout when herdr created the worktree; a hand-linked
# space only knows where its pane is standing.
checkout=$(herdr_cli workspace get "$workspace" |
    jq -r '.result.workspace.worktree.checkout_path // empty')
if [ -z "$checkout" ] && [ -n "$pane" ]; then
    checkout=$(herdr_cli pane get "$pane" | jq -r '.result.pane.cwd // empty')
fi
[ -n "$checkout" ] || exit 0

agent_finished_write "$(agent_checkout_key "$checkout")"
