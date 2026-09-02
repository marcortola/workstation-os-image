#!/usr/bin/env bash
# The default dev layout: three tabs -- main running the agent, plus nvim and
# term. Applied for a herdr-created worktree, for a project picked from the
# workstation-dev picker, and as one half of the prefix+shift+n toggle, which is
# also what takes the split layout (layout-split.sh) apart again.
#
# Every step here is written to converge rather than to build: a second run adds
# nothing, and a workspace that has drifted -- a tab closed, a pane exited, a
# duplicate left over -- comes back to the same three tabs. Building
# unconditionally is what stacked another `nvim` and another `term` on each
# press of the key.
set -euo pipefail

plugin_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=layout-common.sh
. "$plugin_dir/layout-common.sh"

workspace=$(target_workspace "${1:-}")
if [ -z "$workspace" ]; then
  echo "no workspace in context" >&2
  exit 1
fi

read -r main_tab main_pane cwd <<<"$(layout_anchor "$workspace" "${2:-}")"
if [ -z "$main_pane" ]; then
  echo "no agent pane in workspace $workspace" >&2
  exit 1
fi

# Give a pane of the split layout a tab of its own again. `pane move` carries the
# process across, so this undoes the split without restarting Neovim over its
# unsaved buffers. The pane label does not come with it: it exists so
# focus-tab.sh can find the pane inside the split tab, and here the tab label
# answers instead.
#
# A tab already carrying the label is moved into rather than a second one built.
# herdr accepts duplicate tab labels and every lookup takes the first match, so a
# second `nvim` tab does not merely clutter the bar: it captures prefix+n and the
# next split, and the editor actually in use is never found again.
tab_out() {
  local pane=$1 label=$2 existing
  tab_unzoom "$pane"
  existing=$(layout_tab_for_label "$workspace" "$label")
  if [ -n "$existing" ]; then
    tab_unzoom "$(first_pane_of_tab "$workspace" "$existing")"
    pane_move_into_tab "$pane" "$existing" down 0.5 || return 1
  else
    pane_move_new_tab "$pane" "$label" >/dev/null || return 1
  fi
  pane_rename "$pane" ""
}

# The tab for one of the two side roles, reused when it is already there and
# built only when it is not. An existing tab is handed its command again only if
# its pane went idle -- the rule the split layout applies to a pane it adopts --
# and a tab just created is started from this branch rather than probed, because
# a brand-new pane's shell is too young to answer the process probe reliably.
ensure_tab_running() {
  local label=$1 command=${2:-} tab pane
  tab=$(layout_tab_for_label "$workspace" "$label")
  if [ -n "$tab" ]; then
    pane=$(first_pane_of_tab "$workspace" "$tab")
    if [ -z "$pane" ] || ! pane_is_free "$pane"; then
      return 0
    fi
  else
    pane=$(herdr_cli tab create --workspace "$workspace" --label "$label" --cwd "$cwd" --no-focus |
      jq -r '.result.root_pane.pane_id // empty')
  fi
  if [ -n "$command" ] && [ -n "$pane" ]; then
    herdr_cli pane run "$pane" "$command" >/dev/null
  fi
}

# Coming from the split layout the editor and the terminal are panes rather than
# tabs of their own, and they are moved out instead of being built a second
# time. Either of the two can be missing -- a shell exited, a pane was closed --
# and the run carries on to the builders below rather than stopping there, so a
# half-taken-apart split ends up whole.
#
# They are looked for across the workspace, not inside the agent's tab. A pane
# of either name exists under no other layout, and it is not always in that tab:
# a split workspace whose agent pane had exited is rebuilt around a NEW agent
# tab above, leaving the editor and the terminal in the tab they were already
# in. Scoping the search to the agent's tab left them there and built
# replacements beside them.
split_nvim=$(workspace_pane_by_label "$workspace" nvim)
split_term=$(workspace_pane_by_label "$workspace" term)

if [ -n "$split_nvim" ] || [ -n "$split_term" ]; then
  # A pane that will not move is still here, still running the editor or the
  # shell. Carrying on would build a replacement beside it, which is the
  # duplication this whole file exists to avoid, so stop at the first refusal
  # and leave the split as it stands rather than half-taking it apart.
  if [ -n "$split_nvim" ]; then
    if ! tab_out "$split_nvim" nvim; then
      echo "could not move the editor out of the split; layout left as it was" >&2
      exit 1
    fi
  fi
  if [ -n "$split_term" ]; then
    if ! tab_out "$split_term" term; then
      echo "could not move the terminal out of the split; layout left as it was" >&2
      exit 1
    fi
  fi
  pane_rename "$main_pane" ""
fi

herdr_cli tab rename "$main_tab" main >/dev/null

if pane_is_free "$main_pane"; then
  herdr_cli pane run "$main_pane" "$(claude_command "$cwd")" >/dev/null
fi

ensure_tab_running nvim "$(editor_command "$cwd")"
ensure_tab_running term
