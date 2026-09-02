#!/usr/bin/env bash
set -euo pipefail

herdr_cli() {
  "${HERDR_BIN_PATH:-herdr}" "$@"
}

plugin_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=agent-finished.sh
# shellcheck source=agent-finished.sh
. "$plugin_dir/agent-finished.sh"

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
  local topology=$1
  local workspaces panes repo_by_cwd worktrees
  workspaces=$(herdr_cli workspace list)
  panes=$(herdr_cli pane list)
  repo_by_cwd=$(repo_root_by_cwd "$workspaces" "$panes")

  # The per-repo `git worktree list` scan is the only slow part of a row build,
  # and its answer changes only when a checkout appears or goes. The refresh loop
  # reruns everything else every couple of seconds and reuses this; ctrl-r is
  # what throws it away.
  if [ -s "$topology" ]; then
    worktrees=$(cat "$topology")
  else
    worktrees=$(disk_worktrees "$workspaces" "$repo_by_cwd")
    printf '%s' "$worktrees" >"$topology"
  fi

  jq -rn \
    --argjson workspaces "$workspaces" \
    --argjson panes "$panes" \
    --argjson repo_by_cwd "$repo_by_cwd" \
    --argjson finished "$(agent_finished_map)" \
    --argjson now "$(date +%s)" \
    --argjson fresh_seconds "$AGENT_FRESH_SECONDS" \
    --argjson expired_seconds "$AGENT_EXPIRED_SECONDS" \
    --argjson worktrees "$worktrees" '
      def pad($width): . + (" " * ($width - length));

      # herdr leaves worktree metadata empty on some spaces; their panes still know where they live.
      ( $panes.result.panes
          | map(select(.cwd != null))
          | group_by(.workspace_id)
          | map({ key: .[0].workspace_id, value: .[0].cwd })
          | from_entries ) as $pane_cwd

      | def checkout: .worktree.checkout_path // $pane_cwd[.workspace_id] // "";
        def repo: .worktree.repo_root // $repo_by_cwd[checkout] // checkout // .label;
        def is_worktree: .worktree.is_linked_worktree // false;
        # The rollup herdr computes for the space, in the words herdr uses for
        # it: blocked, done, working, idle. Reading .agent_status rather than
        # folding the agent list again is what keeps the picker saying what the
        # sidebar says. herdr reports unknown for a space with no agent, which
        # is most rows, so that one renders as nothing rather than as a column
        # of noise. No apostrophes in here: the whole program is one
        # single-quoted shell word.
        def state: if .opened == false then "closed"
                   elif (.agent_status // "unknown") == "unknown" then ""
                   else .agent_status end;
        # herdr times nothing, so recency comes from the stamp agent-freshness.sh
        # writes per checkout on pane.agent_status_changed.
        def finished_at: $finished[checkout] // null;
        # Working again means you already answered it, so the mark goes as soon
        # as the space goes back to work -- the same moment the hook clears the
        # sidebar token.
        def is_fresh: state != "working" and (finished_at != null) and (($now - finished_at) < $fresh_seconds);
        # Only a checkout with no space of its own expires. An open space always
        # shows, however long ago its agent finished.
        def is_expired: (.opened == false) and (finished_at != null) and (($now - finished_at) > $expired_seconds);
        def marked_state: state + (if is_fresh and state != "" then "*" else "" end);
        def attention_rank: if state == "blocked" or state == "done" then 0 elif state == "working" then 1 else 2 end;

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
          (marked_state | pad(8)),
          (((if is_worktree then "  └ " else "" end) + .label) | pad(38)),
          checkout,
          repo,
          (is_worktree | tostring),
          .label,
          (is_expired | tostring) ]
      | @tsv'
}

# A worktree keeps the repo row that the tree prefix points at, and a repo keeps its worktrees; both come back dim.
visible_rows() {
  local cache=$1 query=${2-}
  local view=$cache.view matched best

  # An expired checkout is one nothing finished in for AGENT_EXPIRED_SECONDS. It
  # is filtered out here rather than in the awk below so that it cannot be the
  # match the cursor lands on, and so its repo row is not dragged in by it.
  # ctrl-a writes the marker file that brings them back.
  if [ -e "$cache.all" ]; then
    cp "$cache" "$view"
  else
    awk -F'\t' '$8 != "true"' "$cache" >"$view"
  fi

  if [ -n "$query" ]; then
    matched=$(cut -f1,7 "$view" | fzf --filter="$query" --delimiter='\t' --nth=2 | cut -f1) || true
  else
    matched=$(cut -f1 "$view")
  fi

  # fzf --filter ranks by score, so the first id is the row the cursor belongs on.
  best=$(printf '%s\n' "$matched" | sed -n 1p)

  # BSD awk rejects a newline inside -v, and a wt: key carries a path, so the ids travel tab separated.
  matched=$(printf '%s' "$matched" | tr '\n' '\t')

  # The state carries the sidebar's colours as well as its words: red wants an
  # answer, green finished, yellow is still going, dim is neither. They are
  # applied here rather than baked into the cache so that a row dimmed for being
  # kin stays dim -- an embedded colour would outrank the dim wrapper.
  awk -F'\t' -v matched="$matched" -v best="$best" -v cursor="$cache.cursor" '
    BEGIN {
      split(matched, list, "\t")
      for (i in list) if (list[i] != "") hit[list[i]] = 1
      colour["blocked"] = "\033[31m"
      colour["done"]    = "\033[32m"
      colour["working"] = "\033[33m"
      colour["idle"]    = "\033[2m"
      colour["closed"]  = "\033[2m"
    }
    FNR == NR {
      if ($1 in hit) { if ($6 == "true") kin[$5] = 1; else group[$5] = 1 }
      next
    }
    {
      if (!($1 in hit) && !($5 in group) && !($5 in kin && $6 == "false")) next
      shown++
      if ($1 == best) row = shown
      if ($1 in hit) {
        key = $2
        sub(/\*?[ ]*$/, "", key)
        print $1 "\t" (key in colour ? colour[key] : "") $2 "\033[0m\t" $3 "\t" $4
      }
      else print $1 "\t\033[2m" $2 "\t" $3 "\t" $4 "\033[0m"
    }
    END { print "pos(" (row ? row : 1) ")" > cursor }
  ' "$view" "$view"
}

if [ "${1:-}" = "--rows" ]; then
  visible_rows "$2" "${3-}"
  exit 0
fi

# ctrl-r: throw the memoised worktree scan away and rebuild every row.
if [ "${1:-}" = "--rescan" ]; then
  rm -f "$3"
  space_rows "$3" >"$2.scan" && mv "$2.scan" "$2"
  visible_rows "$2" "${4-}"
  exit 0
fi

trap 'exit 0' INT TERM

# ctrl+s is XOFF by default and would never reach fzf as the close chord.
stty -ixon </dev/tty 2>/dev/null || true

cache=$(mktemp)
topology=$cache.topology
# A unix socket path is capped at 108 bytes and $TMPDIR here is deep, so the
# listening socket goes in the runtime directory. That directory is 0700, which
# is what keeps the action channel to this user.
socket="${XDG_RUNTIME_DIR:-/tmp}/herdr-spaces-$$.sock"
refresh_pid=

cleanup() {
  [ -n "$refresh_pid" ] && kill "$refresh_pid" 2>/dev/null
  rm -f "$cache" "$cache".* "$socket"
}
trap cleanup EXIT

space_rows "$topology" >"$cache"

# fzf has no timer, so the picker is refreshed from outside it: rebuild the rows
# every couple of seconds and push a reload through fzf's listening socket, but
# only once they actually differ, so nothing redraws under you while you read.
# Only the state is rebuilt; the worktree scan stays memoised.
refresh_loop() {
  while :; do
    sleep 2
    [ -S "$socket" ] || continue
    space_rows "$topology" >"$cache.poll" 2>/dev/null || continue
    if cmp -s "$cache.poll" "$cache"; then
      rm -f "$cache.poll"
      continue
    fi
    mv "$cache.poll" "$cache"
    curl -s --unix-socket "$socket" -X POST http://localhost/ \
      --data-raw "reload('$0' --rows '$cache' {q})" >/dev/null 2>&1 || true
  done
}
refresh_loop &
refresh_pid=$!

# fzf scores every line on its own, which breaks the tree, so the rows are refiltered and redrawn on each keystroke.
chosen=$("$0" --rows "$cache" |
  fzf --height 100% --reverse --ansi --disabled --delimiter='\t' --with-nth=2.. --tabstop=1 \
    --listen="$socket" \
    --prompt='space> ' --border-label=' spaces ' \
    --header='  ^s s close  ^r rescan  ^a expired  * just finished' \
    --bind "ctrl-r:reload('$0' --rescan '$cache' '$topology' {q})" \
    --bind "ctrl-a:execute-silent(if [ -e '$cache.all' ]; then rm -f '$cache.all'; else : >'$cache.all'; fi)+reload('$0' --rows '$cache' {q})" \
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
