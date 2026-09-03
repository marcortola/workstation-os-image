#!/usr/bin/env bash
# The single clock for "when did an agent last finish work in this checkout".
#
# herdr reports agent state but no time: `agent list` carries `state_change_seq`,
# a counter, and nothing else. Every recency question this workstation asks --
# is that space newly finished, has it gone stale, should the editor resume the
# conversation -- therefore reads one stamp per checkout, written by
# agent-freshness.sh from the pane.agent_status_changed event.
#
# Keyed by checkout path, never by workspace id. A workspace id dies when the
# space is closed and the checkout outlives it, which is exactly the case the
# expiry window exists for.
#
# Sourced, not run. Callers: agent-freshness.sh writes; spaces.sh reads, and so
# does layout-common.sh's claude_command, which is how both layouts decide
# whether to resume the conversation. Do not add a second recency source;
# extend this one.

AGENT_FINISHED_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/workstation/agent-finished"

# The status each pane was last seen in. herdr sends the new status and not the
# old one, and a finish is a transition rather than a state: a turn that ends
# while you are watching it goes working -> idle and never passes through done.
AGENT_STATUS_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/workstation/agent-status"

# A space that finished inside AGENT_FRESH_SECONDS is marked as just finished.
# One that finished longer ago than AGENT_EXPIRED_SECONDS is expired: the space
# picker hides it, and reopening it starts a clean conversation instead of
# resuming the old one.
AGENT_FRESH_SECONDS=600
AGENT_EXPIRED_SECONDS=43200

# A checkout parked on background work is not stamped until that work ends, and
# a task whose command can never exit would hold it there forever -- the mark
# would never fire at all, which is worse than firing early. Past this the
# checkout is treated as unparked once anyway. The re-stamp resets the age, so
# this nags hourly rather than latching, and it reads the existing stamp rather
# than starting a clock of its own.
AGENT_PARKED_NAG_SECONDS=3600

# The checkout path as git itself spells it, so a stamp written from a pane cwd
# and a row built from `git worktree list` agree on one key.
agent_checkout_key() {
    git -C "$1" rev-parse --path-format=absolute --show-toplevel 2>/dev/null ||
        printf '%s\n' "$1"
}

agent_status_file() {
    printf '%s/%s\n' "$AGENT_STATUS_DIR" "$(printf '%s' "$1" | tr -c 'A-Za-z0-9_.-' '_')"
}

agent_status_previous() {
    local file
    file=$(agent_status_file "$1")
    [ -f "$file" ] || return 0
    cat "$file" 2>/dev/null || true
}

agent_status_remember() {
    local file
    file=$(agent_status_file "$1")
    mkdir -p "$AGENT_STATUS_DIR"
    printf '%s\n' "$2" >"$file"
    # Pane ids do not outlive a herdr server for long.
    find "$AGENT_STATUS_DIR" -type f -mtime +30 -delete 2>/dev/null || true
}

agent_finished_file() {
    printf '%s/%s\n' "$AGENT_FINISHED_DIR" "$(printf '%s' "$1" | sha1sum | cut -d' ' -f1)"
}

# The stamp carries its own key so the whole directory can be read back as a
# map; a filename hash cannot be inverted.
agent_finished_write() {
    local file
    file=$(agent_finished_file "$1")
    mkdir -p "$AGENT_FINISHED_DIR"
    printf '%s\t%s\n' "$(date +%s)" "$1" >"$file"
    # A checkout deleted months ago would otherwise keep its stamp forever.
    find "$AGENT_FINISHED_DIR" -type f -mtime +30 -delete 2>/dev/null || true
}

# Unix seconds of the last finish in this checkout, or nothing when none was seen.
agent_finished_at() {
    local file
    file=$(agent_finished_file "$1")
    [ -f "$file" ] || return 0
    cut -f1 "$file" 2>/dev/null || true
}

# Seconds since that finish. Non-zero when there is no stamp, so a caller can
# tell "never finished here" from "finished long ago".
agent_finished_age() {
    local at
    at=$(agent_finished_at "$1")
    [ -n "$at" ] || return 1
    printf '%s\n' "$(($(date +%s) - at))"
}

# Every stamp as {"<checkout>": <unix seconds>}, for one jq pass over the rows.
agent_finished_map() {
    { cat "$AGENT_FINISHED_DIR"/* 2>/dev/null || true; } |
        jq -Rn '[inputs | split("\t") | select(length == 2) | {key: .[1], value: (.[0] | tonumber)}] | from_entries'
}
