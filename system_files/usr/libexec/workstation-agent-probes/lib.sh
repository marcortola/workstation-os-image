#!/usr/bin/env bash
# The seam between "this agent is parked on background work" and the two
# surfaces that render it. Sourced, not run.
#
# herdr's agent_status answers one question -- is there a foreground turn -- and
# upstream settled deliberately in herdrdev/herdr#3468 that a background task the
# turn left running is not one, with a regression test guarding it. That is
# defensible for herdr and wrong here: a checkout whose agent is waiting on a
# twenty minute shell is not quiet, and stamping it finished sends you to it
# before it is done.
#
# No signal for this is agent agnostic. A process-tree predicate was measured
# and is false: herdr reports idle for the whole span of a foreground tool call,
# and a foreground tool call is a setsid session leader exactly like a
# background one, so the two are indistinguishable from outside. The seam is
# therefore agnostic and the answers are not -- one probe per agent, named after
# the label herdr reports in .agent, and an agent with no probe answers no and
# behaves exactly as it did before this existed.

AGENT_PARKED_FILE="${XDG_STATE_HOME:-$HOME/.local/state}/workstation/agent-parked"
AGENT_PROBE_DIR="${AGENT_PROBE_DIR:-/usr/libexec/workstation-agent-probes/probes}"


# Ask every agent that owns a pane whether any of them are parked. $1 is the
# `herdr pane list` panes array; the answer is a JSON array of pane ids.
#
# The probe contract, in full: a probe reads a JSON array of pane objects on
# stdin -- every pane whose .agent equals the probe's own filename -- and prints
# a JSON array of the pane ids that are parked. No arguments, no writes, no side
# effects. One fork per agent kind, not per pane.
#
# Every other outcome is read as "not parked": no probe, non-zero exit, timeout,
# output that is not an array of strings. A broken probe degrades this
# workstation to the behaviour it had before probes existed, which is the only
# failure mode worth having for a signal that rides an undocumented vendor file.
agent_parked_probe() {
    local panes=$1 agent subset out parked='[]'
    while IFS= read -r agent; do
        # The label is about to become a path component, so it is validated
        # rather than trusted: herdr reports whatever the manifest calls it.
        case $agent in
            '' | *[!a-z0-9_-]*) continue ;;
        esac
        [ -x "$AGENT_PROBE_DIR/$agent" ] || continue
        subset=$(printf '%s' "$panes" | jq -c --arg a "$agent" '[.[] | select(.agent == $a)]') || continue
        out=$(printf '%s' "$subset" | timeout 2 "$AGENT_PROBE_DIR/$agent" 2>/dev/null) || continue
        printf '%s' "$out" | jq -e 'type == "array" and all(type == "string")' >/dev/null 2>&1 || continue
        parked=$(jq -cn --argjson a "$parked" --argjson b "$out" '$a + $b | unique') || continue
    done < <(printf '%s' "$panes" | jq -r '[.[].agent // empty] | unique | .[]')
    printf '%s\n' "$parked"
}

# What was parked when this last ran, as `<pane id>\t<workspace id>\t<checkout>`
# lines. The unpark edge is the difference between this and the current answer,
# and it is the only thing that knows a background task has ended: no agent
# emits an event for it, which is why the sweep is a poll.
agent_parked_previous() {
    cat "$AGENT_PARKED_FILE" 2>/dev/null || true
}

agent_parked_write() {
    local dir
    dir=$(dirname "$AGENT_PARKED_FILE")
    mkdir -p "$dir"
    # Two readers poll this concurrently -- the picker every 2s, the bar widget
    # every 3s -- so the file is swapped rather than truncated in place. A torn
    # read would drop an unpark edge, which is a mark that never fires.
    printf '%s' "$1" >"$AGENT_PARKED_FILE.$$" && mv "$AGENT_PARKED_FILE.$$" "$AGENT_PARKED_FILE"
}
