#!/usr/bin/env bash
# The second dev layout: one `dev` tab, the agent pinned to a third of the width
# on the left, the editor stacked over the terminal in the rest.
#
#   +--------+------------------+
#   |        |       nvim       |
#   |  main  +------------------+
#   |  33%   |  term (a sliver) |
#   +--------+------------------+
#
# The default layout is still layout.sh's three tabs; this one is applied on
# demand from prefix+shift+v, and prefix+shift+n takes it apart again. Neither
# direction recreates anything: panes are moved, so the agent keeps its
# conversation and Neovim keeps its unsaved buffers. See layout-common.sh for
# why `layout.apply` is not used to build either layout.
set -euo pipefail

plugin_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=layout-common.sh
. "$plugin_dir/layout-common.sh"

workspace=$(target_workspace "${1:-}")
if [ -z "$workspace" ]; then
  echo "no workspace in context" >&2
  exit 1
fi

# Whichever tab is first holds the agent: `main` coming from the default layout,
# `dev` coming from this one applied already.
dev_tab=$(first_tab_of "$workspace")
main_pane=$(main_pane_of_tab "$workspace" "$dev_tab")
cwd=${2:-$(pane_cwd "$main_pane")}

# Take the pane out of the tab the default layout gave it, rather than opening a
# second editor beside the one already running. The tab closes itself once its
# last pane leaves. A tab the user has split further keeps its remaining panes
# and its label; only the first pane moves.
adopt_tab_pane() {
  local label=$1 target=$2 direction=$3 ratio=$4 source_tab pane
  source_tab=$(tab_by_label "$workspace" "$label")
  if [ -z "$source_tab" ] || [ "$source_tab" = "$dev_tab" ]; then
    return 1
  fi
  pane=$(first_pane_of_tab "$workspace" "$source_tab")
  if [ -z "$pane" ]; then
    return 1
  fi
  herdr_cli pane move "$pane" --tab "$dev_tab" --target-pane "$target" \
    --split "$direction" --ratio "$ratio" >/dev/null
  printf '%s\n' "$pane"
}

new_pane() {
  herdr_cli pane split "$1" --direction "$2" --ratio "$3" --cwd "$cwd" --no-focus |
    jq -r '.result.pane.pane_id // empty'
}

# Panes already labelled here mean the layout is applied; the run below then only
# re-asserts the ratios and the focus. Each half is resolved on its own so a
# half-built tab is completed rather than duplicated.
nvim_pane=$(pane_by_label "$workspace" "$dev_tab" nvim)
term_pane=$(pane_by_label "$workspace" "$dev_tab" term)
nvim_created=0

if [ -z "$nvim_pane" ]; then
  if ! nvim_pane=$(adopt_tab_pane nvim "$main_pane" right "$LAYOUT_MAIN_RATIO"); then
    nvim_pane=$(new_pane "$main_pane" right "$LAYOUT_MAIN_RATIO")
    nvim_created=1
  fi
fi

if [ -z "$term_pane" ]; then
  if ! term_pane=$(adopt_tab_pane term "$nvim_pane" down "$LAYOUT_EDITOR_RATIO"); then
    term_pane=$(new_pane "$nvim_pane" down "$LAYOUT_EDITOR_RATIO")
  fi
fi

# The tab must not be called main, nvim or term: focus-tab.sh answers prefix+m,
# prefix+n and prefix+t by looking for a tab of that label first, and would stop
# at this one instead of reaching the pane inside it.
herdr_cli tab rename "$dev_tab" dev >/dev/null
pane_rename "$main_pane" main
pane_rename "$nvim_pane" nvim
pane_rename "$term_pane" term

# A brand-new pane's shell is too young to answer the process probe reliably, so
# it is started from the branch that made it rather than by asking. An adopted
# one is old enough to ask, and asking is what puts the editor back in a pane
# the last session quit out of.
if pane_is_free "$main_pane"; then
  herdr_cli pane run "$main_pane" "$(claude_command "$cwd")" >/dev/null
fi
if [ "$nvim_created" = 1 ] || pane_is_free "$nvim_pane"; then
  herdr_cli pane run "$nvim_pane" "$(editor_command "$cwd")" >/dev/null
fi

# Re-assert the geometry every run: the resting state is the editor holding the
# column, and main's third is restored even after the resize keys moved it.
main_split=$(layout_parent_split "$dev_tab" "$main_pane")
if [ -n "$main_split" ] &&
  [ "$(printf '%s' "$main_split" | jq -r '.direction')" = "right" ] &&
  [ "$(printf '%s' "$main_split" | jq -r '.child')" = "first" ]; then
  layout_set_ratio "$dev_tab" "$(printf '%s' "$main_split" | jq -c '.path')" "$LAYOUT_MAIN_RATIO"
fi
layout_grow_pane "$dev_tab" "$nvim_pane"
pane_focus "$nvim_pane"
