#!/usr/bin/env bash
# Everything the two dev layouts share.
#
# There are two, and either can be applied on top of the other. layout.sh builds
# the default three tabs -- the primary agent's, plus nvim and term.
# layout-split.sh builds the single `dev` tab that pins the agent to a third of
# the width and stacks the editor over the terminal in the rest.
# layout-toggle.sh is the one key both answer to; it reads which is applied and
# runs the other. Switching moves the live panes rather than recreating them, so
# the agent keeps its conversation and Neovim keeps its unsaved buffers.
#
# Both layouts are about ONE agent: the primary slot, the editor and the shell.
# A checkout's further agents are tabs of their own, added by agent-add.sh and
# touched by neither layout -- which is what lets a second agent survive a
# toggle, and why neither builder needed a fourth ratio.
#
# Two rules hold every lookup here together, and both were learned from a
# workspace that had drifted:
#
#   * Ask for a LABEL, never for a position. `first_tab_of` was how both layouts
#     found the agent, and a workspace whose agent pane had exited answered with
#     the editor's tab instead -- which was then renamed `main`, given a second
#     Neovim beside it, and left with no agent at all.
#   * A label is not unique. herdr accepts two tabs called `nvim` and every
#     lookup takes the first match, so one duplicate is permanent: the orphan
#     shadows the tab actually being worked in, and nothing here ever closed a
#     tab. layout_tab_for_label is the tie-break, and the builders refuse to add
#     to the pile.
#
# `layout.apply` is the socket method that looks made for this job and is not:
# it replaces the tab it is handed. A request naming an existing `tab_id` and an
# existing `pane_id` came back with a new tab holding new panes, and the old tab
# and its panes were gone -- the `pane_id` was ignored, not adopted. Applying a
# layout that way would kill the agent every time. `pane split` and `pane move`
# are the calls that preserve a process, so both layouts are built from those
# and `layout.apply` is used by neither.
#
# Sourced, not run. Callers: layout.sh, layout-split.sh, layout-toggle.sh,
# focus-tab.sh.

# Resolved from this file rather than from the caller's $0, so a script can
# source it before working out anything else about itself.
layout_common_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=agent-finished.sh
. "$layout_common_dir/agent-finished.sh"

# A split's `ratio` is always the share of its first child, so all three numbers
# below describe the pane that comes first: the left column for the vertical
# split, the upper pane for the stacked one.
#
# LAYOUT_MAIN_RATIO is the width the agent keeps whichever pane you are working
# in; nothing toggles it. The other two are the two states of the stacked
# column -- the editor holding it, or the terminal holding it.
LAYOUT_MAIN_RATIO=0.33
LAYOUT_EDITOR_RATIO=0.85
LAYOUT_TERMINAL_RATIO=0.3

# The agent kinds a checkout can hold, and the label an agent's slot carries.
#
# The label IS the kind. It is what the tab bar shows, what every lookup here
# matches exactly, and what agent_command turns back into a command line, so
# nothing has to keep a slot-to-agent map in step. herdr persists a tab's
# custom_name in session.json, which makes the set of agents in a checkout
# durable across a server restart without any state of ours.
#
# One slot per kind, which is what keeps the label unique and every lookup an
# equality test. Two of the same agent in one checkout would need numbered slots
# and a map back to the kind, and neither exists here.
AGENT_KINDS="claude codex opencode"
AGENT_DEFAULT_KIND=claude

# What the agent's tab was called before the label became the kind. Read as an
# agent slot so a workspace laid out by an older version keeps its anchor --
# without this the layouts find no agent, build a second tab beside the running
# one, and the duplication this file exists to prevent is exactly what the
# upgrade produces. layout.sh renames it on the way through, so it survives one
# run per workspace.
AGENT_LEGACY_LABEL=main

herdr_cli() {
  "${HERDR_BIN_PATH:-herdr}" "$@"
}

# The socket methods the CLI does not expose: `layout.export`,
# `layout.set_split_ratio` and `pane.focus`. `herdr pane focus` is the
# directional one and cannot take a pane id.
herdr_request() {
  printf '%s\n' "$1" | "$layout_common_dir/herdr-request.sh"
}

target_workspace() {
  if [ -n "${1:-}" ]; then
    printf '%s\n' "$1"
    return 0
  fi
  if [ -n "${HERDR_WORKSPACE_ID:-}" ]; then
    printf '%s\n' "$HERDR_WORKSPACE_ID"
    return 0
  fi
  # herdr's PluginInvocationContext is flat: `workspace_id`, `workspace_label`,
  # `tab_id`, and no nested `workspace` object -- unlike an API response, where
  # `.result.workspace.workspace_id` is right. Reading only the nested path made
  # this fallback resolve to nothing; it went unnoticed because an action is also
  # handed HERDR_WORKSPACE_ID, which the branch above takes first. Read both, so
  # an event hook reaching here still resolves.
  printf '%s' "${HERDR_PLUGIN_CONTEXT_JSON:-}" |
    jq -r '.workspace_id // .workspace.workspace_id // empty'
}

focused_workspace() {
  herdr_cli workspace list | jq -r '[.result.workspaces[] | select(.focused) | .workspace_id] | first // empty'
}

first_tab_of() {
  herdr_cli tab list --workspace "$1" | jq -r '[.result.tabs[].tab_id] | first // empty'
}

# Every tab of that label, in tab-bar order, because there can be more than one.
tabs_by_label() {
  herdr_cli tab list --workspace "$1" |
    jq -r --arg label "$2" '.result.tabs[] | select(.label == $label) | .tab_id'
}

# The one tab of that label to act on, and empty when there is none.
#
# With duplicates present, taking the first match reuses whichever tab the
# duplication happened to leave in front -- an orphan -- and strands the pane
# being worked in, so the next run duplicates again. A tab whose pane is running
# something is the one in use; when none of them is, the first is as good as any.
layout_tab_for_label() {
  local workspace=$1 label=$2 candidates tab pane first=

  candidates=$(tabs_by_label "$workspace" "$label")
  [ -n "$candidates" ] || return 0

  while IFS= read -r tab; do
    [ -n "$tab" ] || continue
    if [ -z "$first" ]; then
      first=$tab
    fi
    pane=$(first_pane_of_tab "$workspace" "$tab")
    if [ -n "$pane" ] && ! pane_is_free "$pane"; then
      printf '%s\n' "$tab"
      return 0
    fi
  done <<<"$candidates"

  printf '%s\n' "$first"
}

first_pane_of_tab() {
  herdr_cli pane list --workspace "$1" | jq -r --arg tab "$2" '[.result.panes[] | select(.tab_id == $tab) | .pane_id] | first // empty'
}

tab_label_of() {
  herdr_cli tab list --workspace "$1" |
    jq -r --arg tab "$2" '[.result.tabs[] | select(.tab_id == $tab) | .label // ""] | first // empty'
}

# Panes carry a label of their own, set by `pane rename` and reported by both
# `pane list` and `layout.export`. The split layout names its three panes after
# the tabs the default layout would have given them, which is what lets
# focus-tab.sh answer the same key in either layout.
pane_by_label() {
  herdr_cli pane list --workspace "$1" |
    jq -r --arg tab "$2" --arg label "$3" \
      '[.result.panes[] | select(.tab_id == $tab and .label == $label) | .pane_id] | first // empty'
}

# The pane id alone, for a caller that does not need the tab.
workspace_pane_by_label() {
  herdr_cli pane list --workspace "$1" |
    jq -r --arg label "$2" '[.result.panes[] | select(.label == $label) | .pane_id] | first // empty'
}

# A labelled pane anywhere in the workspace, as `<tab id> <pane id>`.
labelled_pane_of() {
  herdr_cli pane list --workspace "$1" |
    jq -r --arg label "$2" \
      '[.result.panes[] | select(.label == $label) | "\(.tab_id) \(.pane_id)"] | first // empty'
}

# The agent's pane, by label first and by position only as a fallback. The
# split layout labels all three, and `pane list` order is not a promise, so
# asking for the label is what keeps "run the agent here" pointed at the agent.
#
# $3 is the slot's own label, because that is now the agent's kind rather than
# the constant `main`.
main_pane_of_tab() {
  local pane
  pane=$(pane_by_label "$1" "$2" "$3")
  if [ -z "$pane" ]; then
    pane=$(first_pane_of_tab "$1" "$2")
  fi
  printf '%s\n' "$pane"
}

# Is this label an agent slot? The legacy name answers yes so a workspace laid
# out before the rename keeps its anchor.
agent_label_is_slot() {
  case " $AGENT_KINDS $AGENT_LEGACY_LABEL " in
  *" $1 "*) return 0 ;;
  esac
  return 1
}

# Every agent tab of the workspace, in tab-bar order, and every agent pane of it
# for the split layout. Both are lists: a checkout holds as many agents as it
# has been given, and the first is the primary slot the layouts build around.
agent_tabs_of() {
  herdr_cli tab list --workspace "$1" |
    jq -r --arg slots "$AGENT_KINDS $AGENT_LEGACY_LABEL" \
      '($slots | split(" ")) as $known
       | .result.tabs[] | select(.label as $l | $known | index($l)) | .tab_id'
}

agent_panes_of() {
  herdr_cli pane list --workspace "$1" |
    jq -r --arg slots "$AGENT_KINDS $AGENT_LEGACY_LABEL" \
      '($slots | split(" ")) as $known
       | .result.panes[] | select(.label as $l | $known | index($l))
       | "\(.tab_id) \(.pane_id) \(.label)"'
}

# Every agent slot of the workspace, in tab-bar order, as
# `<tab id>\t<pane id or empty>\t<label>`.
#
# One list covering both layouts, because prefix+m has to reach every agent
# under either: the split layout's agent is a PANE inside the `dev` tab, the
# default layout's is a TAB, and a split workspace with a second agent has one
# of each. A tab holding an agent pane is reported through that pane, so no slot
# appears twice.
#
# Two reads, joined here rather than one read per tab: the picker's own budget
# is the reason this file asks herdr as little as it does.
agent_slots_of() {
  jq -rn \
    --argjson tabs "$(herdr_cli tab list --workspace "$1")" \
    --argjson panes "$(herdr_cli pane list --workspace "$1")" \
    --arg slots "$AGENT_KINDS $AGENT_LEGACY_LABEL" '
      ($slots | split(" ")) as $known
      | ($panes.result.panes | map(select(.label as $l | $known | index($l)))) as $agent_panes
      | $tabs.result.tabs[]
      | . as $t
      | ($agent_panes | map(select(.tab_id == $t.tab_id)) | first) as $p
      | if $p != null then [$t.tab_id, $p.pane_id, $p.label]
        elif ($known | index($t.label // "")) != null then [$t.tab_id, "", $t.label]
        else empty end
      | @tsv'
}

# What herdr says is running in a pane, which is how a slot built before this
# existed learns its own kind. Empty when the pane holds no agent -- the agent
# quit, or it never was one.
pane_agent_of() {
  herdr_cli pane get "$1" | jq -r '.result.pane.agent // empty'
}

# The kind of an existing agent slot: what herdr reports in it, falling back to
# the label when the pane is empty, and to the default when the label is the
# legacy one and so says nothing about which agent it held.
agent_kind_of() {
  local label=$1 pane=${2:-} kind=
  if [ -n "$pane" ]; then
    kind=$(pane_agent_of "$pane")
  fi
  if [ -n "$kind" ] && agent_label_is_slot "$kind" && [ "$kind" != "$AGENT_LEGACY_LABEL" ]; then
    printf '%s\n' "$kind"
    return 0
  fi
  if [ "$label" != "$AGENT_LEGACY_LABEL" ] && agent_label_is_slot "$label"; then
    printf '%s\n' "$label"
    return 0
  fi
  printf '%s\n' "$AGENT_DEFAULT_KIND"
}

# Take over a tab running an agent under one of the layout's other names.
#
# Starting a second agent by hand in the `term` tab is how one got into a
# checkout before there was a key for it, and the tab kept the terminal's name.
# The split layout then adopted it as the terminal and folded a live agent into
# the sliver under the editor, and the default layout left it for prefix+t to
# land in. Renaming the tab to the agent it actually runs makes it an agent slot
# instead, and the layouts build the missing terminal beside it.
#
# Only `nvim` and `term` are claimed, and only when herdr reports an agent in
# them. An unlabelled tab is left alone: a tab opened by hand is not a slot
# until something names it.
claim_agent_tabs() {
  local workspace=$1 label tab pane agent
  for label in nvim term; do
    while IFS= read -r tab; do
      [ -n "$tab" ] || continue
      pane=$(first_pane_of_tab "$workspace" "$tab")
      [ -n "$pane" ] || continue
      agent=$(pane_agent_of "$pane")
      [ -n "$agent" ] || continue
      [ "$agent" != "$AGENT_LEGACY_LABEL" ] || continue
      agent_label_is_slot "$agent" || continue
      herdr_cli tab rename "$tab" "$agent" >/dev/null
    done < <(tabs_by_label "$workspace" "$label")
  done
}

# Rename a tab still called `main` to the agent herdr reports running in it.
#
# The same migration layout.sh performs on its way through, reachable without a
# layout run, because a workspace restored from session.json keeps the legacy
# label until something lays it out again -- and until then the tab bar names
# the slot after a word that is not an agent, prefix+m cannot find it, and
# agent-add offers a second claude beside the one already running.
#
# Only when herdr reports an agent in the tab. An empty legacy tab keeps the
# name: the kind it last held is not recorded anywhere, and guessing it here
# would write the default over a codex slot whose agent had merely exited.
claim_legacy_agent_tabs() {
  local workspace=$1 tab kind
  while IFS=$'\t' read -r tab kind; do
    [ -n "$tab" ] || continue
    herdr_cli tab rename "$tab" "$kind" >/dev/null
  done < <(
    jq -rn \
      --argjson tabs "$(herdr_cli tab list --workspace "$workspace")" \
      --argjson panes "$(herdr_cli pane list --workspace "$workspace")" \
      --arg kinds "$AGENT_KINDS" \
      --arg legacy "$AGENT_LEGACY_LABEL" '
        ($kinds | split(" ")) as $known
        | ( [ $tabs.result.tabs[].label // empty ]
            + [ $panes.result.panes[].label // empty ] | unique ) as $taken
        | ( $panes.result.panes
            | map(select(.agent != null and (.agent | IN($known[]))))
            | group_by(.tab_id)
            | map({ key: .[0].tab_id, value: .[0].agent })
            | from_entries ) as $tab_agent
        | [ $tabs.result.tabs[]
            | select(.label == $legacy)
            | select($tab_agent[.tab_id] != null)
            | select($tab_agent[.tab_id] | IN($taken[]) | not)
            | { tab: .tab_id, kind: $tab_agent[.tab_id] } ]
        # One rename per kind per run. herdr accepts two tabs under one name and
        # a workspace can hold two legacy tabs, and renaming both would answer
        # every later lookup with whichever came first, for good.
        | unique_by(.kind)
        | .[]
        | [.tab, .kind]
        | @tsv'
  )
}

# Give an agent sharing a tab with another agent a tab of its own.
#
# A slot is a tab labelled with its kind, and the label is the whole record --
# so an agent started into a split of another agent's tab is not a slot at all:
# prefix+m steps past it, agent-add offers its kind again, and the layouts fold
# it into whatever they think that tab is. It is also invisible, which is the
# half you notice: the tab bar names one agent and two are running.
#
# Only a tab that is already an agent slot -- one named after a kind, or the
# legacy `main`. The split layout keeps all three roles as panes of a tab called
# `dev`, and a restored session has no pane labels at all, so reaching in there
# would move the editor or the shell out of a workspace that nothing is about to
# rebuild.
#
# The tab keeps exactly one, and the rest leave. Which one stays is decided in
# this order: the pane whose kind the TAB is named after; then a pane already
# labelled with a kind, which is how the split layout marks its agent; then the
# first. Run after claim_legacy_agent_tabs, or the first rule cannot fire on a
# workspace that still says `main`.
#
# A kind already spoken for elsewhere in the workspace is left where it is. One
# slot per kind is what keeps every lookup an equality test, and a second tab
# under a name that already exists would make both of them ambiguous rather
# than making this one visible.
claim_agent_panes() {
  local workspace=$1 pane kind
  while IFS=$'\t' read -r pane kind; do
    [ -n "$pane" ] || continue
    # A zoomed tab refuses the move, and answers the refusal as a success with
    # `changed:false`, which pane_move_new_tab reports by having no created tab.
    # Zoom is a view of one pane; it is given up only when it is what stands
    # between a running agent and a tab of its own.
    if ! pane_move_new_tab "$pane" "$kind" >/dev/null; then
      tab_unzoom "$pane"
      pane_move_new_tab "$pane" "$kind" >/dev/null || continue
    fi
    # The new tab carries the name now, so the pane gives its own up -- the same
    # trade tab_out makes. A pane that kept a role label it no longer fills is
    # how the split layout ends up with two panes called `term`: the label
    # outlives the pane it named, and every lookup for that role finds an agent.
    pane_rename "$pane" "" || true
  done < <(
    jq -rn \
      --argjson tabs "$(herdr_cli tab list --workspace "$workspace")" \
      --argjson panes "$(herdr_cli pane list --workspace "$workspace")" \
      --arg kinds "$AGENT_KINDS" \
      --arg legacy "$AGENT_LEGACY_LABEL" '
        ($kinds | split(" ")) as $known
        | ($known + [$legacy]) as $slot_labels
        | ( $tabs.result.tabs
            | map({ key: .tab_id, value: (.label // "") })
            | from_entries ) as $tab_label
        | ( [ $tabs.result.tabs[].label // empty ]
            + [ $panes.result.panes[].label // empty ] | unique ) as $taken
        # Only a tab that is already an agent slot. The split layout keeps the
        # agent, the editor and the shell as PANES of a tab it calls `dev`, and
        # a restored session has no pane labels at all -- session.json persists
        # a tab custom_name but of a pane only cwd and agent session. Reaching
        # into `dev` here would take the editor or the shell away from a
        # workspace, and only a layout run builds a missing role back.
        | ( $tabs.result.tabs
            | map(select((.label // "") | IN($slot_labels[])) | .tab_id) ) as $agent_tabs
        | $panes.result.panes
        | map(select(.agent != null
                     and (.agent | IN($known[]))
                     and (.tab_id | IN($agent_tabs[]))))
        | group_by(.tab_id)
        | map(select(length > 1))
        | map(
            . as $group
            | ( [ $group[] | select(.agent == $tab_label[.tab_id]) ] | first ) as $named
            | ( [ $group[] | select(.label != null and (.label | IN($known[]))) ] | first ) as $labelled
            | (($named // $labelled // $group[0]).pane_id) as $keeper
            | $group | map(select(.pane_id != $keeper)))
        | flatten
        | map(select(.agent | IN($taken[]) | not))
        # One tab per kind per run: $taken is the state before the first move,
        # so two panes of one kind would otherwise each be given a tab under the
        # same name, and the second would be invisible from then on.
        | unique_by(.agent)
        | .[]
        | [.pane_id, .agent]
        | @tsv'
  )
}

# The tab the primary agent lives in, as `<tab id> <label>`, and empty when the
# workspace has lost it.
#
# Both layouts mark it: the default one names the TAB after the agent, the split
# one names the PANE after it inside the tab it calls `dev`. A workspace carrying
# neither mark has never been laid out, and there the first tab IS the agent's,
# because it is the tab the layout is about to be built around.
#
# The label comes back with the tab because it is the agent's kind, and every
# caller needs it to know what to run there.
agent_tab_of() {
  local workspace=$1 located tab label pane first='' first_label=''

  located=$(agent_panes_of "$workspace" | head -1)
  if [ -n "$located" ]; then
    read -r tab pane label <<<"$located"
    printf '%s %s\n' "$tab" "$label"
    return 0
  fi

  # Same tie-break layout_tab_for_label applies to one label, across the agent
  # tabs: a tab whose pane is running something is the one in use, and with
  # duplicates present taking the first would strand it.
  while IFS= read -r tab; do
    [ -n "$tab" ] || continue
    label=$(tab_label_of "$workspace" "$tab")
    if [ -z "$first" ]; then
      first=$tab
      first_label=$label
    fi
    pane=$(first_pane_of_tab "$workspace" "$tab")
    if [ -n "$pane" ] && ! pane_is_free "$pane"; then
      printf '%s %s\n' "$tab" "$label"
      return 0
    fi
  done < <(agent_tabs_of "$workspace")

  if [ -n "$first" ]; then
    printf '%s %s\n' "$first" "$first_label"
    return 0
  fi

  # Marks of a layout, but no agent among them: answer empty, so the caller
  # builds the agent a tab instead of renaming the editor's.
  #
  # Both sets of marks are asked for. The default layout's are tabs called
  # `nvim` and `term`; the split layout's are PANES of those names, in a tab
  # called `dev`. Asking only about tabs missed the split layout entirely, and a
  # split workspace whose agent pane had exited fell through to the first tab --
  # which is the `dev` tab, whose first pane is the editor.
  if [ -n "$(layout_tab_for_label "$workspace" nvim)" ] ||
    [ -n "$(layout_tab_for_label "$workspace" term)" ] ||
    [ -n "$(workspace_pane_by_label "$workspace" nvim)" ] ||
    [ -n "$(workspace_pane_by_label "$workspace" term)" ]; then
    return 0
  fi

  # Never laid out: the first tab is the agent's, and it carries no label yet.
  # The empty second field is what tells the caller to work the kind out from
  # whatever is running in it.
  tab=$(first_tab_of "$workspace")
  [ -n "$tab" ] || return 0
  printf '%s \n' "$tab"
}

pane_rename() {
  herdr_cli pane rename "$1" "$2" >/dev/null
}

pane_focus() {
  herdr_request "$(jq -cn --arg pane "$1" '{id: "focus", method: "pane.focus", params: {pane_id: $pane}}')" >/dev/null
}

pane_cwd() {
  herdr_cli pane get "$1" | jq -r '.result.pane.cwd // empty'
}

# Any pane's cwd, for a tab that has to be built when no agent pane is left to
# ask. Every pane of a workspace is in the same checkout, so any of them answers.
workspace_cwd() {
  herdr_cli pane list --workspace "$1" | jq -r '[.result.panes[].cwd] | map(select(. != null)) | first // empty'
}

# Drop a tab's zoom before moving panes in or out of it. A zoomed tab refuses
# every `pane move`, and refuses it as a success, so the refusal used to reach
# the caller as an adoption. Zoom is view state and the layout keys are entitled
# to drop it; a half-applied layout is not something they are entitled to leave.
# The pane names the tab, and asking to unzoom one that is not zoomed is a
# no-op.
tab_unzoom() {
  [ -n "${1:-}" ] || return 0
  herdr_cli pane zoom --pane "$1" --off >/dev/null 2>&1 || true
}

# `pane move` answers a refusal with a SUCCESS response: `changed` is false and
# `reason` is `same_tab` or `zoomed_tab`, while `pane` -- required on every
# answer -- still reports the pane's unchanged tab. Reading the tab id from
# there made a zoomed pane rename the tab everything was still sitting in.
# `created_tab` is the field that stays null unless a tab was really made.
# The tab is born with its name: `--label` on the move is what herdr offers, and
# it leaves no window in which a tab exists under a number that a lookup could
# find first.
pane_move_new_tab() {
  local response tab
  response=$(herdr_cli pane move "$1" --new-tab --label "$2" 2>/dev/null) || return 1
  tab=$(printf '%s' "$response" | jq -r '.result.move_result.created_tab.tab_id // empty')
  [ -n "$tab" ] || return 1
  printf '%s\n' "$tab"
}

# The same refusal, moving into a tab that already exists. `changed` is the only
# field that says whether anything happened. `--tab` is not accepted without a
# `--split`, so the direction and ratio are not optional; `--target-pane` is,
# and without it herdr picks the pane to split.
pane_move_into_tab() {
  local pane=$1 tab=$2 direction=$3 ratio=$4 target=${5:-} response
  local -a target_arg=()
  if [ -n "$target" ]; then
    target_arg=(--target-pane "$target")
  fi
  response=$(herdr_cli pane move "$pane" --tab "$tab" "${target_arg[@]}" \
    --split "$direction" --ratio "$ratio" 2>/dev/null) || return 1
  printf '%s' "$response" | jq -e '.result.move_result.changed == true' >/dev/null 2>&1
}

# Take the name off a tab the layout no longer owns.
#
# A tab the user had split further does not close itself when the layout moves
# its first pane out, and it kept the label while the pane it named had left. On
# the way back the layout would then find a tab called `nvim` holding a shell,
# reuse it, and leave the editor to be found by nothing -- or build a second one
# beside it. herdr has no null label, so this is the empty string, which the
# tab bar shows as the tab's number and no lookup here matches.
tab_clear_label() {
  herdr_cli tab rename "$1" "" >/dev/null 2>&1 || true
}

# Build the agent a tab of its own, as `<tab id> <pane id>`.
create_agent_tab() {
  herdr_cli tab create --workspace "$1" --label "$3" --cwd "$2" --no-focus |
    jq -r 'select(.result.tab.tab_id and .result.root_pane.pane_id) |
      "\(.result.tab.tab_id) \(.result.root_pane.pane_id)"'
}

# Where a layout starts from: the primary agent's tab, its pane, which agent it
# is, and the directory to work in, as `<tab id> <pane id> <kind> <cwd>`. Empty
# when the workspace holds no pane at all to read a directory from.
#
# The kind comes before the cwd so the cwd stays the trailing field: a caller
# reads all four with one `read -r`, and a directory containing a space still
# arrives whole.
#
# The caller's own second argument wins for the directory: worktree-create.sh
# and workstation-dev both know the checkout before any of these panes exist.
#
# A workspace that has lost the agent's tab -- the agent quit, then the shell
# exited, so herdr closed the pane and the tab with it -- gets a new one here,
# for the agent it last held rather than for the default one. Both layouts used
# to take the first tab instead, which handed the agent's slot to Neovim and
# started a second editor beside it.
layout_anchor() {
  local workspace=$1 explicit=${2:-} located tab label pane kind cwd

  located=$(agent_tab_of "$workspace")
  tab=
  label=
  if [ -n "$located" ]; then
    read -r tab label <<<"$located"
  fi

  pane=
  if [ -n "$tab" ]; then
    pane=$(main_pane_of_tab "$workspace" "$tab" "$label")
  fi
  kind=$(agent_kind_of "$label" "$pane")

  cwd=$explicit
  if [ -z "$cwd" ] && [ -n "$pane" ]; then
    cwd=$(pane_cwd "$pane")
  fi
  if [ -z "$cwd" ]; then
    cwd=$(workspace_cwd "$workspace")
  fi
  [ -n "$cwd" ] || return 1

  if [ -z "$pane" ]; then
    read -r tab pane <<<"$(create_agent_tab "$workspace" "$cwd" "$kind")"
    [ -n "$pane" ] || return 1
  fi

  printf '%s %s %s %s\n' "$tab" "$pane" "$kind" "$cwd"
}

# Whether the pane is idle, asked as "is the shell itself the foreground process
# group". Matching process names instead is what the upstream probe did through a
# field herdr 0.8.2 does not return (`argv0`, so `test` hit null and jq aborted
# and every pane read as busy), and repairing that to `name` only traded one
# failure for a flakier one: fish runs `direnv hook fish` while it starts, and a
# probe landing in that window saw a non-shell name and skipped the agent in
# roughly half of cold picks. The transient is a child of the shell's own process
# group, so this comparison rides through it, and it needs no list of shell or
# helper names to stay correct.
pane_is_free() {
  herdr_cli pane process-info --pane "$1" |
    jq -e '.result.process_info | .foreground_process_group_id == .shell_pid' >/dev/null 2>&1
}

# `dev nvim` runs Neovim inside the project's Dev Container so LSP and parsers
# see the project's real dependencies; it exits 1 with a message when the tree
# has no .devcontainer, so pick the editor command per project rather than
# leaving that pane showing an error.
editor_command() {
  # Two `local` assignments, not one: bash expands every word before the
  # builtin runs, so `local dir=$1 probe=$dir` reads the caller's unset `dir`
  # and `set -u` aborts the function.
  local dir=$1
  local probe=$dir
  local root
  root=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null || true)
  while :; do
    if [ -f "$probe/.devcontainer/devcontainer.json" ] || [ -f "$probe/.devcontainer.json" ]; then
      printf 'dev nvim\n'
      return 0
    fi
    # -ef, not =: /home is a symlink to /var/home, so the caller's path and the
    # physical one git reports never compare equal as strings and the walk would
    # run past the repository into ~ and /.
    [ "$probe" -ef "${root:-/}" ] && break
    [ "$probe" = / ] && break
    probe=$(dirname "$probe")
  done
  printf 'nvim\n'
}

# What to run in an agent's pane. A checkout where THIS agent has finished a
# turn reopens on the conversation it left; one where it has not starts clean,
# because there is nothing to resume and the resume flag would fail the pane
# into a bare shell.
#
# All three resume from the directory they are started in: `claude --continue`
# is scoped to the current directory, and `codex resume --last` filters by cwd
# unless `--all` is passed, which is why neither needs a session id here. The
# stamp answers only whether there is anything to resume, and it is keyed per
# agent for exactly this: keyed on the checkout alone, a codex finish put
# `claude --continue` into a checkout claude had never run in.
#
# opencode is the exception and always starts clean. It keeps every session in
# one SQLite database rather than per project, and whether its `--continue` is
# scoped to the directory is not established here -- resuming another checkout's
# conversation is a worse failure than starting a new one.
#
# The stamp is read as a fact, not as a clock: no age window closes a
# conversation. herdr restores the exact conversation on its own at server
# start with no age limit of its own, so a window here would only make the two
# disagree after a reboot -- and a conversation is finished when the checkout
# is removed, which is a deliberate act with its own popup.
agent_command() {
  local agent=$1 cwd=$2 resumable=no
  if agent_finished_age "$(agent_checkout_key "$cwd")" "$agent" >/dev/null; then
    resumable=yes
  fi
  case $agent in
  claude)
    if [ "$resumable" = yes ]; then printf 'claude --continue\n'; else printf 'claude\n'; fi
    ;;
  codex)
    if [ "$resumable" = yes ]; then printf 'codex resume --last\n'; else printf 'codex\n'; fi
    ;;
  opencode) printf 'opencode\n' ;;
  *) return 1 ;;
  esac
}

layout_export_tab() {
  herdr_request "$(jq -cn --arg tab "$1" '{id: "export", method: "layout.export", params: {tab_id: $tab}}')"
}

# The split a pane hangs directly off, as {path, direction, child}. `path` is the
# route from the root as a list of booleans -- false for the first child, true
# for the second -- which is the address layout.set_split_ratio takes, and the
# same convention equalize-panes.sh builds.
layout_parent_split() {
  layout_export_tab "$1" | jq -c --arg pane "$2" '
    def parent($path):
      if .type != "split" then empty
      else
        (if (.first | .type == "pane" and .pane_id == $pane)
           then {path: $path, direction: .direction, child: "first"} else empty end),
        (if (.second | .type == "pane" and .pane_id == $pane)
           then {path: $path, direction: .direction, child: "second"} else empty end),
        (.first | parent($path + [false])),
        (.second | parent($path + [true]))
      end;
    [.result.layout.root | parent([])] | first // empty'
}

# Address a split by the route layout.set_split_ratio takes.
layout_set_ratio() {
  herdr_request "$(jq -cn --arg tab "$1" --argjson path "$2" --argjson ratio "$3" \
    '{id: "ratio", method: "layout.set_split_ratio", params: {tab_id: $tab, path: $path, ratio: $ratio}}')" >/dev/null
}

# Give a pane the larger share of the column it is stacked in.
#
# Only a `down` split is touched. The vertical split is what pins the agent to
# LAYOUT_MAIN_RATIO, and it has to keep that width whichever pane you move to,
# so moving to main focuses it and resizes nothing.
layout_grow_pane() {
  local tab=$1 pane=$2 parent ratio
  parent=$(layout_parent_split "$tab" "$pane")
  [ -n "$parent" ] || return 0
  [ "$(printf '%s' "$parent" | jq -r '.direction')" = "down" ] || return 0

  if [ "$(printf '%s' "$parent" | jq -r '.child')" = "first" ]; then
    ratio=$LAYOUT_EDITOR_RATIO
  else
    ratio=$LAYOUT_TERMINAL_RATIO
  fi

  layout_set_ratio "$tab" "$(printf '%s' "$parent" | jq -c '.path')" "$ratio"
}

# Hand a role's command back to a pane that has fallen back to the shell.
#
# Focusing an agent slot or `nvim` is a request to be in that agent or in the
# editor, and a pane whose process has exited answers with a prompt instead --
# the tab is still there, still labelled, and empty. The layouts start those
# panes under exactly this rule, so the same predicate decides here: a pane
# running anything at all is left alone, and only an idle shell is started
# again. `term` is a shell by design and is never restarted.
#
# The command is worked out from the pane's own cwd, so a restarted editor still
# gets `dev nvim` in a Dev Container project and a restarted agent still resumes
# the conversation while the checkout's last finish is fresh.
relaunch_role_pane() {
  local label=$1 pane=$2 cwd command
  [ -n "$pane" ] || return 0
  if [ "$label" != nvim ] && ! agent_label_is_slot "$label"; then
    return 0
  fi
  pane_is_free "$pane" || return 0
  cwd=$(pane_cwd "$pane")
  [ -n "$cwd" ] || return 0
  if [ "$label" = nvim ]; then
    command=$(editor_command "$cwd")
  else
    # An agent slot restarts as the agent its label names. The legacy label
    # names none, so it resolves through the same rule the layouts use: what the
    # pane last held, and the default when it held nothing.
    command=$(agent_command "$(agent_kind_of "$label" "$pane")" "$cwd") || return 0
  fi
  herdr_cli pane run "$pane" "$command" >/dev/null
}
