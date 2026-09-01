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

pane_runs_vim_or_fzf() {
  herdr_cli pane process-info --pane "$pane" |
    jq -e -r '[.result.process_info.foreground_processes[]?.argv0] | any(test("^(n?vim|fzf)$"))' >/dev/null 2>&1
}

if pane_runs_vim_or_fzf; then
  herdr_cli pane send-keys "$pane" "$(key_for_direction "$direction")" >/dev/null
else
  herdr_cli pane focus --direction "$direction" --pane "$pane" >/dev/null
fi
