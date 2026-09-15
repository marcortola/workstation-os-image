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

# Which mark is on the workspace is layout-common's question -- the space picker
# asks it too, to build the default layout on a checkout that has never been
# laid out without touching one that is already split. The reasoning for each
# mark, and for asking the whole workspace rather than the agent's tab, lives
# beside the definitions there.
if layout_split_applied "$workspace"; then
  target=$plugin_dir/layout.sh
elif layout_tabs_applied "$workspace"; then
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
