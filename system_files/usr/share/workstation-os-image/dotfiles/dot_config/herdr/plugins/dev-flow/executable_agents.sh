#!/usr/bin/env bash
set -euo pipefail

herdr_bin=${HERDR_BIN_PATH:-herdr}

herdr_cli() {
  "$herdr_bin" "$@"
}

trap 'exit 0' INT TERM

# ctrl+s is XOFF by default and would never reach fzf as the close chord.
stty -ixon </dev/tty 2>/dev/null || true

project_branch_labels() {
  local id project checkout branch
  herdr_cli workspace list |
    jq -r '.result.workspaces[] | [.workspace_id, (.worktree.repo_name // .label), (.worktree.checkout_path // "")] | @tsv' |
    while IFS=$'\t' read -r id project checkout; do
      branch=$([ -n "$checkout" ] && git -C "$checkout" branch --show-current 2>/dev/null || true)
      if [ -n "$branch" ]; then
        printf '%s\t%s[%s]\n' "$id" "$project" "$branch"
      else
        printf '%s\t%s\n' "$id" "$project"
      fi
    done |
    jq -Rn '[inputs | split("\t") | {key: .[0], value: .[1]}] | from_entries'
}

agent_rows() {
  jq -rn \
    --argjson labels "$(project_branch_labels)" \
    --argjson agents "$(herdr_cli agent list)" '
      {blocked: 0, done: 1, idle: 2, working: 3, unknown: 4} as $attention
      | $agents.result.agents
      | sort_by($attention[.agent_status] // 9)
      | .[]
      | [ .pane_id,
          .agent_status,
          ($labels[.workspace_id] // .workspace_id),
          (.terminal_title_stripped // .agent) ]
      | @tsv' |
    awk -F'\t' '{ printf "%s\t%-8s %-34s %s\n", $1, $2, $3, $4 }'
}

prompt_agent() {
  local message
  read -r -p 'msg> ' message || return 0
  [ -n "$message" ] && herdr_cli agent prompt "$1" "$message" >/dev/null
}

if [ "${1:-}" = "--rows" ]; then
  agent_rows
  exit 0
fi

while :; do
  picked=$(agent_rows |
    fzf --height 100% --reverse --ansi --no-sort \
      --with-nth=2.. --delimiter='\t' \
      --prompt='agent> ' --border-label=' agents ' \
      --header='  ^o send prompt  ^r reload  ^d/^u scroll preview  tab/S-tab move  ^s a close' \
      --preview "$herdr_bin agent read {1} --source visible --format ansi" \
      --preview-window 'right:60%' \
      --expect=ctrl-o \
      --bind 'tab:down,btab:up' \
      --bind 'ctrl-d:preview-half-page-down,ctrl-u:preview-half-page-up' \
      --bind "ctrl-r:reload($0 --rows)" \
      --bind 'start:unbind(a)' \
      --bind 'ctrl-s:unbind(ctrl-s)+rebind(a)' \
      --bind 'a:abort' \
      --bind 'change:rebind(ctrl-s)+unbind(a)') || exit 0

  key=$(printf '%s\n' "$picked" | sed -n 1p)
  pane=$(printf '%s\n' "$picked" | sed -n 2p | cut -f1)
  [ -n "$pane" ] || exit 0

  if [ "$key" = "ctrl-o" ]; then
    prompt_agent "$pane"
    continue
  fi

  herdr_cli agent focus "$pane" >/dev/null
  exit 0
done
