# Agent Recency

The record for making "when did this finish?" answerable on a machine whose
terminal multiplexer does not keep the time: what the stamp is, why the space
picker hides work it has not heard from in twelve hours, and which cheaper
routes lost.

**herdr reports what an agent is doing and never when it started doing it, so
every recency question on this workstation had exactly one honest answer:
nobody knows.**

---

## Context

The space picker (`Ctrl+G` `s`) sorts by attention: a space whose agent is
`blocked` or `done` rises above one that is `working`, which rises above the
rest. That ordering is correct and it is also all there was. A conversation that
finished ninety seconds ago and one that finished last Tuesday render
identically, in the same column, at the same rank. The picker could say *this
space wants you* and could not say *this one wants you now*.

The obvious fix is a timestamp, and there is none to read:

```
$ herdr agent list | jq '.result.agents[0] | {agent_status, state_change_seq, revision}'
{ "agent_status": "working", "state_change_seq": 20, "revision": 8 }
```

`state_change_seq` is a monotonic counter, server-global. It orders two agents
against each other and says nothing about elapsed time. `herdr api snapshot`
adds no clock, and neither does the `pane_agent_status_changed` event body,
whose four required fields are `type`, `pane_id`, `workspace_id` and
`agent_status`.

So the clock had to be ours, and the only question worth arguing was where to
put it.

---

## Decision

One stamp per checkout, written when the transition happens, read by everything
that asks about recency.

`dev-flow/agent-freshness.sh` runs on `pane.agent_status_changed` and writes
`<unix seconds>\t<checkout path>` into
`~/.local/state/workstation/agent-finished/<sha1 of the path>`.
`dev-flow/agent-finished.sh` holds the paths, the two windows and the readers;
it is sourced, never run.

A finish is a **transition**, not a state, and that distinction is the whole of
the rule. herdr derives `done` rather than accepting it — `pane report-agent
--state` takes only `idle`, `working`, `blocked` and `unknown`, and no agent
manifest emits `done` — and the docs say what it derives it for: *"A done agent
stays visible until you view it."* So a turn that ends while you are **watching**
it goes `working -> idle` and never passes through `done`. Keying the stamp on
`done` alone therefore lost exactly the projects you had open when you finished
one, which is not a corner case; it is the common one.

The stamp is written on `done`, on `blocked`, and on `idle` only when the pane
was `working` a moment earlier. The last clause is load-bearing: without it,
every re-detection of a pane that has sat at its prompt for a week would reset
the clock and nothing would ever expire. The previous status per pane lives
beside the stamps, because herdr's event carries the new status and not the old.

The sidebar badge keeps the narrower rule — `done` or `blocked` only. Those are
the two states that also mean *and you have not looked yet*, and herdr clears
`done` itself the moment the pane is viewed, so a badge on `idle` would outlive
the thing it announces.

Three consumers, one clock:

| Consumer | Question | Window |
|---|---|---|
| Space picker | Is this space newly finished? | `AGENT_FRESH_SECONDS`, 10 min, rendered as `*` |
| Space picker | Has this checkout gone stale? | `AGENT_EXPIRED_SECONDS`, 12 h, row hidden |
| `claude_command`, in `layout-common.sh` | Resume the conversation or start clean? | `AGENT_EXPIRED_SECONDS` |

The third row is one consumer with two callers: `layout.sh` and
`layout-split.sh` both start the agent through `claude_command`, which is why it
lives in the file they share rather than in either of them.

The stamp is keyed by **checkout path**, not by workspace id. A workspace id
dies when the space is closed, and the case the twelve-hour window exists for is
precisely a checkout that outlived its space.

The words and colours are herdr's, not ours. The picker reads the rollup herdr
already computes per space, `.agent_status` on `workspace list`, and prints it
in herdr's own vocabulary -- `blocked`, `done`, `working`, `idle` -- coloured
red, green, yellow and dim. It had been folding the agent list itself and
collapsing blocked and done into one invented word, `action`, which meant the
picker and the sidebar could describe the same space differently. `unknown` is
herdr for "no agent here" and stays blank, because it is most rows.

The sidebar badge is deliberately *not* the stamp. It is a herdr workspace
token, `fresh=new`, published with `--ttl-ms 600000`, so herdr expires it and
nothing on this machine has to sweep it or recompute it on a timer. The stamp
cannot serve the sidebar because the sidebar renders from herdr's own state; the
token cannot serve the picker because a closed space has no workspace to carry
one. Two surfaces, two mechanisms, one event that writes both.

---

## What Lost

**A seen-watermark instead of a clock.** Record the `state_change_seq` the
picker last displayed, mark anything above it as new. No daemon, no clock, never
wrong. It answers a different question: *unseen since you last looked*, which
marks a Tuesday conversation as new on Friday because you never opened the
picker in between. The question actually being asked was temporal.

**Polling for the timestamp.** A loop that samples `agent list` and stamps
transitions it notices. It only knows what it was awake for, and the sampling
interval becomes the resolution of every window downstream. The event hook is
exact and costs nothing between transitions.

**A long-lived subscriber on `events.subscribe`.** Correct, and a daemon to
supervise, reconnect and ship. The plugin event hook is a process per
transition, which is a handful per hour.

**Expiring open spaces too.** A uniform rule, and it would hide a space that is
open in the sidebar while you look at it. Only the synthesised rows — a checkout
on disk with no space of its own — can expire.

---

## The Refresh Loop

Hiding stale rows made the picker's other flaw louder: it was a snapshot. You
opened it, read it, closed it, and opened it again to find out whether anything
had moved.

fzf has no timer binding, so the refresh comes from outside it. `spaces.sh`
starts fzf with `--listen=$XDG_RUNTIME_DIR/herdr-spaces-<pid>.sock` and a
background loop that rebuilds the rows every two seconds, compares them to what
is on screen, and pushes `reload(... {q})` through that socket only when they
differ. Nothing redraws while you read an unchanged list, and the query and
cursor survive because the reload carries `{q}` and the existing
`load:transform` restores the row.

What is rebuilt matters. A full row build is three socket calls plus a
`git worktree list` per repository; the git scan is the slow half and its answer
changes only when a checkout appears or goes, so it is memoised in a topology
file for the life of the picker. `Ctrl+R` throws that away and rescans. Measured
cold, with the scan: 131 ms.

The socket lives in `$XDG_RUNTIME_DIR`, which is `0700`. That, and not an API
key, is what keeps the action channel to one user — a listening fzf will run any
action posted to it.

---

## Shipping

The same keystroke argument settled `Ctrl+G` `Shift+M`. `/worktree-push` commits
outstanding work, syncs the base branch, opens the PR and merges it, and two of
those four need judgement that a shell script does not have: a commit message,
and a conflict.

The popup takes the other two. It refuses on a dirty tree rather than inventing
a commit, pushes, opens the PR with `gh pr create --fill`, and arms
`gh pr merge --auto --squash` so GitHub merges when the checks pass rather than
when the popup felt like it. It never deletes a branch; `/worktree-remove` owns
that, because it is the one that checks whether the merge landed.

It prints the active `gh` account in the status block on purpose. Pushes go out
as gh's *active* account rather than the repository's owner, and the mismatch
surfaces as a 403 that names neither.

`allow_auto_merge` is off on this repository, so the auto-merge call fails here
and the popup falls through to an explicit `[m] merge now`, printing the one
command that would enable it. That is the intended shape: the popup says what
GitHub refused instead of quietly doing the more dangerous thing.

---

## Where to go next

[../keybindings.md](../keybindings.md) has the keys,
[../subsystems/](../subsystems/) the surrounding machinery, and
`AGENTS.md` the invariant that keeps this to one clock.
