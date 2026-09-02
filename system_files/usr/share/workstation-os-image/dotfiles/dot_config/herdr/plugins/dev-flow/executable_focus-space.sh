#!/usr/bin/env bash
# Focus a herdr space from outside herdr: scope the session over the socket,
# then raise the window whose client is attached to it. The DMS bar widget is
# the only caller -- the space picker needs only the first half, because it is
# already running inside the window it would raise.
#
# The second half is workstation-dev's `herdr_focus_existing_window` without its
# self-exclusion: that one runs in a terminal of its own and has to skip it, this
# one is called from a layer-shell popout, which is not a toplevel and so never
# appears in the window list at all.
set -euo pipefail

workspace=${1:?workspace id}

# DMS spawns this with the session's environment rather than a login shell, so
# resolve the binaries the way the niri binds do rather than trusting PATH.
herdr_bin=herdr
command -v herdr >/dev/null 2>&1 || herdr_bin=/home/linuxbrew/.linuxbrew/bin/herdr

"$herdr_bin" workspace focus "$workspace" >/dev/null

# Both binds that launch a client are matched: Mod+Shift+T opens one as `herdr`,
# the project picker as `dev-terminal`. With no window up there is nothing to
# raise and scoping the workspace was the whole job, so that is a success.
window=$(niri msg -j windows 2>/dev/null |
  jq -r '[.[] | select(.app_id == "herdr" or .app_id == "dev-terminal") | .id] | first // empty') || exit 0

[ -n "$window" ] || exit 0
niri msg action focus-window --id "$window" >/dev/null 2>&1 || true
