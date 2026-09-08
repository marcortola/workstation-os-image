#!/usr/bin/env bash
# The single clock for "when did an agent last finish work in this checkout".
#
# herdr reports agent state but no time: `agent list` carries `state_change_seq`,
# a counter, and nothing else. Every recency question this workstation asks --
# is that space newly finished, has it gone stale, should the pane resume the
# conversation -- therefore reads one stamp per checkout and agent, written by
# agent-freshness.sh from the pane.agent_status_changed event.
#
# Keyed by checkout path, never by workspace id. A workspace id dies when the
# space is closed and the checkout outlives it, which is exactly the case the
# expiry window exists for.
#
# Keyed by AGENT as well, because a checkout now holds more than one. The stamp
# is what layout-common.sh's agent_command reads to decide whether there is a
# conversation to resume, and a resume flag passed with nothing to resume fails
# the pane into a bare shell. Keyed on the checkout alone, a codex finish
# answered that question for claude, in a checkout claude had never run in.
#
# Sourced, not run. Callers: agent-freshness.sh writes; spaces.sh reads and also
# writes through its parked sweep, and so does layout-common.sh's agent_command.
# Do not add a second recency source; extend this one.

AGENT_FINISHED_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/workstation/agent-finished"

# Stamps written before the key grew its agent half name a checkout and nothing
# else. They are read as claude's: claude is the only command either layout ever
# ran, so all but a hand-started agent's finishes were its. The wrong attribution
# it can still make -- a checkout where only a hand-started codex ever finished --
# is the behaviour those checkouts already had, and it lasts until that agent's
# next finish rather than for good.
AGENT_LEGACY_KIND=claude

# The status each pane was last seen in. herdr sends the new status and not the
# old one, and a finish is a transition rather than a state: a turn that ends
# while you are watching it goes working -> idle and never passes through done.
AGENT_STATUS_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/workstation/agent-status"

# A space that finished inside AGENT_FRESH_SECONDS is marked as just finished.
#
# There is deliberately no counterpart that expires a stamp. A checkout leaves
# the picker when it is removed, not when it goes quiet: the closed rows come
# from `git worktree list`, so the list is already bounded by what is on disk
# and prunes itself through the ship and close-workspace popups. An age window
# on top of that hid live checkouts nobody had asked to hide, and gave the
# reboot path two answers to one question -- herdr restores the exact
# conversation with no age limit, so a window here only disagreed with it.
AGENT_FRESH_SECONDS=600

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

# Every remembered status belongs to a server that is gone, so a new server
# starts without any. The file is a memory of a transition, not a fact about a
# pane: a finish is `working` followed by `idle`, and nothing else records the
# first half. session.json restores the public pane ids verbatim, so a machine
# shut down mid-turn would come back with the pane still remembered as
# `working`, and the first idle after the restore would be read as a turn that
# ended while the server was off -- stamping a finish that never happened and
# marking the space as just finished on the bar.
#
# This resets the existing clock rather than adding a second one: it removes a
# reading taken by a dead server, and writes no stamp of its own.
agent_status_forget_all() {
    [ -d "$AGENT_STATUS_DIR" ] || return 0
    find "$AGENT_STATUS_DIR" -type f -delete 2>/dev/null || true
}

# One file per checkout and agent. The tab separator is what keeps the two
# halves apart in the hash: without it a checkout ending in the agent's own name
# would collide with the checkout beside it.
agent_finished_file() {
    printf '%s/%s\n' "$AGENT_FINISHED_DIR" "$(printf '%s\t%s' "$1" "$2" | sha1sum | cut -d' ' -f1)"
}

# The stamp carries its own key so the whole directory can be read back as a
# map; a filename hash cannot be inverted.
agent_finished_write() {
    local file
    [ -n "${2:-}" ] || return 0
    file=$(agent_finished_file "$1" "$2")
    mkdir -p "$AGENT_FINISHED_DIR"
    printf '%s\t%s\t%s\n' "$(date +%s)" "$1" "$2" >"$file"
    # A checkout deleted months ago would otherwise keep its stamp forever.
    find "$AGENT_FINISHED_DIR" -type f -mtime +30 -delete 2>/dev/null || true
}

# Unix seconds of that agent's last finish in this checkout, or nothing when
# none was seen.
#
# A stamp written before the key grew its agent half is named after the checkout
# alone, so the per-agent name misses it. The legacy name is tried for the legacy
# kind and for nothing else, which is the same reading agent_finished_map gives
# those files -- and the two have to agree, or the picker marks a checkout as
# just finished while the layout starts the agent clean. It stops mattering at
# that agent's next finish, which writes the current name and takes precedence.
agent_finished_at() {
    local file
    [ -n "${2:-}" ] || return 0
    file=$(agent_finished_file "$1" "$2")
    if [ ! -f "$file" ] && [ "$2" = "$AGENT_LEGACY_KIND" ]; then
        file="$AGENT_FINISHED_DIR/$(printf '%s' "$1" | sha1sum | cut -d' ' -f1)"
    fi
    [ -f "$file" ] || return 0
    cut -f1 "$file" 2>/dev/null || true
}

# Seconds since that finish. Non-zero when there is no stamp, so a caller can
# tell "never finished here" from "finished long ago".
agent_finished_age() {
    local at
    at=$(agent_finished_at "$1" "${2:-}")
    [ -n "$at" ] || return 1
    printf '%s\n' "$(($(date +%s) - at))"
}

# Every stamp as {"<checkout>": {"<agent>": <unix seconds>}}, for one jq pass
# over the rows. Nested rather than flat on a joined key so a row that wants the
# whole checkout can take the newest of its agents without splitting keys again.
agent_finished_map() {
    { cat "$AGENT_FINISHED_DIR"/* 2>/dev/null || true; } |
        jq -Rn --arg legacy "$AGENT_LEGACY_KIND" '
            [ inputs
              | split("\t")
              | select(length >= 2)
              | {checkout: .[1], agent: (.[2] // $legacy), at: (.[0] | tonumber)} ]
            | group_by(.checkout)
            | map({ key: .[0].checkout,
                    value: (map({key: .agent, value: .at}) | from_entries) })
            | from_entries'
}
