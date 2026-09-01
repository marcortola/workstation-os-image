#!/usr/bin/env bash
set -euo pipefail

herdr_cli() {
  "${HERDR_BIN_PATH:-herdr}" "$@"
}

trap 'exit 0' INT TERM

workspace=${HERDR_ACTIVE_WORKSPACE_ID:-${HERDR_WORKSPACE_ID:-}}
if [ -z "$workspace" ]; then
  exit 0
fi

info=$(herdr_cli workspace get "$workspace" |
  jq -r '[((.result.workspace.worktree.is_linked_worktree // false) | tostring), (.result.workspace.worktree.checkout_path // ""), (.result.workspace.label // "")] | @tsv')
linked=$(printf '%s' "$info" | cut -f1)
checkout=$(printf '%s' "$info" | cut -f2)
label=$(printf '%s' "$info" | cut -f3)

if [ "$linked" != "true" ] || [ -z "$checkout" ]; then
  herdr_cli workspace close "$workspace" >/dev/null
  exit 0
fi

printf 'worktree: %s\n' "$label"
printf 'checkout: %s\n' "$checkout"
printf 'the branch is never deleted\n\n'

pending=$(git -C "$checkout" status --porcelain || true)
if [ -n "$pending" ]; then
  printf 'UNCOMMITTED WORK:\n%s\n\n' "$(printf '%s\n' "$pending" | head -15)"
fi

read -r -p 'delete this checkout from disk? [y/N] ' answer || exit 0
case "$answer" in
  y | Y | yes) ;;
  *) exit 0 ;;
esac

herdr_cli worktree remove --workspace "$workspace" --force >/dev/null
