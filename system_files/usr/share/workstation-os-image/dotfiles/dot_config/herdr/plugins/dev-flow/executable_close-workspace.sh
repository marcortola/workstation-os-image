#!/usr/bin/env bash
# prefix+shift+x popup: close the focused workspace, or -- when it holds a
# linked worktree -- offer to delete the checkout from disk.
#
# The confirm-and-remove itself lives in checkout-remove.sh, shared with the
# ship popup.
set -euo pipefail

plugin_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

# The popup dies with the script, so a failure has to hold the window open long
# enough to be read. 130 is the interrupt path and closes silently.
on_exit() {
    local status=$?
    if [ "$status" -ne 0 ] && [ "$status" -ne 130 ]; then
        printf '\nfailed (exit %s). press enter to close\n' "$status"
        read -r _ </dev/tty || true
    fi
}
trap on_exit EXIT
trap 'exit 0' INT TERM

workspace=${HERDR_ACTIVE_WORKSPACE_ID:-${HERDR_WORKSPACE_ID:-}}
if [ -z "$workspace" ]; then
    exit 0
fi

"$plugin_dir/checkout-remove.sh" "$workspace" --close-plain
