# The herdr Server Unit

The record for why the herdr server got a systemd user unit of its own: the
one-millisecond race that was eating a workspace at every other reboot, why
`KillMode=mixed` is the entire fix, and why the recency stamp lost its expiry
window in the same change rather than a later one.

**A reboot was not losing the herdr session. It was losing a workspace out of
the middle of it, silently, and then persisting the result as if that were the
session.**

---

## Context

`session.json` already worked. herdr writes it on a debounce and again on a
clean shutdown, and restores workspaces, tabs, panes, working directories,
layout and focus at the next server start — visible in `herdr-server.log` as
`session restore evaluated` followed by `restored session already has
workspaces; ignoring startup cwd`. Across the eleven server starts the log
held, the restored count matched the count in the save that preceded it every
single time.

Which is exactly what made the defect hard to see. The restore was faithful.
The *save* was wrong.

Two of nine reboots dropped a workspace between the last debounced save and the
shutdown save:

```
20:28:51.198253Z  session saved ... workspaces=2
20:29:03.764727Z  pane child exited ... pane_id=46 status="... signal: Some(\"Terminated\")"
20:29:03.765926Z  server shutdown initiated
20:29:03.817137Z  session saved ... workspaces=1
```

Pane 46 was the only pane of workspace `w27`. It died 1.2ms before the server
processed its own SIGTERM, so herdr read it as an ordinary pane exit, closed the
workspace it emptied, and then wrote that. The 2026-08-29 reboot has the same
shape with pane 4. Panes that die *after* `server shutdown initiated` — three of
them in the same second, leaving with `signal=Hangup` — cost nothing, because by
then herdr is tearing them down itself.

The actor was never in doubt once the cgroup was read:

```
$ cat /proc/11330/cgroup        # herdr server
0::/user.slice/user-1000.slice/user@1000.service/app.slice/foot-server.service
$ cat /proc/11348/cgroup        # a pane's fish
0::/user.slice/user-1000.slice/user@1000.service/app.slice/foot-server.service
$ systemctl --user show foot-server.service -p KillMode
KillMode=control-group
```

The server is a child of the terminal window that launched it. Fifteen pane
shells and the server sat in one unit, and `control-group` SIGTERMs a unit's
whole cgroup at stop. `journalctl` for that boot puts the signal 35ms after
`Stopping user@1000.service`, with `session-2.scope` already deactivated 147ms
earlier and logind's `KillUserProcesses` at its default `false` — so the user
manager stopping `foot-server.service` is the only candidate, and the race is
between fifteen processes handling the same broadcast.

---

## Decision

Give the server a unit whose cgroup it does not share, and set the one directive
that stops systemd signalling the panes at all.

`man systemd.kill`, on this machine's systemd 259:

> If set to mixed, the SIGTERM signal ... is sent to the main process while the
> subsequent SIGKILL signal ... is sent to all remaining processes of the unit's
> control group.

That is the whole mechanism. The server takes SIGTERM alone, writes
`session.json` with every workspace still in it — 51ms, measured — and shuts its
own panes down before anything else could reach them. `TimeoutStopSec=30` sits
well inside the user manager's own 60s, and well under the 45s default that
`/usr/lib/systemd/user/service.d/10-timeout-abort.conf` would turn into a
SIGABRT and a coredump rather than a quiet kill.

Three constraints shaped the rest of it.

**The unit must start late.** Whatever environment the server holds is what
every pane it ever spawns inherits, and `niri --session` imports its own
environment — `WAYLAND_DISPLAY`, `NIRI_SOCKET`, the Homebrew `PATH` — into the
user manager rather than reading `environment.d`. `After=graphical-session.target`
plus `ConditionEnvironment=WAYLAND_DISPLAY`, copied from `foot-server.service`,
is what guarantees the import has happened. `TERM` and `COLORTERM` are pinned in
the unit because a user service inherits `TERM=linux` and no `COLORTERM`,
measured against the two user services already running here.

**`ExecStart` cannot be the Homebrew path.** `build_files/99-check-build.sh`
runs `systemd-analyze verify` over `/usr/lib/systemd/user/workstation-*.service`
inside the build, and verify exits 1 on a command that is not executable in the
layer — confirmed directly, not assumed. Homebrew is unpacked on first boot.
So `ExecStart` is a two-line wrapper under `/usr/libexec`, and
`ExecCondition=/usr/bin/test -x /home/linuxbrew/.linuxbrew/bin/herdr` skips the
unit on a machine that has no herdr yet instead of failing it forever. Both
halves are the shape `workstation-claude-mcp-seed.service` already set.

**The launch stays deliberate.** The unit is not in the user preset. Enabling it
would restore every workspace's shells at every login whether or not a terminal
is opened, which is a different feature from the one this record is about. The
two paths that open a session start it explicitly instead. A bare `herdr` typed
at a shell still forks a server into the wrong cgroup, so
`tooling/audit/units` reads the running server's `/proc/<pid>/cgroup` and says
so — the machine-side half, because no build-time gate can see it.

### The expiry window went in the same change

`AGENT_EXPIRED_SECONDS=43200` is gone, and `[session] resume_agents_on_restore`
is pinned `true`. This belongs here rather than in a follow-up because the unit
is what makes the conflict routine.

Before the unit, most workspaces did not survive a reboot, so herdr's native
resume rarely ran. Afterwards it runs on every space at every boot — and it
restores the exact conversation with no age limit of its own, while
`claude_command` refused to resume anything older than twelve hours. Two
deciders, one question, opposite answers, on the path that had just become the
normal one.

Removing the window rather than pinning the resume off was the cheaper of the
two, and it turned out to cost almost nothing. The picker's expiry only ever
hid **closed** rows, and those come from `git worktree list` rather than from the
stamp store, so the list was already bounded by what is on disk and already
pruned itself through the ship and close-workspace popups. At the time of the
change, every worktree on disk in every repo with an open space already had one:
the measured number of rows the filter was hiding was zero. What the window
mostly did was disagree with herdr after an overnight reboot.

So the stamp is now read as a fact rather than as a clock. A checkout that has
ever finished a turn reopens with `claude --continue`; one that never has starts
clean, because `--continue` with no conversation drops the pane to a bare shell.
The clock itself is unchanged — one stamp per checkout, two writers — it simply
has one consumer fewer. [agent-recency.md](agent-recency.md) is the record of
building it, and by the standing rule it still describes the twelve-hour window
it was built with.

### Two defects the unit exposed

Both were masked by the pruning, and both become routine once the session
actually comes back.

`session.json` persists a tab's `custom_name` but of a pane only its `cwd` and
agent session reference. The split layout's marks are pane labels, so after a
restore `layout-toggle.sh` saw an unlaid-out workspace and rebuilt the default
layout on top of a live split one. The fix is the mark that does survive: the
split tab is named `dev`, and the toggle now tests that name beside the pane
labels.

The per-pane status memory under `~/.local/state/workstation/agent-status`
outlives the server that wrote it, and herdr restores public pane ids verbatim.
A machine shut down mid-turn came back with the pane still remembered as
`working`, so the first `idle` after the restore read as a turn that ended while
the server was off — a finish stamp for something that never finished.
`agent-status-reset.sh` clears the directory on `[[startup]]`. It removes a
reading taken by a dead server and writes no stamp, so the single clock keeps
its one pair of writers.

---

## What Lost

**Enabling the unit at login.** The obvious reading of "persistent herdr on
reboot", and it does more than the bug called for: every restored workspace's
shells respawn at login whether or not a terminal is opened. Rejected as a
separate decision, not a rejected mechanism — the preset line is all it takes,
and the unit comment says so.

**Socket activation.** It would keep the current lazy start with none of the
launch-path edits, mirroring `foot-server.socket`. Rejected because nothing
established that herdr accepts a listening fd, and verifying it means running a
throwaway server. Two `systemctl --user start` calls are the cheaper certainty.

**`ExecStop=herdr server stop`.** Redundant and slightly harmful: the log proves
plain SIGTERM already drives the complete save, and `ExecStop` would add a
client process inside the cgroup that is being torn down.

**`Restart=always`.** `workstation-x11-clipsync.service` uses it, but
`herdr server stop` and `herdr update --handoff` both end the server on purpose
and exit 0. `on-failure` leaves those working.

**Pinning `resume_agents_on_restore = false` and keeping the twelve-hour
window.** The other way to make one decider own resume, and the one that matches
the letter of the original invariant. It loses because it keeps a policy whose
only remaining effect on this machine was to contradict herdr, costs a keypress
per space after every reboot, and gives up exact-conversation restore for
`--continue`'s most-recent-in-this-cwd. herdr's native resume is not flawless —
three of twelve attaches in the log died within ten seconds, and it logs nothing
when it fails — but the failure is self-healing: the pane frees up, and the
layout key runs `claude --continue` where the failure is visible.

**Re-deriving pane labels at startup** to make the split layout restore-safe.
More machinery than the defect needs, when a mark that already persists was
sitting in the tab name.

---

## Shipping

`tooling/validate/sources` gates every part of this that fails silently: that
`KillMode=mixed` is still in the unit, that `ExecStart` is still the
`/usr/libexec` wrapper and the `ExecCondition` still guards it, that both
session launch paths still start the unit, that no expiry constant has come back
into the plugin, and that the `dev` tab mark and the startup status reset are
still wired. `tooling/audit/units` covers the machine-side half — a server
running outside its unit.

The gates exist because every one of these fails at a reboot and nowhere else,
and what it costs is one workspace out of the middle of a session that otherwise
looks correct.

---

## Where to go next

[../subsystems/dev-environment.md](../subsystems/dev-environment.md) owns the
current behaviour of the server unit, the layouts and the picker.
[agent-recency.md](agent-recency.md) is the record of the stamp this change
narrowed. [../validation-and-gates.md](../validation-and-gates.md) lists what
each gate asserts.
