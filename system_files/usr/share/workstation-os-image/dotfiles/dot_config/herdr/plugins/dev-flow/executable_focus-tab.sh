#!/usr/bin/env bash
# Answer prefix+m, prefix+n and prefix+t with the same three destinations under
# either layout: a tab of that label in the default one, a pane of that label in
# the split one.
set -euo pipefail

plugin_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=layout-common.sh
. "$plugin_dir/layout-common.sh"

label=$1

workspace=${HERDR_ACTIVE_WORKSPACE_ID:-$(focused_workspace)}
if [ -z "$workspace" ]; then
  exit 0
fi

tab=$(tab_by_label "$workspace" "$label")
if [ -n "$tab" ]; then
  herdr_cli tab focus "$tab" >/dev/null
  exit 0
fi

# The split layout keeps all three in one tab, so the destination is a pane. It
# is given the column on the way in, which is what makes prefix+n and prefix+t a
# toggle between the editor and the terminal; main is only focused, because the
# split holding it is vertical and layout_grow_pane leaves those alone.
tab=$(focused_tab_of "$workspace")
if [ -z "$tab" ]; then
  exit 0
fi

pane=$(pane_by_label "$workspace" "$tab" "$label")
if [ -n "$pane" ]; then
  layout_grow_pane "$tab" "$pane"
  pane_focus "$pane"
fi
