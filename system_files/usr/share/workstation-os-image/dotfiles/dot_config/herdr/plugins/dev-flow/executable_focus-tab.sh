#!/usr/bin/env bash
set -euo pipefail

herdr_cli() {
  "${HERDR_BIN_PATH:-herdr}" "$@"
}

label=$1

focused_workspace() {
  herdr_cli workspace list | jq -r '[.result.workspaces[] | select(.focused) | .workspace_id] | first // empty'
}

tab_by_label() {
  herdr_cli tab list --workspace "$1" |
    jq -r --arg label "$2" '[.result.tabs[] | select(.label == $label) | .tab_id] | first // empty'
}

workspace=${HERDR_ACTIVE_WORKSPACE_ID:-$(focused_workspace)}
if [ -z "$workspace" ]; then
  exit 0
fi

tab=$(tab_by_label "$workspace" "$label")
if [ -n "$tab" ]; then
  herdr_cli tab focus "$tab" >/dev/null
fi
