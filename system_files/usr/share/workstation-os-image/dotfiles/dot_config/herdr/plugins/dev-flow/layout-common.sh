#!/usr/bin/env bash
# Everything the two dev layouts share.
#
# There are two, and either can be applied on top of the other. layout.sh builds
# the default three tabs -- main running the agent, plus nvim and term.
# layout-split.sh builds the single `dev` tab that pins main to a third of the
# width and stacks the editor over the terminal in the rest. Switching between
# them moves the live panes rather than recreating them, so the agent keeps its
# conversation and Neovim keeps its unsaved buffers.
#
# `layout.apply` is the socket method that looks made for this job and is not:
# it replaces the tab it is handed. A request naming an existing `tab_id` and an
# existing `pane_id` came back with a new tab holding new panes, and the old tab
# and its panes were gone -- the `pane_id` was ignored, not adopted. Applying a
# layout that way would kill the agent every time. `pane split` and `pane move`
# are the calls that preserve a process, so both layouts are built from those
# and `layout.apply` is used by neither.
#
# Sourced, not run. Callers: layout.sh, layout-split.sh, focus-tab.sh.

# Resolved from this file rather than from the caller's $0, so a script can
# source it before working out anything else about itself.
layout_common_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=agent-finished.sh
. "$layout_common_dir/agent-finished.sh"

# A split's `ratio` is always the share of its first child, so all three numbers
# below describe the pane that comes first: the left column for the vertical
# split, the upper pane for the stacked one.
#
# LAYOUT_MAIN_RATIO is the width the agent keeps whichever pane you are working
# in; nothing toggles it. The other two are the two states of the stacked
# column -- the editor holding it, or the terminal holding it.
LAYOUT_MAIN_RATIO=0.33
LAYOUT_EDITOR_RATIO=0.85
LAYOUT_TERMINAL_RATIO=0.3

herdr_cli() {
  "${HERDR_BIN_PATH:-herdr}" "$@"
}

# The socket methods the CLI does not expose: `layout.export`,
# `layout.set_split_ratio` and `pane.focus`. `herdr pane focus` is the
# directional one and cannot take a pane id.
herdr_request() {
  printf '%s\n' "$1" | "$layout_common_dir/herdr-request.sh"
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
  # herdr's PluginInvocationContext is flat: `workspace_id`, `workspace_label`,
  # `tab_id`, and no nested `workspace` object -- unlike an API response, where
  # `.result.workspace.workspace_id` is right. Reading only the nested path made
  # this fallback resolve to nothing; it went unnoticed because an action is also
  # handed HERDR_WORKSPACE_ID, which the branch above takes first. Read both, so
  # an event hook reaching here still resolves.
  printf '%s' "${HERDR_PLUGIN_CONTEXT_JSON:-}" |
    jq -r '.workspace_id // .workspace.workspace_id // empty'
}

focused_workspace() {
  herdr_cli workspace list | jq -r '[.result.workspaces[] | select(.focused) | .workspace_id] | first // empty'
}

first_tab_of() {
  herdr_cli tab list --workspace "$1" | jq -r '[.result.tabs[].tab_id] | first // empty'
}

focused_tab_of() {
  herdr_cli tab list --workspace "$1" | jq -r '[.result.tabs[] | select(.focused) | .tab_id] | first // empty'
}

tab_by_label() {
  herdr_cli tab list --workspace "$1" |
    jq -r --arg label "$2" '[.result.tabs[] | select(.label == $label) | .tab_id] | first // empty'
}

first_pane_of_tab() {
  herdr_cli pane list --workspace "$1" | jq -r --arg tab "$2" '[.result.panes[] | select(.tab_id == $tab) | .pane_id] | first // empty'
}

# Panes carry a label of their own, set by `pane rename` and reported by both
# `pane list` and `layout.export`. The split layout names its three panes after
# the tabs the default layout would have given them, which is what lets
# focus-tab.sh answer the same key in either layout.
pane_by_label() {
  herdr_cli pane list --workspace "$1" |
    jq -r --arg tab "$2" --arg label "$3" \
      '[.result.panes[] | select(.tab_id == $tab and .label == $label) | .pane_id] | first // empty'
}

# The agent's pane, by label first and by position only as a fallback. The
# split layout labels all three, and `pane list` order is not a promise, so
# asking for the label is what keeps "run the agent here" pointed at the agent.
main_pane_of_tab() {
  local pane
  pane=$(pane_by_label "$1" "$2" main)
  if [ -z "$pane" ]; then
    pane=$(first_pane_of_tab "$1" "$2")
  fi
  printf '%s\n' "$pane"
}

pane_rename() {
  herdr_cli pane rename "$1" "$2" >/dev/null
}

pane_focus() {
  herdr_request "$(jq -cn --arg pane "$1" '{id: "focus", method: "pane.focus", params: {pane_id: $pane}}')" >/dev/null
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

# `dev nvim` runs Neovim inside the project's Dev Container so LSP and parsers
# see the project's real dependencies; it exits 1 with a message when the tree
# has no .devcontainer, so pick the editor command per project rather than
# leaving that pane showing an error.
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

layout_export_tab() {
  herdr_request "$(jq -cn --arg tab "$1" '{id: "export", method: "layout.export", params: {tab_id: $tab}}')"
}

# The split a pane hangs directly off, as {path, direction, child}. `path` is the
# route from the root as a list of booleans -- false for the first child, true
# for the second -- which is the address layout.set_split_ratio takes, and the
# same convention equalize-panes.sh builds.
layout_parent_split() {
  layout_export_tab "$1" | jq -c --arg pane "$2" '
    def parent($path):
      if .type != "split" then empty
      else
        (if (.first | .type == "pane" and .pane_id == $pane)
           then {path: $path, direction: .direction, child: "first"} else empty end),
        (if (.second | .type == "pane" and .pane_id == $pane)
           then {path: $path, direction: .direction, child: "second"} else empty end),
        (.first | parent($path + [false])),
        (.second | parent($path + [true]))
      end;
    [.result.layout.root | parent([])] | first // empty'
}

# Address a split by the route layout.set_split_ratio takes.
layout_set_ratio() {
  herdr_request "$(jq -cn --arg tab "$1" --argjson path "$2" --argjson ratio "$3" \
    '{id: "ratio", method: "layout.set_split_ratio", params: {tab_id: $tab, path: $path, ratio: $ratio}}')" >/dev/null
}

# Give a pane the larger share of the column it is stacked in.
#
# Only a `down` split is touched. The vertical split is what pins the agent to
# LAYOUT_MAIN_RATIO, and it has to keep that width whichever pane you move to,
# so moving to main focuses it and resizes nothing.
layout_grow_pane() {
  local tab=$1 pane=$2 parent ratio
  parent=$(layout_parent_split "$tab" "$pane")
  [ -n "$parent" ] || return 0
  [ "$(printf '%s' "$parent" | jq -r '.direction')" = "down" ] || return 0

  if [ "$(printf '%s' "$parent" | jq -r '.child')" = "first" ]; then
    ratio=$LAYOUT_EDITOR_RATIO
  else
    ratio=$LAYOUT_TERMINAL_RATIO
  fi

  layout_set_ratio "$tab" "$(printf '%s' "$parent" | jq -c '.path')" "$ratio"
}
