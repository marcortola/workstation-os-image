# Multi-Agent Checkouts

The record for running claude, codex and opencode side by side in one checkout:
why the slot is named after the agent rather than numbered, why the recency
stamp had to grow a second key, and which surfaces deliberately did not change.

**The tab label IS the agent's kind. It is the only record of which agents a
checkout holds, and herdr persists it, so nothing here keeps state of its own.**

---

## Context

Everything in `dev.flow` assumed one agent per checkout. The layouts built a tab
called `main`, `claude_command` emitted the literal string `claude`, and the
recency stamp that decides whether to resume a conversation was keyed on the
checkout path alone.

The workstation had already outgrown that by hand. herdr 0.8.2 detects claude,
codex and opencode as first-class agents — `herdr agent explain` names the
manifest and the rule that fired — and a live workspace was running claude in the
`main` tab and codex in the `term` tab of the same checkout. The intended shape
is one agent implementing and another reviewing the implementation.

Three things broke under that, all silently:

- **The wrong agent came back.** Every path that restarts an exited agent pane
  ran `claude`, whatever had been there. Worse, the stamp was agent-blind, so a
  codex finish made the next run answer `claude --continue` in a checkout claude
  had never run in. `--continue` with no conversation fails the pane into a bare
  shell.
- **The split layout ate the second agent.** `prefix+shift+n` resolves its
  terminal slot by tab label and takes that tab's first pane. With codex sitting
  in the tab called `term`, the layout folded a live agent into the 15% sliver
  under the editor and left the workspace with no shell.
- **One key reached one agent.** `prefix+m` asked for the label `main`. Nothing
  reached a second agent except `prefix+a`, the agent picker, which lists panes
  rather than slots.

---

## The Decision

A checkout holds at most one agent of each kind, each in a tab labelled with the
agent's own name: `claude`, `codex`, `opencode`.

### Why the label, and not a number

`agent 1` / `agent 2` was the obvious shape and is worse on every axis that
matters here.

The label would have to carry the kind anyway — the whole point is to see which
agent is which in the tab bar — so it becomes `agent1 (claude)`: a *mutable*
label. Every lookup in `layout-common.sh` is an exact-match jq select
(`select(.label == $label)`, and three more like it), and the layouts' whole
convergence property rests on that equality: a second run must find what the
first built. Prefix matching in six places, plus re-parsing the kind back out of
the label on every relaunch, buys nothing that the kind alone does not give.

Naming the slot after the kind makes the label unique, keeps every lookup an
equality test, and makes the label *self-describing*: `agent_command` turns it
straight back into a command line, so no slot-to-agent map exists to fall out of
step.

The cost is that two claudes in one checkout are not expressible. That was
explicitly not wanted.

### Why the tab, and not the pane

herdr's `session.json` persists a tab's `custom_name` and, of a pane, only its
cwd and agent session. A tab label therefore survives a server restart and a
reboot; a pane label does not. Since the label is the only record of which agents
a checkout holds, it has to live where it survives — so the set of agents is
durable with no state file, no marker, and nothing to reconcile.

It also means `herdr tab list` already answers "what state is each agent in":
one agent per tab, and herdr rolls `agent_status` up per tab as well as per
workspace.

### Why further agents stay out of both layouts

Both dev layouts are about the primary agent, the editor and the shell. The split
tab is a three-pane tree with three ratio constants; a fourth pane leaves every
one of them too narrow to read. Extra agents are tabs neither layout touches,
which is also what lets a second agent survive `prefix+shift+n` untouched.

---

## What Changed

| Piece | Before | After |
|---|---|---|
| Agent slot | tab or pane called `main` | tab or pane called `claude` / `codex` / `opencode` |
| Command | `claude_command <cwd>` | `agent_command <kind> <cwd>` |
| Resume | `claude --continue` | per kind: `claude --continue`, `codex resume --last`, opencode always clean |
| Stamp key | checkout | checkout **and** agent |
| Parked marker | 5 columns | 6, the last one the agent |
| `prefix+m` | focus the tab called `main` | focus the next agent slot, wrapping |
| `prefix+alt+o` | bare `opencode` pane | *gone* — `prefix+alt+a` adds any agent as a tab |

`agent_command` is deliberately the only thing that turns a kind into a command
line, and a gate fails the build if `claude_command` reappears anywhere in the
plugin.

### Resume is per agent, per directory

All three CLIs resume from the directory they start in: `claude --continue` is
scoped to the current directory, and `codex resume --last` filters by cwd unless
`--all` is passed. So the stamp only has to answer *whether* there is anything to
resume, which is exactly what keying it on the checkout and the agent gives.

opencode is the exception and always starts clean. It keeps every session in one
SQLite database rather than per project, and whether its `--continue` is scoped
to the directory is not established here. Resuming another checkout's
conversation is a worse failure than starting a new one, so it is not attempted.

### The two migrations

Both are self-healing and neither needs a script.

A tab still labelled `main` is read as an agent slot — without that, an upgraded
workspace finds no agent and builds a *second* agent tab beside the running one,
which is the exact duplication `layout-common.sh` exists to prevent. `layout.sh`
renames it to whatever herdr reports running in it, so the legacy label survives
one run per workspace.

A stamp file written before the key grew its agent half is named after the
checkout alone. It is read as claude's, in both the map and the direct lookup —
the two have to agree, or the picker marks a checkout as just finished while the
layout starts the agent clean. claude is the only command either layout ever ran,
so all but a hand-started agent's finishes were its. The wrong attribution it can
still make — a checkout where only a hand-started codex ever finished — is the
behaviour that checkout already had, and it lasts until that agent's next finish
rather than for good.

### `claim_agent_tabs`

Starting an agent by hand in the `term` tab is how a second agent got into a
checkout before there was a key for it, and the tab kept the terminal's name.
Before either layout resolves anything, a tab labelled `nvim` or `term` whose
pane herdr reports as an agent is renamed to that agent — it becomes a proper
slot, and the layout builds the missing terminal beside it. `adopt_tab_pane`
carries the same refusal as a second line of defence, for a pane labelled by hand
or an agent started since the claim ran.

Only `nvim` and `term` are claimed. An unlabelled tab is left alone: a tab opened
by hand is not a slot until something names it.

---

## What Did Not Change

The space picker (`prefix+s`) and the DMS bar widget still render one row per
checkout, carrying herdr's own rollup of the agents in it. Two agents in one
checkout collapse into one state word, and the row's just-finished mark takes the
newest of that checkout's stamps.

That is a deliberate stopping point, not an oversight. Making rows per-agent
re-keys `is_parked` off the workspace, re-keys the sidebar `fresh` token, gives
`focus-space.sh` a pane target and re-counts the widget pill — and the per-agent
view already exists on `prefix+a`, which has always listed one row per pane,
blocked first. Duplicating it in the space picker buys a second way to ask the
same question.

Parked-work detection also did not change. `tooling/data/agent-probe-registry`
already records why codex and opencode have no probe, and an agent without one is
never parked and behaves as it did before probes existed.

---

## Gates

`tooling/validate/sources` fails on each of these, all verified by breaking them:

- a kind in `AGENT_KINDS` with no arm in `agent_command` — a tab that gets
  created and then handed nothing
- `claude_command` reappearing anywhere in the plugin
- either layout no longer calling `claim_agent_tabs`
- the freshness hook or the picker sweep writing a stamp without the agent
- `prefix+m` pointing back at a label instead of `agent`
- any script in the plugin directory without a manifest entry
