#!/usr/bin/env bash
set -euo pipefail

herdr_cli() {
  "${HERDR_BIN_PATH:-herdr}" "$@"
}

plugin_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=agent-finished.sh
. "$plugin_dir/agent-finished.sh"

# The parked-work seam is image payload, not part of this plugin, because the
# probes it dispatches read vendor internals and belong where the build gates
# can see them. A machine without the image half keeps the behaviour it had
# before probes existed rather than failing a row build.
# shellcheck source=../../../../../../../libexec/workstation-agent-probes/lib.sh
if [ -r /usr/libexec/workstation-agent-probes/lib.sh ]; then
  . /usr/libexec/workstation-agent-probes/lib.sh
else
  agent_parked_probe() { printf '[]\n'; }
  agent_parked_previous() { :; }
  agent_parked_write() { :; }
fi

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

# The three live reads a row build needs, held together so the picker and the
# DMS bar widget cannot drift into fetching different things. Globals rather
# than a return value because bash has no way to hand back three blobs, and the
# script already carries state at this level.
state_workspaces=
state_panes=
state_repo_by_cwd=
state_parked=
read_state() {
  state_workspaces=$(herdr_cli workspace list)
  state_panes=$(herdr_cli pane list)
  state_repo_by_cwd=$(repo_root_by_cwd "$state_workspaces" "$state_panes")
  sweep_parked
}

# The far side of a finish. The hook on pane.agent_status_changed stamps when
# the turn ends, and a turn that ends leaving a background shell running takes
# the same working -> idle transition as one that is actually done -- which is
# why the just-finished mark fires early today. Nothing emits an event when that
# background work ends: no agent has one, so herdr has none to forward. The only
# way to learn it is to notice a pane that was parked no longer is.
#
# So this is a poll, and it is deliberately not a timer. Both readers of this
# file already poll -- the picker rebuilds every 2s, the bar widget every 3s --
# and a third scheduler running slower than the two that exist would buy
# nothing. The cost is that a row build writes: the same stamp, through the same
# function, on the same clock as the hook. One clock, two writers.
unpark() {
  local pane=$1 workspace=$2 checkout=$3 status
  [ -n "$checkout" ] || return 0
  # The marker outlives the checkout it names. A directory that is gone is not a
  # finish worth recording, and agent_finished_write would key the stamp on a
  # path nothing will ever ask about again.
  [ -d "$checkout" ] || return 0

  status=$(printf '%s' "$state_panes" | jq -r --arg p "$pane" \
    '.result.panes[] | select(.pane_id == $p) | .agent_status' 2>/dev/null) || status=

  case $status in
    # Leaving the parked set because a NEW turn started is not the work ending.
    # The probe answers one question -- is background work alive -- and an agent
    # that picked up another turn stops being parked without anything having
    # finished. The hook owns that finish, as it always did.
    working | blocked) return 0 ;;
  esac

  agent_finished_write "$checkout"

  # The sidebar badge is the same answer in herdr's own state, expired by TTL
  # rather than swept. Only while the space is still open and quiet; a pane that
  # is gone has no workspace left to carry a token.
  [ -n "$workspace" ] || return 0
  case $status in
    idle | done)
      herdr_cli workspace report-metadata "$workspace" \
        --source dev.flow --token fresh=new --ttl-ms "$((AGENT_FRESH_SECONDS * 1000))" >/dev/null 2>&1 || true
      ;;
  esac
}

parked_workspace_map() {
  printf '%s' "$1" | awk -F'\t' '$5 != "yes" { print $2 }' |
    jq -Rn '[inputs | select(length > 0) | {key: ., value: true}] | from_entries'
}

sweep_parked() {
  local panes parked previous current nagged_ids pane workspace cwd checkout session nagged age

  panes=$(printf '%s' "$state_panes" | jq -c '.result.panes')
  previous=$(agent_parked_previous)

  # A probe that failed is not a probe that said no. Conflating them makes one
  # bad tick -- a timeout under load, a session file read mid-rewrite -- look
  # exactly like the work ending, and fire the false finish this whole mechanism
  # exists to prevent. A tick that could not tell changes nothing at all: the
  # marker stands and every row keeps its last answer.
  if ! parked=$(agent_parked_probe "$panes"); then
    state_parked=$(parked_workspace_map "$previous")
    return 0
  fi

  # The checkout key is resolved once, on the edge into parked, and then carried
  # in the marker for as long as the pane stays parked -- one git call when
  # something starts rather than one per parked pane per tick -- keyed on the
  # session id as well as the pane id so a marker that outlived its herdr server
  # cannot hand a reused pane id someone else's checkout.
  current=$(
    printf '%s' "$panes" | jq -r --argjson parked "$parked" \
      '.[] | select(.pane_id | IN($parked[]))
           | [.pane_id, (.workspace_id // ""), (.cwd // ""), (.agent_session.value // "")] | @tsv' |
      while IFS=$'\t' read -r pane workspace cwd session; do
        [ -n "$cwd" ] || continue
        checkout=$(printf '%s' "$previous" |
          awk -F'\t' -v p="$pane" -v s="$session" '$1 == p && $4 == s { print $3; exit }')
        nagged=$(printf '%s' "$previous" |
          awk -F'\t' -v p="$pane" -v s="$session" '$1 == p && $4 == s { print $5; exit }')
        if [ -z "$checkout" ]; then
          checkout=$(agent_checkout_key "$cwd")
          nagged=no
        fi
        [ -n "$nagged" ] || nagged=no
        printf '%s\t%s\t%s\t%s\t%s\n' "$pane" "$workspace" "$checkout" "$session" "$nagged"
      done
  )

  # The unpark edge: parked a moment ago, not parked now. Re-stamp before
  # recording, so a kill between the two repeats the stamp on the next tick
  # rather than losing it. A row already nagged was called finished once and
  # must not be called finished again when it finally goes.
  while IFS=$'\t' read -r pane workspace checkout session nagged; do
    [ -n "$pane" ] || continue
    if printf '%s' "$current" | cut -f1,4 | grep -qxF "$pane$(printf '\t')$session"; then
      continue
    fi
    if [ "$nagged" != yes ]; then
      unpark "$pane" "$workspace" "$checkout"
    fi
  done <<<"$previous"

  # A background task whose command can never exit would hold its checkout
  # parked forever and the mark would never fire at all, which is worse than
  # firing early. Past the ceiling it is called finished once and the flag keeps
  # it that way: the row leaves parked so the mark can actually show, and the
  # pane is not re-nagged and not read as an unpark when the task really ends.
  # No new clock -- the age is the existing stamp through the existing accessor.
  nagged_ids=
  while IFS=$'\t' read -r pane workspace checkout session nagged; do
    [ -n "$checkout" ] || continue
    [ "$nagged" = no ] || continue
    if age=$(agent_finished_age "$checkout") && [ "$age" -gt "$AGENT_PARKED_NAG_SECONDS" ]; then
      unpark "$pane" "$workspace" "$checkout"
      nagged_ids=$nagged_ids$pane$'\n'
    fi
  done <<<"$current"
  if [ -n "$nagged_ids" ]; then
    current=$(printf '%s' "$current" | awk -F'\t' -v ids="$nagged_ids" '
      BEGIN { n = split(ids, a, "\n"); for (i = 1; i <= n; i++) if (a[i] != "") flagged[a[i]] = 1 }
      { if ($1 in flagged) $5 = "yes"; print $1 "\t" $2 "\t" $3 "\t" $4 "\t" $5 }')
  fi

  [ -z "$current" ] || current=$current$'\n'
  agent_parked_write "$current"
  state_parked=$(parked_workspace_map "$current")
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
  done < <(jq -rn --argjson workspaces "$state_workspaces" --argjson repo_by_cwd "$state_repo_by_cwd" \
    '[$workspaces.result.workspaces[].worktree.repo_root] + [$repo_by_cwd[]] | map(select(. != null)) | unique | .[]')
  wait
  { cat "$scans"/* 2>/dev/null || true; } | jq -Rn '[inputs | split("\t") | {repo: .[0], checkout: .[1]}]'
  rm -rf "$scans"
}

# The row build, as data. The herdr picker renders these rows as padded TSV and
# the DMS bar widget reads the same objects as JSON, so state, the just-finished
# mark and the attention ordering are computed exactly once. $1 is the worktree
# topology: the picker passes its memoised disk scan so that closed checkouts
# appear, the widget passes [] because it lists only open spaces.
rows_json() {
  jq -cn \
    --argjson workspaces "$state_workspaces" \
    --argjson panes "$state_panes" \
    --argjson repo_by_cwd "$state_repo_by_cwd" \
    --argjson finished "$(agent_finished_map)" \
    --argjson now "$(date +%s)" \
    --argjson fresh_seconds "$AGENT_FRESH_SECONDS" \
    --argjson parked "$state_parked" \
    --argjson worktrees "$1" '
      # herdr leaves worktree metadata empty on some spaces; their panes still know where they live.
      ( $panes.result.panes
          | map(select(.cwd != null))
          | group_by(.workspace_id)
          | map({ key: .[0].workspace_id, value: .[0].cwd })
          | from_entries ) as $pane_cwd

      | def checkout: .worktree.checkout_path // $pane_cwd[.workspace_id] // "";
        def repo: .worktree.repo_root // $repo_by_cwd[checkout] // checkout // .label;
        def is_worktree: .worktree.is_linked_worktree // false;
        # Turn over, background work still running. Keyed on the workspace id
        # and not on checkout, because checkout here is the raw pane cwd while
        # the sweep records the git-normalised key, and the two only agree by
        # accident. jq rejects a forward reference, so this stays above state.
        def is_parked: $parked[.workspace_id] == true;
        # The rollup herdr computes for the space, in the words herdr uses for
        # it: blocked, done, working, idle. Reading .agent_status rather than
        # folding the agent list again is what keeps the picker saying what the
        # sidebar says. herdr reports unknown for a space with no agent, which
        # is most rows, so that one renders as nothing rather than as a column
        # of noise. No apostrophes in here: the whole program is one
        # single-quoted shell word.
        # A parked pane reads idle or done depending on whether you have looked
        # at it since the turn ended; both mean the same thing here.
        def state: if .opened == false then "closed"
                   elif (.agent_status // "unknown") == "unknown" then ""
                   elif is_parked and ((.agent_status == "idle") or (.agent_status == "done")) then "parked"
                   else .agent_status end;
        # herdr times nothing, so recency comes from the stamp agent-freshness.sh
        # writes per checkout on pane.agent_status_changed.
        def finished_at: $finished[checkout] // null;
        # Working again means you already answered it, so the mark goes as soon
        # as the space goes back to work -- the same moment the hook clears the
        # sidebar token.
        def is_fresh: state != "working" and state != "parked" and (finished_at != null) and (($now - finished_at) < $fresh_seconds);
        def marked_state: state + (if is_fresh and state != "" then "*" else "" end);
        def attention_rank: if state == "blocked" or state == "done" then 0 elif state == "working" or state == "parked" then 1 else 2 end;

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
      | map({ workspace_id: .workspace_id,
              label: .label,
              repo: repo,
              checkout: checkout,
              is_worktree: is_worktree,
              state: state,
              marked_state: marked_state,
              is_parked: is_parked,
              is_fresh: is_fresh,
              attention_rank: attention_rank })'
}

space_rows() {
  local topology=$1
  local worktrees
  read_state

  # The per-repo `git worktree list` scan is the only slow part of a row build,
  # and its answer changes only when a checkout appears or goes. The refresh loop
  # reruns everything else every couple of seconds and reuses this; ctrl-r is
  # what throws it away.
  if [ -s "$topology" ]; then
    worktrees=$(cat "$topology")
  else
    worktrees=$(disk_worktrees)
    printf '%s' "$worktrees" >"$topology"
  fi

  # The picker's columns, unchanged: the cache is read positionally by
  # visible_rows and by the wt: branch at the bottom of this file.
  rows_json "$worktrees" |
    jq -r '
      def pad($width): . + (" " * ($width - length));
      .[]
      | [ .workspace_id,
          (.marked_state | pad(8)),
          (((if .is_worktree then "  └ " else "" end) + .label) | pad(38)),
          .checkout,
          .repo,
          (.is_worktree | tostring),
          .label ]
      | @tsv'
}

# A worktree keeps the repo row that the tree prefix points at, and a repo keeps its worktrees; both come back dim.
visible_rows() {
  local cache=$1 query=${2-}
  local view=$cache.view matched best

  # Every row the cache holds is shown. Nothing ages out: a checkout leaves the
  # list by being removed, and the closed rows come from `git worktree list`, so
  # the list is bounded by what is on disk rather than by a clock.
  cp "$cache" "$view"

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
      colour["parked"]  = "\033[33m"
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

# The DMS bar widget's poll. Only the open spaces, so no git runs at all and the
# answer costs the two herdr reads: the widget is an ambient state indicator and
# this picker stays the navigator. Exits non-zero with herdr down, which is how
# the widget tells "no spaces" from "no server".
if [ "${1:-}" = "--json" ]; then
  read_state
  rows_json '[]'
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
    --header='  ^s s close  ^r rescan  * just finished' \
    --bind "ctrl-r:reload('$0' --rescan '$cache' '$topology' {q})" \
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
