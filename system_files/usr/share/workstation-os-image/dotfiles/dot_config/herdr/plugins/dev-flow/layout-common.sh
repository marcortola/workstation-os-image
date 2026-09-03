#!/usr/bin/env bash
# Everything the two dev layouts share.
#
# There are two, and either can be applied on top of the other. layout.sh builds
# the default three tabs -- main running the agent, plus nvim and term.
# layout-split.sh builds the single `dev` tab that pins main to a third of the
# width and stacks the editor over the terminal in the rest. layout-toggle.sh is
# the one key both answer to; it reads which is applied and runs the other.
# Switching moves the live panes rather than recreating them, so the agent keeps
# its conversation and Neovim keeps its unsaved buffers.
#
# Two rules hold every lookup here together, and both were learned from a
# workspace that had drifted:
#
#   * Ask for a LABEL, never for a position. `first_tab_of` was how both layouts
#     found the agent, and a workspace whose agent pane had exited answered with
#     the editor's tab instead -- which was then renamed `main`, given a second
#     Neovim beside it, and left with no agent at all.
#   * A label is not unique. herdr accepts two tabs called `nvim` and every
#     lookup takes the first match, so one duplicate is permanent: the orphan
#     shadows the tab actually being worked in, and nothing here ever closed a
#     tab. layout_tab_for_label is the tie-break, and the builders refuse to add
#     to the pile.
#
# `layout.apply` is the socket method that looks made for this job and is not:
# it replaces the tab it is handed. A request naming an existing `tab_id` and an
# existing `pane_id` came back with a new tab holding new panes, and the old tab
# and its panes were gone -- the `pane_id` was ignored, not adopted. Applying a
# layout that way would kill the agent every time. `pane split` and `pane move`
# are the calls that preserve a process, so both layouts are built from those
# and `layout.apply` is used by neither.
#
# Sourced, not run. Callers: layout.sh, layout-split.sh, layout-toggle.sh,
# focus-tab.sh.

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

# Every tab of that label, in tab-bar order, because there can be more than one.
tabs_by_label() {
  herdr_cli tab list --workspace "$1" |
    jq -r --arg label "$2" '.result.tabs[] | select(.label == $label) | .tab_id'
}

# The one tab of that label to act on, and empty when there is none.
#
# With duplicates present, taking the first match reuses whichever tab the
# duplication happened to leave in front -- an orphan -- and strands the pane
# being worked in, so the next run duplicates again. A tab whose pane is running
# something is the one in use; when none of them is, the first is as good as any.
layout_tab_for_label() {
  local workspace=$1 label=$2 candidates tab pane first=

  candidates=$(tabs_by_label "$workspace" "$label")
  [ -n "$candidates" ] || return 0

  while IFS= read -r tab; do
    [ -n "$tab" ] || continue
    if [ -z "$first" ]; then
      first=$tab
    fi
    pane=$(first_pane_of_tab "$workspace" "$tab")
    if [ -n "$pane" ] && ! pane_is_free "$pane"; then
      printf '%s\n' "$tab"
      return 0
    fi
  done <<<"$candidates"

  printf '%s\n' "$first"
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

# The pane id alone, for a caller that does not need the tab.
workspace_pane_by_label() {
  herdr_cli pane list --workspace "$1" |
    jq -r --arg label "$2" '[.result.panes[] | select(.label == $label) | .pane_id] | first // empty'
}

# A labelled pane anywhere in the workspace, as `<tab id> <pane id>`.
labelled_pane_of() {
  herdr_cli pane list --workspace "$1" |
    jq -r --arg label "$2" \
      '[.result.panes[] | select(.label == $label) | "\(.tab_id) \(.pane_id)"] | first // empty'
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

# The tab the agent lives in, and empty when the workspace has lost it.
#
# Both layouts mark it: the default one names the TAB `main`, the split one
# names the PANE `main` inside the tab it calls `dev`. A workspace carrying
# neither mark has never been laid out, and there the first tab IS the agent's,
# because it is the tab the layout is about to be built around.
agent_tab_of() {
  local workspace=$1 located tab

  located=$(labelled_pane_of "$workspace" main)
  if [ -n "$located" ]; then
    printf '%s\n' "${located%% *}"
    return 0
  fi

  tab=$(layout_tab_for_label "$workspace" main)
  if [ -n "$tab" ]; then
    printf '%s\n' "$tab"
    return 0
  fi

  # Marks of a layout, but no agent among them: answer empty, so the caller
  # builds the agent a tab instead of renaming the editor's.
  #
  # Both sets of marks are asked for. The default layout's are tabs called
  # `nvim` and `term`; the split layout's are PANES of those names, in a tab
  # called `dev`. Asking only about tabs missed the split layout entirely, and a
  # split workspace whose agent pane had exited fell through to the first tab --
  # which is the `dev` tab, whose first pane is the editor.
  if [ -n "$(layout_tab_for_label "$workspace" nvim)" ] ||
    [ -n "$(layout_tab_for_label "$workspace" term)" ] ||
    [ -n "$(workspace_pane_by_label "$workspace" nvim)" ] ||
    [ -n "$(workspace_pane_by_label "$workspace" term)" ]; then
    return 0
  fi

  first_tab_of "$workspace"
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

# Any pane's cwd, for a tab that has to be built when no agent pane is left to
# ask. Every pane of a workspace is in the same checkout, so any of them answers.
workspace_cwd() {
  herdr_cli pane list --workspace "$1" | jq -r '[.result.panes[].cwd] | map(select(. != null)) | first // empty'
}

# Drop a tab's zoom before moving panes in or out of it. A zoomed tab refuses
# every `pane move`, and refuses it as a success, so the refusal used to reach
# the caller as an adoption. Zoom is view state and the layout keys are entitled
# to drop it; a half-applied layout is not something they are entitled to leave.
# The pane names the tab, and asking to unzoom one that is not zoomed is a
# no-op.
tab_unzoom() {
  [ -n "${1:-}" ] || return 0
  herdr_cli pane zoom --pane "$1" --off >/dev/null 2>&1 || true
}

# `pane move` answers a refusal with a SUCCESS response: `changed` is false and
# `reason` is `same_tab` or `zoomed_tab`, while `pane` -- required on every
# answer -- still reports the pane's unchanged tab. Reading the tab id from
# there made a zoomed pane rename the tab everything was still sitting in.
# `created_tab` is the field that stays null unless a tab was really made.
# The tab is born with its name: `--label` on the move is what herdr offers, and
# it leaves no window in which a tab exists under a number that a lookup could
# find first.
pane_move_new_tab() {
  local response tab
  response=$(herdr_cli pane move "$1" --new-tab --label "$2" 2>/dev/null) || return 1
  tab=$(printf '%s' "$response" | jq -r '.result.move_result.created_tab.tab_id // empty')
  [ -n "$tab" ] || return 1
  printf '%s\n' "$tab"
}

# The same refusal, moving into a tab that already exists. `changed` is the only
# field that says whether anything happened. `--tab` is not accepted without a
# `--split`, so the direction and ratio are not optional; `--target-pane` is,
# and without it herdr picks the pane to split.
pane_move_into_tab() {
  local pane=$1 tab=$2 direction=$3 ratio=$4 target=${5:-} response
  local -a target_arg=()
  if [ -n "$target" ]; then
    target_arg=(--target-pane "$target")
  fi
  response=$(herdr_cli pane move "$pane" --tab "$tab" "${target_arg[@]}" \
    --split "$direction" --ratio "$ratio" 2>/dev/null) || return 1
  printf '%s' "$response" | jq -e '.result.move_result.changed == true' >/dev/null 2>&1
}

# Take the name off a tab the layout no longer owns.
#
# A tab the user had split further does not close itself when the layout moves
# its first pane out, and it kept the label while the pane it named had left. On
# the way back the layout would then find a tab called `nvim` holding a shell,
# reuse it, and leave the editor to be found by nothing -- or build a second one
# beside it. herdr has no null label, so this is the empty string, which the
# tab bar shows as the tab's number and no lookup here matches.
tab_clear_label() {
  herdr_cli tab rename "$1" "" >/dev/null 2>&1 || true
}

# Build the agent a tab of its own, as `<tab id> <pane id>`.
create_agent_tab() {
  herdr_cli tab create --workspace "$1" --label main --cwd "$2" --no-focus |
    jq -r 'select(.result.tab.tab_id and .result.root_pane.pane_id) |
      "\(.result.tab.tab_id) \(.result.root_pane.pane_id)"'
}

# Where a layout starts from: the agent's tab, its pane, and the directory to
# work in, as `<tab id> <pane id> <cwd>`. Empty when the workspace holds no pane
# at all to read a directory from.
#
# The caller's own second argument wins for the directory: worktree-create.sh
# and workstation-dev both know the checkout before any of these panes exist.
#
# A workspace that has lost the agent's tab -- the agent quit, then the shell
# exited, so herdr closed the pane and the tab with it -- gets a new one here.
# Both layouts used to take the first tab instead, which handed the agent's slot
# to Neovim and started a second editor beside it.
layout_anchor() {
  local workspace=$1 explicit=${2:-} tab pane cwd

  tab=$(agent_tab_of "$workspace")
  pane=
  if [ -n "$tab" ]; then
    pane=$(main_pane_of_tab "$workspace" "$tab")
  fi

  cwd=$explicit
  if [ -z "$cwd" ] && [ -n "$pane" ]; then
    cwd=$(pane_cwd "$pane")
  fi
  if [ -z "$cwd" ]; then
    cwd=$(workspace_cwd "$workspace")
  fi
  [ -n "$cwd" ] || return 1

  if [ -z "$pane" ]; then
    read -r tab pane <<<"$(create_agent_tab "$workspace" "$cwd")"
    [ -n "$pane" ] || return 1
  fi

  printf '%s %s %s\n' "$tab" "$pane" "$cwd"
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

# A checkout that has ever finished a turn reopens with `claude --continue`;
# one that has not starts clean, because there is nothing to continue and
# `--continue` would fail the pane into a bare shell.
#
# The stamp is read as a fact, not as a clock: no age window closes a
# conversation. herdr restores the exact conversation on its own at server
# start with no age limit of its own, so a window here would only make the two
# disagree after a reboot -- and a conversation is finished when the checkout
# is removed, which is a deliberate act with its own popup.
claude_command() {
  if agent_finished_age "$(agent_checkout_key "$1")" >/dev/null; then
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
