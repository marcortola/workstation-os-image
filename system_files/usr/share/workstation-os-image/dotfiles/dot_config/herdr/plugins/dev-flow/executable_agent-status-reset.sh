#!/usr/bin/env bash
# Drop the per-pane status memory of the server that just went away.
#
# agent-freshness.sh decides a turn has finished from a transition -- `working`
# remembered, then `idle` reported -- and the remembered half is written by a
# server that no longer exists. herdr restores public pane ids verbatim from
# session.json, so a machine shut down mid-turn would otherwise come back with
# the pane still remembered as working and stamp a finish for a turn that never
# ended.
#
# It runs from `[[startup]]`, listed first so it precedes the other startup
# commands. Whether herdr can deliver a `pane.agent_status_changed` before its
# startup commands run is not established here; if one lands first it costs a
# single false stamp, which now shows only as a just-finished mark that ages out
# in AGENT_FRESH_SECONDS rather than affecting what a layout resumes.
#
# It clears a reading, never writes a stamp, so the single recency clock in
# agent-finished.sh keeps its one pair of writers.
set -euo pipefail

plugin_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=agent-finished.sh
# Resolved at run time from the deployed plugin directory, which is not this
# path in the repository.
# shellcheck disable=SC1091
. "$plugin_dir/agent-finished.sh"

agent_status_forget_all
