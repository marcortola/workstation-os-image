#!/usr/bin/env bash
set -euo pipefail

herdr_cli() {
  "${HERDR_BIN_PATH:-herdr}" "$@"
}

direction=$1
pane=${HERDR_ACTIVE_PANE_ID:-${HERDR_PANE_ID:-}}
if [ -z "$pane" ]; then
  exit 0
fi

key_for_direction() {
  case "$1" in
    left) printf 'ctrl+h' ;;
    down) printf 'ctrl+j' ;;
    up) printf 'ctrl+k' ;;
    right) printf 'ctrl+l' ;;
  esac
}

# See layout.sh's pane_is_free: `argv0` is not a field herdr 0.8.2 returns, and
# jq aborts on the null, so this answered "not vim" for every pane and ctrl+hjkl
# never reached Neovim or fzf.
pane_runs_vim_or_fzf() {
  herdr_cli pane process-info --pane "$pane" |
    jq -e -r '[.result.process_info.foreground_processes[]? | .name // .argv0 // ""] | any(test("^(n?vim|fzf)$"))' >/dev/null 2>&1
}

if pane_runs_vim_or_fzf; then
  herdr_cli pane send-keys "$pane" "$(key_for_direction "$direction")" >/dev/null
else
  herdr_cli pane focus --direction "$direction" --pane "$pane" >/dev/null
fi
