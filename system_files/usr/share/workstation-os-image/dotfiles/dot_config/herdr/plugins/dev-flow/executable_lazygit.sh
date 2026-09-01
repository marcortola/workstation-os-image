#!/usr/bin/env bash
# Open lazygit at the focused pane's repository root, in a herdr popup.
#
# Upstream drives Snacks.lazygit() inside a running Neovim over
# `nvim --server --remote-expr`. That cannot work here: `dev nvim` runs Neovim
# inside the project's Dev Container, so the host process tree shows
# devcontainer/node rather than nvim and the server socket lives in the
# container, not $XDG_RUNTIME_DIR. Reaching lazygit directly needs no editor.
set -euo pipefail

trap 'exit 0' INT TERM

start=${HERDR_ACTIVE_PANE_CWD:-$PWD}
root=$(git -C "$start" rev-parse --show-toplevel 2>/dev/null || true)
if [ -z "$root" ]; then
    printf 'not inside a git repository\n'
    sleep 1
    exit 0
fi

cd "$root"
exec lazygit
