# Agent parked-work probes

The seam ships from `system_files/usr/libexec/workstation-agent-probes/` and lands
at `/usr/libexec/workstation-agent-probes/`.

A checkout is **parked** when its agent's foreground turn is over and background
work that turn started is still running. herdr calls that pane `idle`, on
purpose: `herdrdev/herdr#3468` removed the rule that reported a live background
shell as `working`, and added a regression test asserting `idle`. herdr answers
"is there a foreground turn"; this answers "is there work".

The distinction is not cosmetic. `dev-flow/agent-freshness.sh` stamps a checkout
finished on a `working -> idle` transition, and a turn that ends with a
background task alive takes exactly that transition, so the picker's
just-finished mark and the sidebar badge fire before the work is done.

## Contract

A probe is an executable named after the label herdr reports in `.agent`. It
reads a JSON array of pane objects on stdin -- every pane whose `.agent` matches
its own filename -- and prints a JSON array of the `pane_id`s that are parked.

No arguments. No writes. No side effects. Non-zero exit, a timeout past two
seconds, or output that is not an array of strings is read as "not parked".

An agent with no probe is never parked, and behaves exactly as it did before
probes existed. Adding one is: this file, an executable here, and a line in
`tooling/data/agent-probe-registry`. Nothing else changes.

## Why there is no generic probe

There was a candidate -- "the agent is idle and owns a live session-leader
descendant" -- and it is false. Measured on this workstation: a pane mid-turn
reads `agent_status=idle` with one session leader for the whole span of a
foreground tool call, 13 of 13 samples over 39s. A foreground tool call and a
background shell are the same process shape. Do not rebuild this.

## claude (Claude Code)

Signal: `~/.claude/sessions/<pid>.json`, `.status` over
`busy | shell | idle | waiting`. `shell` means the turn ended and a background
`local_bash` task is alive. Joined to the pane by `.sessionId` against herdr's
`agent_session.value`, which the Claude integration already reports through
`pane.report_agent_session`.

Believed only while `.procStart` still equals field 22 of `/proc/<pid>/stat`,
since a session file outlives a crashed session and pids are reused. `waiting`
is not treated as parked: it has never been observed here and a guess would be
indistinguishable from a bug.

Undocumented and self-versioned. `tooling/audit/agent-probes` asserts the shape
against the live machine every audit, because a vendor change makes this probe
answer "not parked" forever, silently.

## codex

No signal, and the route is closed rather than merely unimplemented. No hook or
protocol event fires when a `unified_exec` background terminal exits, and
`ThreadActiveFlag` has exactly two members, `waitingOnApproval` and
`waitingOnUserInput`. Recheck if either changes.

## opencode

No signal reachable from outside the process. `GET /session/status` exists, but
the server binds `--port 0` and writes no lock file, so nothing external can
find it; an adapter would have to be an in-process plugin that pushes. No live
harm meanwhile: background subagents are gated behind
`OPENCODE_EXPERIMENTAL_BACKGROUND_SUBAGENTS`, which is unset here.
