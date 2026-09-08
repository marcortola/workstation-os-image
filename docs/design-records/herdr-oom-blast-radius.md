# The herdr Cgroup's OOM Blast Radius

The record for why one out-of-memory kill anywhere on the machine was SIGKILLing
every process in every terminal pane, why the fix is two directives rather than
one, and the six routes that lost.

**Giving the herdr server its own cgroup fixed the logout race and created a new
failure with a different shape: an OOM kill against any process in any pane took
down the work running in all of them.**

---

## Context

[herdr-server-unit.md](herdr-server-unit.md) moved the server into
`workstation-herdr-server.service` so a logout SIGTERM would reach the server
alone. The point of that change is that the unit's cgroup holds the server *and
every pane it owns*. That is the mechanism, not a side effect.

So every process the user runs in a herdr pane — a build, a JVM, a test runner, a
browser — is a process of that unit. systemd's default is `OOMPolicy=stop`: if
the kernel OOM killer kills any process in a unit's cgroup, the service manager
stops the unit. For a worker service that is correct. For a cgroup holding the
user's own work it means one OOM kill reaches all of it.

It happened twice, at `Sep 07 22:13:54` (victim `task=script`, anon-rss 11.9 GB)
and `Sep 08 14:51:37` — 16h37m apart, and the only two such events in a journal
reaching back to `Sep 05 08:09:54`. The second:

```
systemd-oomd invoked oom-killer: gfp_mask=0x140cca(...), order=0, oom_score_adj=-900
oom-kill:constraint=CONSTRAINT_NONE,nodemask=(null),cpuset=systemd-oomd.service,
  mems_allowed=0,global_oom,task_memcg=/user.slice/user-1000.slice/
  user@1000.service/app.slice/workstation-herdr-server.service,task=chrome,pid=3670881
Out of memory: Killed process 3670881 (chrome) ... oom_score_adj:300
workstation-herdr-server.service: Failed with result 'oom-kill'
```

`constraint=CONSTRAINT_NONE` — the machine ran out, not a cgroup limit. herdr
exceeded nothing; it was holding the cgroup that happened to contain the victim.
`cpuset=systemd-oomd.service` names the process whose allocation tripped the
kernel killer, not the actor: systemd-oomd was the allocator, the kernel chose.

### What it actually cost, measured

The blast radius is narrower than "you lose your session", and the record is
written to the log rather than to the intuition. `herdr-server.log` for the
second incident:

```
12:51:28.705173Z  session saved ... workspaces=8
12:51:39.393041Z  session restore evaluated ... workspaces=8
```

The **layout survives**. `KillMode=mixed` sends SIGTERM to the main process
alone, herdr writes `session.json` with all eight workspaces, `Restart=on-failure`
brings it back, and the restore is faithful — the mechanism the previous record
built, working exactly as designed. The journal puts the gap at eleven seconds:
`Failed with result 'oom-kill'` at 14:51:37.237, `Started` at 14:51:39.358.

What does not survive is everything *running* in those panes. Every build, dev
server, container, and coding agent mid-turn is SIGKILLed, in every workspace, on
account of one process somewhere else on the machine losing a memory race. That
is the cost this record is about, and it is worth two directives — but it is not
the loss of a workspace, and claiming so would put this record at odds with the
log sitting next to it.

### Which browser, and why it matters

The victim was a renderer of a **host-launched** Chromium, not the image's
Flatpak Chrome. systemd's own kill list for that moment names
`app-org.chromium.Chromium-2256823.scope` while killing `chrome_crashpad` 2256827
and 2256829 out of herdr's cgroup — a split the Flatpak build never produces. On
this machine no `chrome_crashpad` process sits outside its own
`app-flatpak-com.google.Chrome-*.scope`. Reproducing the path gives the
downloaded `~/.cache/ms-playwright/chromium-1243` build, which moves only its
browser process into a scope and leaves crashpad, zygotes, gpu, utility and every
renderer in the launching pane's cgroup.

It reached a host Chromium because the booted deployment's `playwright-cli`
matches `open` only as `$1` (`/usr/bin/playwright-cli:16`), so a session-flagged
`-s=NAME open` never reaches the translation and falls through to upstream, which
downloads and launches its own browser. `f1c0363` replaced that test with one
that finds the first non-flag argument — committed 3 minutes 34 seconds before
the kernel invoked the OOM killer, and never built.

---

## Decision

Two directives, because the two routes to the same outcome are different
mechanisms.

**`OOMPolicy=continue`** — for the kernel OOM killer. `man systemd.service`:

> If set to continue and a process in the unit is killed by the OOM killer, this
> is logged but the unit continues running.

Verified rather than read: a throwaway transient unit with `OOMPolicy=continue`,
`MemoryMax=200M` and `MemorySwapMax=0`, whose main process spawned a memory hog
the cgroup killer then killed. The main process reaped it as an ordinary child
(`hog reaped rc=137 -- main still alive`), systemd logged one line and took no
action, and `ActiveState=active Result=success NRestarts=0` throughout. The
control unit, identical but for `OOMPolicy=stop`, lost every process.

That measurement was on `CONSTRAINT_MEMCG` while the incident was `global_oom`.
It generalises for a source-level reason rather than an experimental one: systemd
reads only the `memory.events` `oom_kill` counter, which the kernel documents as
"killed by any kind of OOM killer", and the notification carries no discriminator
beyond `managed_oom`. systemd cannot tell the two apart.

One bound. This covers non-main-process kills only; if the OOM killer picks the
server itself the unit still dies, by the ordinary main-process path
(`result 'signal'`, a different code path from `'oom-kill'`). Note the reason the
server is an unlikely victim is **not** its `oom_score_adj`: every process in the
cgroup inherits 200 from the user manager, the server included, and so do
`foot-server.service`, `niri.service` and `dbus.service`. Chromium renderers
self-raise to 300. With adj equal the kernel's badness score is dominated by RSS,
and a ~10 MB server loses to an 11 GB build.

**`ManagedOOMPreference=avoid`** — for systemd-oomd, which `OOMPolicy` cannot
*prevent*. The man page is explicit that `OOMPolicy` applies to oomd too, but
only to "the state of the unit after systemd-oomd kills a cgroup associated with
it". oomd selects a whole **cgroup** and SIGKILLs everything in it, so under
`continue` alone the memory-pressure path still takes every pane.

herdr is an eligible candidate today, not in principle:
`/usr/lib/systemd/user/slice.d/10-oomd-per-slice-defaults.conf` sets
`ManagedOOMMemoryPressure=kill` with an 80% limit on every user slice, and
`oomctl` shows `app.slice` monitored. The unit's cgroup is a leaf with no
children and `memory.oom.group=0` — what oomd considers selectable — holding 79
processes.

Two limits worth stating, because both are live rather than theoretical:

- **The memory-pressure path is covered; the swap path is not.**
  `man systemd.resource-control` gives two conditions. For memory pressure the
  xattr is respected when the unit's cgroup and the monitored ancestor share an
  owner — here both are `marc`, so it holds. For swap it requires the cgroup to
  be owned by **root**, which a uid-1000 user unit can never satisfy. `oomctl`
  monitors swap at a 90% limit and swap currently sits at 11.1 G of 15.3 G, so
  this is a real gap, not a hypothetical one.
- **oomd monitors more than `app.slice`.** It also watches
  `user@1000.service`, where the candidate is `app.slice` itself, which carries
  no `avoid` xattr. So `avoid` deprioritises herdr within `app.slice`'s candidate
  set; it does not remove the unit from every path oomd can take.

Deprioritising means something else is chosen. Measured, the substitutes are not
equivalent: the Chrome scopes recover on their own; `dms.service`
(`Restart=on-failure`) comes back with a visible shell, bar and widget blip; and
`foot-server.service` (`Restart=no`) does not come back at all. That trade was
examined rather than assumed, and it is the reason the next route lost.

---

## What Lost

**`ManagedOOMPreference=omit`.** The nearest neighbour and the one a reader will
reach for: it removes the cgroup from oomd's candidate list outright rather than
deprioritising it. Rejected on measurement. herdr's cgroup is 8097 M of
`app.slice` against 2609 M and 1495 M for the two real Chrome scopes and 650 M for
`dms.service` — it is usually the largest consumer in the slice by a wide margin.
Exempting the biggest cgroup does not relieve pressure; it redirects every
selection onto neighbours a fraction of its size, including the terminal server
that never restarts. `avoid` keeps herdr last in line without making it
unselectable when it genuinely is the problem.

**A manager-wide `DefaultOOMPolicy=continue`.** The obvious "fix it everywhere"
answer, and it works: measured here, a `[Manager]` drop-in flips the manager and
every non-overriding user service live, on `systemctl --user daemon-reload`
alone. It loses on blast radius in the other direction. Manager configuration
admits no per-user condition, so a `/usr/lib/systemd/user.conf.d/` drop-in also
flips greetd's `greeter` manager — the class this repository elsewhere guards
with `ConditionUser=!@system` — and every future user service whose author wanted
`stop` and had no reason to say so. One unit has this problem; one unit gets the
directive.

**A top-level `service.d/` drop-in setting `OOMPolicy` for all user services.**
Reads as the more explicit version of the above and is strictly worse:
`DefaultOOMPolicy=` is a default that a unit's own line beats, while a drop-in
*overrides* the unit. It would silently defeat every upstream author who set
`OOMPolicy=` deliberately.

**Launching the browser in its own transient scope** (`systemd-run --user
--scope`). Measured inert for the Flatpak browser: flatpak migrates the launcher
out into its own `app-flatpak-*.scope`, and the wrapper scope was already
`inactive` with the browser still running — the same fact
[playwright-npm-cache-and-browser-teardown.md](playwright-npm-cache-and-browser-teardown.md)
records for a systemd unit wrapping `flatpak run`. It was also aimed at a premise
that turned out false: the Flatpak browser is *not* split across herdr's cgroup.
The apparent evidence was a `pgrep -f` self-match — a shell whose own command
line contained the profile path — which is the exact hazard
`workstation-playwright-chrome` documents in its own `targets()` comment.

**Fixing it in `workstation-playwright-chrome`.** Follows from the above: the
helper's browser was never the one in the cgroup. A fix scoped there would leave
every non-browser case — the JVM, the build, the test runner — untouched, and
those are most of what a pane runs.

**Doing nothing until the image catches up.** Tempting, because the deployment
*was* the proximate cause: `f1c0363` was committed before the incident and never
built. But that removes one producer of OOM-killable processes from one pane.
`OOMPolicy=stop` is what turns any of them into a session-wide SIGKILL.

---

## Shipping

`tooling/validate/sources` gates both directives beside the existing
`KillMode=mixed` assertion, for the same reason: one line each, both read as
noise to anyone tidying the unit, and neither absence shows up until the machine
is already out of memory for an unrelated reason.

`tooling/audit/units` reads both from the **running** unit as well. A source gate
proves the repository, and the repository was not the problem: the incident
happened on a deployment whose four ostree copies all predated the fix, so no
reboot or rollback reached it.

**The pre-image drop-in must be deleted.** While the image is being built, the
live machine carries
`~/.config/systemd/user/workstation-herdr-server.service.d/10-oom-policy.conf`
with the same two directives. `systemctl show` reports merged properties, so that
file makes the machine-side audit green regardless of what the booted image
carries — it masks the very drift the audit exists to find. Delete it on the
first boot carrying the unit. The audit reports any `$HOME` drop-in on an
image-owned `workstation-*` unit for this reason, so the shadow is visible rather
than invisible-and-green.

---

## Where to go next

[herdr-server-unit.md](herdr-server-unit.md) is why this cgroup exists at all,
and is the record this one extends rather than corrects.
[../subsystems/dev-environment.md](../subsystems/dev-environment.md) owns the
current behaviour of the unit.
[../validation-and-gates.md](../validation-and-gates.md) lists what each gate
asserts.
