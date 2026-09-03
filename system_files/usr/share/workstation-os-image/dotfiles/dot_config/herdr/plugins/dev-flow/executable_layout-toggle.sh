#!/usr/bin/env bash
# The one key both dev layouts answer to, on prefix+shift+n.
#
# Which one it applies is read off the workspace rather than remembered: herdr
# keeps no plugin state, and a workspace restored from an earlier session would
# arrive without it anyway. The marks each layout leaves are what it reads:
#
#   a PANE called nvim or term -> the split layout is on,
#                                 so take it apart (layout.sh)
#   a TAB called nvim or term  -> the default layout is on,
#                                 so fold it up (layout-split.sh)
#   neither                    -> nothing is laid out yet,
#                                 so build the default one
#
# The first press on a bare workspace therefore builds, and every press after it
# alternates. Both layouts stay separately invokable, because two callers need
# "apply the default layout" and not a toggle: worktree-create.sh for a checkout
# it has just made, and workstation-dev for a project picked from Mod+Shift+P.
set -euo pipefail

plugin_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=layout-common.sh
. "$plugin_dir/layout-common.sh"

workspace=$(target_workspace "${1:-}")
if [ -z "$workspace" ]; then
  echo "no workspace in context" >&2
  exit 1
fi

# A pane called `nvim` or `term` is the split layout's own mark and exists under
# no other layout, so the question is asked of the whole workspace rather than
# of the agent's tab. Asking only inside that tab meant the answer depended on
# finding the agent first, and a split workspace that had lost its agent pane
# answered "nothing is laid out here" -- which built the default layout on top
# of the split one and stranded the live editor in the orphan tab.
#
# The `dev` tab is the same mark in the one form that survives a server
# restart. session.json persists a tab's custom_name but nothing about a pane
# beyond its cwd and agent session, so after a reboot every pane label is gone
# and the pane test alone answered false on a workspace that is plainly still
# split -- rebuilding the default layout over it, which is the exact failure
# the pane test was widened to prevent.
split_applied() {
  [ -n "$(workspace_pane_by_label "$workspace" nvim)" ] ||
    [ -n "$(workspace_pane_by_label "$workspace" term)" ] ||
    [ -n "$(layout_tab_for_label "$workspace" dev)" ]
}

tabs_applied() {
  [ -n "$(layout_tab_for_label "$workspace" nvim)" ] ||
    [ -n "$(layout_tab_for_label "$workspace" term)" ]
}

if split_applied; then
  target=$plugin_dir/layout.sh
elif tabs_applied; then
  target=$plugin_dir/layout-split.sh
else
  target=$plugin_dir/layout.sh
fi

# The optional directory is forwarded only when there is one, so the layout
# resolves it from the workspace exactly as it does for a bare keypress.
if [ -n "${2:-}" ]; then
  exec "$target" "$workspace" "$2"
fi
exec "$target" "$workspace"
