#!/usr/bin/env bash
# The default dev layout: three tabs -- main running the agent, plus nvim and
# term. Applied for a herdr-created worktree, from the project picker, and on
# demand from prefix+shift+n, which is also what takes the split layout
# (layout-split.sh, prefix+shift+v) apart again.
set -euo pipefail

plugin_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=layout-common.sh
. "$plugin_dir/layout-common.sh"

create_tab_running() {
  local workspace=$1 label=$2 cwd=$3 command=${4:-} pane
  pane=$(herdr_cli tab create --workspace "$workspace" --label "$label" --cwd "$cwd" --no-focus |
    jq -r '.result.root_pane.pane_id // empty')
  if [ -n "$command" ] && [ -n "$pane" ]; then
    herdr_cli pane run "$pane" "$command" >/dev/null
  fi
}

# Give a pane of the split layout a tab of its own again. `pane move --new-tab`
# carries the process across, so this undoes prefix+shift+v without restarting
# Neovim over its unsaved buffers, and the new tab arrives numbered rather than
# named. The pane label goes with it: it exists so focus-tab.sh can find the
# pane inside the split tab, and here the tab label answers instead.
tab_out() {
  local pane=$1 label=$2 tab
  tab=$(herdr_cli pane move "$pane" --new-tab | jq -r '.result.move_result.pane.tab_id // empty')
  if [ -n "$tab" ]; then
    herdr_cli tab rename "$tab" "$label" >/dev/null
  fi
  pane_rename "$pane" ""
}

workspace=$(target_workspace "${1:-}")
if [ -z "$workspace" ]; then
  echo "no workspace in context" >&2
  exit 1
fi

main_tab=$(first_tab_of "$workspace")
main_pane=$(main_pane_of_tab "$workspace" "$main_tab")
cwd=${2:-$(pane_cwd "$main_pane")}

herdr_cli tab rename "$main_tab" main >/dev/null
if pane_is_free "$main_pane"; then
  herdr_cli pane run "$main_pane" "$(claude_command "$cwd")" >/dev/null
fi

# Coming from the split layout the editor and the terminal are panes of this tab
# rather than tabs of their own, and they are moved out instead of being built a
# second time.
split_nvim=$(pane_by_label "$workspace" "$main_tab" nvim)
split_term=$(pane_by_label "$workspace" "$main_tab" term)

if [ -n "$split_nvim" ] || [ -n "$split_term" ]; then
  pane_rename "$main_pane" ""
  if [ -n "$split_nvim" ]; then
    tab_out "$split_nvim" nvim
  fi
  if [ -n "$split_term" ]; then
    tab_out "$split_term" term
  fi
  exit 0
fi

create_tab_running "$workspace" nvim "$cwd" "$(editor_command "$cwd")"
create_tab_running "$workspace" term "$cwd"
