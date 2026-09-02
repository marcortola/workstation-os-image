#!/usr/bin/env bash
set -euo pipefail

herdr_cli() {
  "${HERDR_BIN_PATH:-herdr}" "$@"
}

plugin_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=agent-finished.sh
. "$plugin_dir/agent-finished.sh"

target_workspace() {
  if [ -n "${1:-}" ]; then
    printf '%s\n' "$1"
    return 0
  fi
  if [ -n "${HERDR_WORKSPACE_ID:-}" ]; then
    printf '%s\n' "$HERDR_WORKSPACE_ID"
    return 0
  fi
  # herdr's PluginInvocationContext is flat: `workspace_id`, `workspace_label`,
  # `tab_id`, and no nested `workspace` object -- unlike an API response, where
  # `.result.workspace.workspace_id` is right. Reading only the nested path made
  # this fallback resolve to nothing; it went unnoticed because an action is also
  # handed HERDR_WORKSPACE_ID, which the branch above takes first. Read both, so
  # an event hook reaching here still resolves.
  printf '%s' "${HERDR_PLUGIN_CONTEXT_JSON:-}" |
    jq -r '.workspace_id // .workspace.workspace_id // empty'
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

# Whether the pane is idle, asked as "is the shell itself the foreground process
# group". Matching process names instead is what the upstream probe did through a
# field herdr 0.8.2 does not return (`argv0`, so `test` hit null and jq aborted
# and every pane read as busy), and repairing that to `name` only traded one
# failure for a flakier one: fish runs `direnv hook fish` while it starts, and a
# probe landing in that window saw a non-shell name and skipped the agent in
# roughly half of cold picks. The transient is a child of the shell's own process
# group, so this comparison rides through it, and it needs no list of shell or
# helper names to stay correct.
pane_is_free() {
  herdr_cli pane process-info --pane "$1" |
    jq -e '.result.process_info | .foreground_process_group_id == .shell_pid' >/dev/null 2>&1
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
  # Two `local` assignments, not one: bash expands every word before the
  # builtin runs, so `local dir=$1 probe=$dir` reads the caller's unset `dir`
  # and `set -u` aborts the function.
  local dir=$1
  local probe=$dir
  local root
  root=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null || true)
  while :; do
    if [ -f "$probe/.devcontainer/devcontainer.json" ] || [ -f "$probe/.devcontainer.json" ]; then
      printf 'dev nvim\n'
      return 0
    fi
    # -ef, not =: /home is a symlink to /var/home, so the caller's path and the
    # physical one git reports never compare equal as strings and the walk would
    # run past the repository into ~ and /.
    [ "$probe" -ef "${root:-/}" ] && break
    [ "$probe" = / ] && break
    probe=$(dirname "$probe")
  done
  printf 'nvim\n'
}

main_tab=$(first_tab_of "$workspace")
main_pane=$(root_pane_of_tab "$workspace" "$main_tab")
cwd=${2:-$(pane_cwd "$main_pane")}

# Resume the conversation only while it is still the same stretch of work: a
# checkout whose last agent finish is inside AGENT_EXPIRED_SECONDS reopens with
# `claude --continue`, an expired one starts clean. Without a stamp there is
# nothing to continue and `--continue` would fail the pane into a bare shell,
# so no stamp means a clean start too.
claude_command() {
  local age
  age=$(agent_finished_age "$(agent_checkout_key "$1")") || {
    printf 'claude\n'
    return 0
  }
  if [ "$age" -lt "$AGENT_EXPIRED_SECONDS" ]; then
    printf 'claude --continue\n'
  else
    printf 'claude\n'
  fi
}

herdr_cli tab rename "$main_tab" main >/dev/null
if pane_is_free "$main_pane"; then
  herdr_cli pane run "$main_pane" "$(claude_command "$cwd")" >/dev/null
fi

create_tab_running "$workspace" nvim "$cwd" "$(editor_command "$cwd")"
create_tab_running "$workspace" term "$cwd"
