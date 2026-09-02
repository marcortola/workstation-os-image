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

# `blocked` wants an answer and `done` wants a review; both are "this space is
# asking for you", which is the state the picker already collapses them into.
case $status in
    done | blocked) ;;
    *)
        herdr_cli workspace report-metadata "$workspace" --source dev.flow --clear-token fresh >/dev/null 2>&1 || true
        exit 0
        ;;
esac

# The workspace knows its checkout when herdr created the worktree; a hand-linked
# space only knows where its pane is standing.
checkout=$(herdr_cli workspace get "$workspace" |
    jq -r '.result.workspace.worktree.checkout_path // empty')
if [ -z "$checkout" ] && [ -n "$pane" ]; then
    checkout=$(herdr_cli pane get "$pane" | jq -r '.result.pane.cwd // empty')
fi
[ -n "$checkout" ] || exit 0

agent_finished_write "$(agent_checkout_key "$checkout")"

herdr_cli workspace report-metadata "$workspace" \
    --source dev.flow --token fresh=new --ttl-ms "$((AGENT_FRESH_SECONDS * 1000))" >/dev/null 2>&1 || true
