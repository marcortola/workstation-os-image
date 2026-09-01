#!/usr/bin/env bash
set -euo pipefail

herdr_cli() {
  "${HERDR_BIN_PATH:-herdr}" "$@"
}

plugin_dir=$(cd "$(dirname "$0")" && pwd)

pause_on_failure() {
  local status=$?
  if [ "$status" -ne 0 ] && [ "$status" -ne 130 ]; then
    printf 'failed (exit %s). press enter to close\n' "$status"
    read -r _
  fi
}
trap pause_on_failure EXIT
trap 'exit 0' INT TERM

slugify() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-//; s/-$//'
}

strip_control_chars() {
  printf '%s' "$1" | tr -d '[:cntrl:]'
}

is_valid_branch_name() {
  case "$1" in
    q | quit) return 1 ;;
    *) git check-ref-format --branch "$1" >/dev/null 2>&1 ;;
  esac
}

start_cwd=${HERDR_ACTIVE_PANE_CWD:-$PWD}
main_repo=$(dirname "$(git -C "$start_cwd" rev-parse --path-format=absolute --git-common-dir)")

printf 'repo: %s\n' "$main_repo"
printf 'enter nothing (or q) to cancel\n'
read -r -p 'branch: ' raw_branch || exit 0

branch=$(strip_control_chars "${raw_branch:-}")
if [ -z "$branch" ]; then
  exit 0
fi
if ! is_valid_branch_name "$branch"; then
  printf 'not a valid branch name, nothing created\n'
  exit 0
fi

slug=$(slugify "$branch")
worktree_path="${main_repo}__worktrees/${slug}"

response=$(herdr_cli worktree create --cwd "$main_repo" --branch "$branch" --path "$worktree_path" --label "$slug" --focus)
workspace_id=$(printf '%s' "$response" | jq -r '.result.workspace.workspace_id // empty')

if [ -n "$workspace_id" ]; then
  "$plugin_dir/layout.sh" "$workspace_id" "$worktree_path"
fi
