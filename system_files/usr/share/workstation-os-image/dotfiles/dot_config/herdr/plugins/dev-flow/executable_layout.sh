#!/usr/bin/env bash
set -euo pipefail

herdr_cli() {
  "${HERDR_BIN_PATH:-herdr}" "$@"
}

target_workspace() {
  if [ -n "${1:-}" ]; then
    printf '%s\n' "$1"
    return 0
  fi
  if [ -n "${HERDR_WORKSPACE_ID:-}" ]; then
    printf '%s\n' "$HERDR_WORKSPACE_ID"
    return 0
  fi
  printf '%s' "${HERDR_PLUGIN_CONTEXT_JSON:-}" | jq -r '.workspace.workspace_id // empty'
}

first_tab_of() {
  herdr_cli tab list --workspace "$1" | jq -r '[.result.tabs[].tab_id] | first // empty'
}

root_pane_of_tab() {
  herdr_cli pane list --workspace "$1" | jq -r --arg tab "$2" '[.result.panes[] | select(.tab_id == $tab) | .pane_id] | first // empty'
}

pane_cwd() {
  herdr_cli pane get "$1" | jq -r '.result.pane.cwd // empty'
}

pane_is_free() {
  herdr_cli pane process-info --pane "$1" |
    jq -e -r '[.result.process_info.foreground_processes[]?.argv0] | all(test("^(zsh|bash|sh|fish|nu)$"))' >/dev/null 2>&1
}

create_tab_running() {
  local workspace=$1 label=$2 cwd=$3 command=${4:-} pane
  pane=$(herdr_cli tab create --workspace "$workspace" --label "$label" --cwd "$cwd" --no-focus |
    jq -r '.result.root_pane.pane_id // empty')
  if [ -n "$command" ] && [ -n "$pane" ]; then
    herdr_cli pane run "$pane" "$command" >/dev/null
  fi
}

workspace=$(target_workspace "${1:-}")
if [ -z "$workspace" ]; then
  echo "no workspace in context" >&2
  exit 1
fi

# `dev nvim` runs Neovim inside the project's Dev Container so LSP and parsers
# see the project's real dependencies; it exits 1 with a message when the tree
# has no .devcontainer, so pick the editor command per project rather than
# leaving that tab showing an error.
editor_command() {
  local dir=$1 probe=$dir
  local root
  root=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null || true)
  while :; do
    if [ -f "$probe/.devcontainer/devcontainer.json" ] || [ -f "$probe/.devcontainer.json" ]; then
      printf 'dev nvim\n'
      return 0
    fi
    [ "$probe" = "${root:-/}" ] && break
    [ "$probe" = / ] && break
    probe=$(dirname "$probe")
  done
  printf 'nvim\n'
}

main_tab=$(first_tab_of "$workspace")
main_pane=$(root_pane_of_tab "$workspace" "$main_tab")
cwd=${2:-$(pane_cwd "$main_pane")}

herdr_cli tab rename "$main_tab" main >/dev/null
if pane_is_free "$main_pane"; then
  herdr_cli pane run "$main_pane" claude >/dev/null
fi

create_tab_running "$workspace" nvim "$cwd" "$(editor_command "$cwd")"
create_tab_running "$workspace" term "$cwd"
