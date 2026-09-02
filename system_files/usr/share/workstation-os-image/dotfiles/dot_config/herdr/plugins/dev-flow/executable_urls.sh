#!/usr/bin/env bash
set -euo pipefail

herdr_cli() {
  "${HERDR_BIN_PATH:-herdr}" "$@"
}

trap 'exit 0' INT TERM

# HERDR_ACTIVE_PANE_ID is upstream residue: herdr 0.8.2 injects HERDR_PANE_ID
# and never sets that name, so reading it alone made prefix+u a popup that
# closed on itself with no list and nothing logged. navigate.sh carries the same
# pair and survived only because of its fallback.
pane=${HERDR_ACTIVE_PANE_ID:-${HERDR_PANE_ID:-}}
if [ -z "$pane" ]; then
  exit 0
fi

urls=$(herdr_cli pane read "$pane" --source recent-unwrapped --lines 3000 |
  grep -oE '(https?://|www\.)[^ 	"'"'"'<>()[:cntrl:]]+' |
  sed 's/[.,;:!?)"]*$//' |
  awk 'length($0) > 8 && !seen[$0]++' |
  tac)

if [ -z "$urls" ]; then
  printf 'no urls in this pane\n'
  sleep 1
  exit 0
fi

chosen=$(printf '%s\n' "$urls" | fzf --height 100% --reverse --prompt='url> ' --border-label=' urls ') || exit 0
if [ -n "$chosen" ]; then
  case "$chosen" in
    www.*) xdg-open "https://$chosen" ;;
    *) xdg-open "$chosen" ;;
  esac
fi
