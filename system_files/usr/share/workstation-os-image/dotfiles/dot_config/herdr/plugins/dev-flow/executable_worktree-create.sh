#!/usr/bin/env bash
set -euo pipefail

herdr_cli() {
  "${HERDR_BIN_PATH:-herdr}" "$@"
}

plugin_dir=$(cd "$(dirname "$0")" && pwd)

work=$(mktemp -d)

pause_on_failure() {
  local status=$?
  rm -rf "$work"
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

# `git worktree add` finishes the checkout BEFORE it runs post-checkout, and
# githooks(5) is explicit that the hook "cannot affect the outcome of git switch
# or git checkout, other than that the hook's exit status becomes the exit status
# of these two commands". So a repository whose post-checkout exits non-zero --
# git-lfs's stock hook with git-lfs missing, husky, lefthook, or `git lfs
# post-checkout` itself failing on the network -- makes herdr report failure over
# a checkout that is complete and clean. Dying here under `set -e` is what
# abandons it: no layout, no propagation, and the next adopt-worktrees.sh startup
# pass launders it into a workspace nothing tells apart from a healthy one.
# Adopt it instead. Only a checkout git did not produce is a failure.
if ! response=$(herdr_cli worktree create --cwd "$main_repo" --branch "$branch" --path "$worktree_path" --label "$slug" --focus 2>"$work/create.err"); then
  cat "$work/create.err" >&2
  # Adopt only a checkout git actually produced for THIS branch, of THIS repo.
  # `git worktree add` also fails when the path is already occupied, and a bare
  # `-d` probe would hand the workspace whatever stranger's directory is sitting
  # there.
  checkout_head=$(git -C "$worktree_path" rev-parse --abbrev-ref HEAD 2>/dev/null || true)
  checkout_repo=$(git -C "$worktree_path" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)
  if [ "$checkout_head" != "$branch" ] || [ "$checkout_repo" != "$main_repo/.git" ]; then
    exit 1
  fi
  parent_workspace=${HERDR_ACTIVE_WORKSPACE_ID:-${HERDR_WORKSPACE_ID:-}}
  if [ -z "$parent_workspace" ]; then
    printf '\n%s exists, but there is no active workspace to adopt it under.\n' "$worktree_path" >&2
    exit 1
  fi
  printf '\ngit created the checkout regardless; adopting %s\n' "$worktree_path"
  if ! response=$(herdr_cli worktree open --workspace "$parent_workspace" --path "$worktree_path" --focus 2>"$work/open.err"); then
    cat "$work/open.err" >&2
    exit 1
  fi
  # herdr emits worktree.created only for a checkout it created itself, so the
  # second propagation net never fired either. Call the same handler rather than
  # growing a third copy list. It installs dependencies, so say what the wait is
  # rather than leaving the popup looking hung, and name the retry if it fails --
  # a silent `|| true` here would close the popup over a checkout with no .env.
  printf 'populating it (this installs dependencies)\n'
  "$plugin_dir/worktree-setup.sh" "$worktree_path" \
    || printf '\nworktree-setup.sh failed; finish by hand:\n  %s %s\n' \
         "$plugin_dir/worktree-setup.sh" "$worktree_path" >&2
elif [ -s "$work/create.err" ]; then
  # herdr succeeded but said something. Losing it to the capture file is how a
  # warning goes unread.
  cat "$work/create.err" >&2
fi

workspace_id=$(printf '%s' "$response" | jq -r '.result.workspace.workspace_id // .result.workspace_id // empty')

if [ -n "$workspace_id" ]; then
  "$plugin_dir/layout.sh" "$workspace_id" "$worktree_path"
fi
