#!/usr/bin/env bash
set -euo pipefail

herdr_cli() {
  "${HERDR_BIN_PATH:-herdr}" "$@"
}

# A hand-linked project carries no worktree metadata, so git resolves its repo from the pane.
repo_root_by_cwd() {
  local cwd git_dir
  jq -rn --argjson workspaces "$1" --argjson panes "$2" '
      ( $workspaces.result.workspaces
        | map(select(.worktree.repo_root == null) | .workspace_id) ) as $unknown
      | [ $panes.result.panes[]
          | select(.cwd != null and (.workspace_id | IN($unknown[])))
          | .cwd ]
      | unique | .[]' |
    while IFS= read -r cwd; do
      git_dir=$(git -C "$cwd" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || continue
      printf '%s\t%s\n' "$cwd" "${git_dir%/*}"
    done |
    jq -Rn '[inputs | split("\t") | {key: .[0], value: .[1]}] | from_entries'
}

checkouts_of() {
  git -C "$1" worktree list --porcelain 2>/dev/null |
    awk -v root="$1" '
      /^worktree /{ path = substr($0, 10); prunable = 0; next }
      /^prunable/ { prunable = 1; next }
      /^$/        { if (path != "" && path != root && !prunable) print root "\t" path; path = "" }
    ' || true
}

# Worktrees made outside herdr never became spaces, so the picker reads the live ones straight from git too.
disk_worktrees() {
  local root scans index=0
  scans=$(mktemp -d)
  # A git call per repo is slow enough to show, so they run at once into a file each.
  while IFS= read -r root; do
    index=$((index + 1))
    checkouts_of "$root" >"$scans/$index" &
  done < <(jq -rn --argjson workspaces "$1" --argjson repo_by_cwd "$2" \
    '[$workspaces.result.workspaces[].worktree.repo_root] + [$repo_by_cwd[]] | map(select(. != null)) | unique | .[]')
  wait
  { cat "$scans"/* 2>/dev/null || true; } | jq -Rn '[inputs | split("\t") | {repo: .[0], checkout: .[1]}]'
  rm -rf "$scans"
}

space_rows() {
  local workspaces panes repo_by_cwd
  workspaces=$(herdr_cli workspace list)
  panes=$(herdr_cli pane list)
  repo_by_cwd=$(repo_root_by_cwd "$workspaces" "$panes")

  jq -rn \
    --argjson workspaces "$workspaces" \
    --argjson agents "$(herdr_cli agent list)" \
    --argjson panes "$panes" \
    --argjson repo_by_cwd "$repo_by_cwd" \
    --argjson worktrees "$(disk_worktrees "$workspaces" "$repo_by_cwd")" '
      def pad($width): . + (" " * ($width - length));

      ( $agents.result.agents
        | group_by(.workspace_id)
        | map({ key: .[0].workspace_id,
                value: (if   any(.[]; .agent_status == "blocked" or .agent_status == "done") then "action"
                        elif any(.[]; .agent_status == "working")                            then "working"
                        else "" end) })
        | from_entries ) as $status

      # herdr leaves worktree metadata empty on some spaces; their panes still know where they live.
      | ( $panes.result.panes
          | map(select(.cwd != null))
          | group_by(.workspace_id)
          | map({ key: .[0].workspace_id, value: .[0].cwd })
          | from_entries ) as $pane_cwd

      | def checkout: .worktree.checkout_path // $pane_cwd[.workspace_id] // "";
        def repo: .worktree.repo_root // $repo_by_cwd[checkout] // checkout // .label;
        def is_worktree: .worktree.is_linked_worktree // false;
        def state: if .opened == false then "closed" else ($status[.workspace_id] // "") end;
        def attention_rank: if state == "action" then 0 elif state == "working" then 1 else 2 end;

        ( $workspaces.result.workspaces | map(checkout) ) as $open_paths

      | ( $worktrees
          | map(select(.checkout | IN($open_paths[]) | not))
          | to_entries
          | map({ workspace_id: ("wt:" + .value.checkout),
                  label: (.value.checkout | split("/") | last),
                  opened: false,
                  order: (1000 + .key),
                  worktree: { repo_root: .value.repo, checkout_path: .value.checkout, is_linked_worktree: true } }) ) as $closed

      | ( $workspaces.result.workspaces | to_entries | map(.value + { order: .key }) ) + $closed
      | group_by(repo)
      # A worktree needs its repo row above it, so the whole group rises when one space wants me.
      | sort_by([(map(attention_rank) | min), (map(.order) | min)])
      | map(sort_by([is_worktree, attention_rank, .order]))
      | flatten
      | .[]
      | [ .workspace_id,
          (state | pad(8)),
          (((if is_worktree then "  └ " else "" end) + .label) | pad(38)),
          checkout,
          repo,
          (is_worktree | tostring),
          .label ]
      | @tsv'
}

# A worktree keeps the repo row that the tree prefix points at, and a repo keeps its worktrees; both come back dim.
visible_rows() {
  local cache=$1 query=${2-}
  local matched best

  if [ -n "$query" ]; then
    matched=$(cut -f1,7 "$cache" | fzf --filter="$query" --delimiter='\t' --nth=2 | cut -f1) || true
  else
    matched=$(cut -f1 "$cache")
  fi

  # fzf --filter ranks by score, so the first id is the row the cursor belongs on.
  best=$(printf '%s\n' "$matched" | sed -n 1p)

  # BSD awk rejects a newline inside -v, and a wt: key carries a path, so the ids travel tab separated.
  matched=$(printf '%s' "$matched" | tr '\n' '\t')

  awk -F'\t' -v matched="$matched" -v best="$best" -v cursor="$cache.cursor" '
    BEGIN {
      split(matched, list, "\t")
      for (i in list) if (list[i] != "") hit[list[i]] = 1
    }
    FNR == NR {
      if ($1 in hit) { if ($6 == "true") kin[$5] = 1; else group[$5] = 1 }
      next
    }
    {
      if (!($1 in hit) && !($5 in group) && !($5 in kin && $6 == "false")) next
      shown++
      if ($1 == best) row = shown
      if ($1 in hit) print $1 "\t" $2 "\t" $3 "\t" $4
      else print $1 "\t\033[2m" $2 "\t" $3 "\t" $4 "\033[0m"
    }
    END { print "pos(" (row ? row : 1) ")" > cursor }
  ' "$cache" "$cache"
}

if [ "${1:-}" = "--rows" ]; then
  visible_rows "$2" "${3-}"
  exit 0
fi

trap 'exit 0' INT TERM

# ctrl+s is XOFF by default and would never reach fzf as the close chord.
stty -ixon </dev/tty 2>/dev/null || true

cache=$(mktemp)
trap 'rm -f "$cache" "$cache.cursor"' EXIT
space_rows >"$cache"

# fzf scores every line on its own, which breaks the tree, so the rows are refiltered and redrawn on each keystroke.
chosen=$("$0" --rows "$cache" |
  fzf --height 100% --reverse --ansi --disabled --delimiter='\t' --with-nth=2.. --tabstop=1 \
    --prompt='space> ' --border-label=' spaces ' --header='  ^s s close' \
    --bind "change:reload('$0' --rows '$cache' {q})+rebind(ctrl-s)+unbind(s)" \
    --bind "load:transform(cat '$cache.cursor' 2>/dev/null)" \
    --bind 'start:unbind(s)' \
    --bind 'ctrl-s:unbind(ctrl-s)+rebind(s)' \
    --bind 's:abort') || exit 0

# The popup dies with the script, so a failed call has to stop and show itself.
run_herdr() {
  local failure
  if failure=$(herdr_cli "$@" 2>&1 >/dev/null); then
    return 0
  fi
  printf 'herdr %s\n\n%s\n' "$*" "$failure"
  read -r -n 1 -s _ </dev/tty || true
}

# A wt: key is a worktree with no space yet, so picking it has to open the space first.
key=$(printf '%s' "$chosen" | cut -f1)
[ -n "$key" ] || exit 0

case $key in
  wt:*)
    repo=$(awk -F'\t' -v key="$key" '$1 == key { print $5; exit }' "$cache")
    parent=$(awk -F'\t' -v repo="$repo" '$1 !~ /^wt:/ && $5 == repo && $6 == "false" { print $1; exit }' "$cache")
    open_args=(worktree open --path "${key#wt:}" --focus)
    if [ -n "$parent" ]; then
      open_args+=(--workspace "$parent")
    fi
    run_herdr "${open_args[@]}"
    ;;
  *)
    run_herdr workspace focus "$key"
    ;;
esac
