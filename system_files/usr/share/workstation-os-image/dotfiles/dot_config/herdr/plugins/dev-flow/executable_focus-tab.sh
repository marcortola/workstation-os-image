#!/usr/bin/env bash
# Answer prefix+m, prefix+n and prefix+t with the same destinations under either
# layout: a tab of that label in the default one, a pane of that label in the
# split one.
#
# `agent` is not a label but a request for the next agent slot, because a
# checkout holds as many as it has been given and one key has to reach all of
# them. Pressed on an agent it moves to the next and wraps, so with one agent it
# still means what prefix+m always meant: go to the agent.
#
# Arriving is also what restarts the two roles that are more than a shell: a
# `main` or `nvim` destination found sitting at a prompt -- the agent quit, the
# editor was closed -- is handed its command again on the way in, by
# relaunch_role_pane and the rule the layouts already build under.
set -euo pipefail

plugin_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=layout-common.sh
. "$plugin_dir/layout-common.sh"

label=$1

workspace=${HERDR_WORKSPACE_ID:-$(focused_workspace)}
if [ -z "$workspace" ]; then
  exit 0
fi

# The agent slots in tab-bar order, focus moving to the one after whichever tab
# holds the focus now -- and to the first when the focus is not on an agent at
# all, which is what makes the key work from the editor or the terminal.
focus_next_agent() {
  local focused line tab pane slot_label i next=0
  local -a slots=()
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    slots+=("$line")
  done < <(agent_slots_of "$workspace")
  [ "${#slots[@]}" -gt 0 ] || return 0

  focused=$(herdr_cli tab list --workspace "$workspace" |
    jq -r '[.result.tabs[] | select(.focused) | .tab_id] | first // empty')
  for i in "${!slots[@]}"; do
    if [ "${slots[$i]%%$'\t'*}" = "$focused" ]; then
      next=$(((i + 1) % ${#slots[@]}))
      break
    fi
  done

  IFS=$'\t' read -r tab pane slot_label <<<"${slots[$next]}"
  herdr_cli tab focus "$tab" >/dev/null
  if [ -n "$pane" ]; then
    layout_grow_pane "$tab" "$pane"
    pane_focus "$pane"
  else
    pane=$(first_pane_of_tab "$workspace" "$tab")
  fi
  relaunch_role_pane "$slot_label" "$pane"
}

if [ "$label" = agent ]; then
  focus_next_agent
  exit 0
fi

tab=$(layout_tab_for_label "$workspace" "$label")
if [ -n "$tab" ]; then
  herdr_cli tab focus "$tab" >/dev/null
  relaunch_role_pane "$label" "$(first_pane_of_tab "$workspace" "$tab")"
  exit 0
fi

# The split layout keeps all three in one tab, so the destination is a pane, and
# it is looked for across the whole workspace rather than in whichever tab
# happens to be focused. Searching only the focused tab made these three keys
# conditional: pressed from any other tab -- a scratch tab from prefix+c, say --
# they did nothing at all, and silently.
#
# The pane is given the column on the way in, which is what makes prefix+n and
# prefix+t a toggle between the editor and the terminal; main is only focused,
# because the split holding it is vertical and layout_grow_pane leaves those
# alone.
located=$(labelled_pane_of "$workspace" "$label")
if [ -z "$located" ]; then
  exit 0
fi

tab=${located%% *}
pane=${located#* }
herdr_cli tab focus "$tab" >/dev/null
layout_grow_pane "$tab" "$pane"
pane_focus "$pane"
relaunch_role_pane "$label" "$pane"
