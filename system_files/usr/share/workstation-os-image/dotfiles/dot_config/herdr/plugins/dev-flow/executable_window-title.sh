#!/usr/bin/env bash
set -euo pipefail

herdr_cli() {
  "${HERDR_BIN_PATH:-herdr}" "$@"
}

plugin_dir=$(cd "$(dirname "$0")" && pwd)

focused_space_as_worktree_repo() {
  herdr_cli workspace list | jq -r '
    [.result.workspaces[] | select(.focused)] | first // empty
    | (.worktree.repo_name // "") as $repo
    | if $repo == "" or $repo == .label then .label else "\(.label)[\($repo)]" end'
}

title=$(focused_space_as_worktree_repo)
if [ -z "$title" ]; then
  exit 0
fi

# The tab bar's right-hand entry runs this script rather than duplicating the
# derivation above: herdr resolves a `command` entry on the server and reads its
# last output line, so --print writes the title instead of pushing it.
if [ "${1:-}" = "--print" ]; then
  printf '%s\n' "$title"
  exit 0
fi

jq -cn --arg title "$title" \
  '{id: "dev.flow:window-title", method: "client.window_title.set", params: {title: $title}}' |
  "$plugin_dir/herdr-request.sh" >/dev/null
