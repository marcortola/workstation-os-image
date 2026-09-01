#!/usr/bin/env bash
set -euo pipefail

herdr_cli() {
  "${HERDR_BIN_PATH:-herdr}" "$@"
}

repo_root_from_cwd() {
  git -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null | xargs -I {} dirname {}
}

workspace_rows() {
  local workspace info root linked cwd toplevel
  for workspace in $(herdr_cli workspace list | jq -r '.result.workspaces[].workspace_id'); do
    info=$(herdr_cli workspace get "$workspace" |
      jq -r '[(.result.workspace.worktree.repo_root // ""), ((.result.workspace.worktree.is_linked_worktree // false) | tostring)] | @tsv')
    root=$(printf '%s' "$info" | cut -f1)
    linked=$(printf '%s' "$info" | cut -f2)

    if [ -z "$root" ]; then
      cwd=$(herdr_cli pane list --workspace "$workspace" | jq -r '[.result.panes[].cwd] | map(select(. != null)) | first // empty')
      if [ -z "$cwd" ]; then
        continue
      fi
      root=$(repo_root_from_cwd "$cwd")
      if [ -z "$root" ]; then
        continue
      fi
      toplevel=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null || true)
      if [ "$toplevel" = "$root" ]; then linked=false; else linked=true; fi
    fi

    if [ "$linked" = "true" ]; then
      printf '%s\t%s\t0\n' "$root" "$workspace"
    else
      printf '%s\t%s\t1\n' "$root" "$workspace"
    fi
  done
}

parent_workspace_per_repo() {
  awk -F'\t' '
    $1 == "" { next }
    {
      if (!($1 in chosen) || ($3 == "1" && chosen_is_main[$1] != 1)) {
        chosen[$1] = $2
        chosen_is_main[$1] = ($3 == "1") ? 1 : 0
      }
    }
    END { for (repo in chosen) printf "%s\t%s\n", repo, chosen[repo] }
  '
}

linked_checkouts() {
  git -C "$1" worktree list --porcelain |
    awk '/^worktree /{print substr($0, 10)}' |
    grep -Fxv "$1" || true
}

opened=0
while IFS=$'\t' read -r repo_root workspace; do
  if [ -z "$repo_root" ]; then
    continue
  fi
  while IFS= read -r checkout; do
    if [ -z "$checkout" ]; then
      continue
    fi
    if failure=$(herdr_cli worktree open --workspace "$workspace" --path "$checkout" --no-focus 2>&1 >/dev/null); then
      opened=$((opened + 1))
      printf 'opened %s under %s\n' "$checkout" "$workspace"
    else
      printf 'skipped %s: %s\n' "$checkout" "$failure" >&2
    fi
  done <<EOF
$(linked_checkouts "$repo_root")
EOF
done <<EOF
$(workspace_rows | parent_workspace_per_repo)
EOF

printf 'adopted %s worktree(s)\n' "$opened"
