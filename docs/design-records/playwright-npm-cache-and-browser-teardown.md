# The npm Cache Path and the Playwright Browser Teardown

The record for why one `playwright-cli` subcommand cost fifty-one seconds of
pinned CPU, why the dist-tag everyone blames was not the cause, and why the two
obvious ways to stop the browser it starts both fail — one silently.

**`npx -y @playwright/cli@latest --version` took 51.09 s of user CPU. The
identical command, in the same directory, against the same registry, took
0.99 s once one file was deleted.**

---

## Context

Browser automation on this workstation is `playwright-cli`, a wrapper around
`npx -y @playwright/cli@latest` that attaches to the Flatpak Chrome over CDP.
The symptom reported was a saturated core and a desktop that stopped responding
whenever an agent was told to drive a browser. `htop` showed two processes at
the top: `npm exec @playwright/cli@latest ... fill input[...]` at 100.8%, and a
headless Chrome at 99.7% with 12:44 of accumulated CPU.

Both were real, and neither was the freeze. The freeze was a global OOM the
night before — one process named `script`, 11.97 GB anon RSS, inside
`workstation-herdr-server.service`, the only `oom_kill` of that boot and
7.5 times the combined footprint of all 36 Chrome processes. `/proc/pressure/cpu`
reported `full ... total=0` since boot: not one microsecond in three days where
every runnable task was stalled on CPU. The npm cost and the browser leak are
worth fixing on their own merits. Neither of them froze anything.

---

## The 51 seconds

The first diagnosis was that `@latest` forces npm to re-resolve the dist-tag and
re-reify the cached `_npx` tree on every invocation, and that the fix was to pin
the version. Pinning does make it fast — `@0.1.19` measured 0.58 s — which is
exactly why the diagnosis survived as long as it did.

It was wrong. A fresh cache, same `@latest` spec, six consecutive runs:

```
run1 1.34 s   run2 0.65 s   run3 0.50 s   run4 0.55 s   run5 0.55 s   run6 0.54 s
```

Re-resolving a dist-tag costs about half a second. The 51 s came from one
corrupt file:

```
/var/home/marc/.npm/_npx/423231821c231c73/package-lock.json   18.8 MB
entries: 5014        longest key: 6588 characters
  ../../../../../var/home/marc/.npm/_npx/.../node_modules/@playwright/cli
  ../../../../../var/var/home/marc/.npm/_npx/.../node_modules/@playwright/cli
  ../../../../../var/var/var/home/marc/.npm/_npx/.../node_modules/@playwright/cli
```

Isolated by deleting only that file, everything else held constant:

| | wall | user |
| --- | --- | --- |
| with the 18.8 MB lock | 51.09 s | 50.61 s |
| lockfile removed | 0.99 s | 0.86 s |

`node --cpu-prof` on the slow run accounts for it: `path.normalizeString`
20.9 s, `path.resolve` 14.1 s, `path.relative` 4.8 s. About 41 s of 50.9 s
normalizing those keys. All registry and network work totalled 0.08 s.

### The mechanism

`getent passwd` gives this account `/home/marc`, and `/home` is a symlink to
`var/home`. So `$HOME` is the symlinked path while every real path is
`/var/home/marc`. npm reaches its cache through `$HOME`, and `@npmcli/arborist`
recomputes the tree's relative paths on each reify — prepending one more `var/`
component every time. Reproduced from an empty cache on a symlinked path, eight
runs of `@latest`:

```
entries: 4 → 7 → 10 → 13 → 16 → 19 → 22 → 25
```

Three entries and one path level per run, unbounded. On a cache addressed by its
real path the same command stays at 4 entries and ~0.5 s indefinitely.

The dist-tag is the trigger, not the cause: npm cannot prove a cached tree
satisfies `latest`, so it reifies every run, and each reify grows the lock. A
pinned spec short-circuits, never reifies, and therefore never grows — which is
why pinning looks like a fix and is actually a way of not touching the bug.

This was never playwright-specific. `help-scout-mcp-server`, reached the same way
by every Claude Code session, was at 12921 entries and 9.9 MB. The `_npx` cache
totalled 988 MB.

Nor was it two packages. A first sweep deleted only `package-lock.json` files
over 2 MB and read as a cleanup; a later audit found **18** corrupt visible locks
and **19** corrupt hidden ones — npm keeps a second copy at
`node_modules/.package-lock.json`, 15 MB of it here, and deleting either alone
leaves the other to reseed the corruption. The surviving dirs cost ~4x the clean
run each: 1.8–2.0 s against 0.42–0.48 s. Both files in all 19 affected
directories were removed, which cleared the tree without discarding the 923 MB of
downloaded packages. The lesson is that the corruption is invisible, does not
self-heal, and is not detectable by file size — a healthy lock's keys are all
`node_modules/...`, so a key matching `../` is the honest probe.

---

## Routes that lost

**Pin the version in the wrapper.** Measured 0.58 s, one line. Rejected as the
fix: it leaves an 18.8 MB corrupt lock in place, does nothing for the three other
`@latest` call sites in `tooling/ai/`, and re-fires the day anything else uses a
dist-tag. Fix the input, never the symptom.

**Bake `@playwright/cli` into the image layer.** Rejected by two decisions
already written down: no `.list` declares a language runtime, and the AI installer
deliberately does not `npm install -g` here because brew-managed node's global
directory is not user-writable. Baking the CLI means baking node.

**`cache=~/.npm`, or `${HOME}/.npm`, wherever the value is written.** Reads as
the portable, username-free way to express it. It reproduces the bug exactly:
npm's `parseField` resolves both `~` and `${HOME}` against `$HOME`, which is the
symlinked path.

**`/usr/lib/environment.d`, which this repository's conventions name as the home
for session environment.** It cannot express this one. environment.d does
`${VAR}` expansion and nothing else, and every expansion available to it yields
the symlinked path. The generator directory beside it is the mechanism that can
run `readlink -m`.

**`readlink -f` inside the generator.** The first version used it, and it is
wrong in a way that only the image shows: `-f` requires every path component but
the last to exist, and the base's `/home` is a compat symlink to a `var/home`
that does not exist inside the image at all. So `-f` returned empty there and the
generator exited 0 emitting nothing — the silent no-op this whole change is
about. `-m` canonicalises without touching the filesystem and is correct on a
live account, inside the image, and for a home not yet created.

**A chezmoi `template` seed for `~/.npmrc`.** This was written, gated,
mutation-tested and reverted, and it is the most instructive of the losing
routes because everything about it worked. The template rendered correctly at
apply time, `output "realpath"` resolved, the source name composed, ten gates
held.

What killed it is that `~/.npmrc` is a file **npm writes to itself** — `npm
login`, `npm adduser`, `npm config set` all append there. A manifest entry puts
it under `tooling/audit/personal-config`, which byte-compares live against the
rendered seed, so the first credential npm writes turns `just audit`
permanently red. `tooling/dotfiles/sync` is an empty case for the `template`
kind, so the repository's own documented remedy for that report does nothing,
and the only apparent fix left is switching the entry to `copy` — which commits
the token to a public repository. The design created standing pressure toward
the exact outcome the kind was chosen to avoid.

Two smaller findings pointed the same way. `create_` never overwrites an
existing target, so on any account that already has an `~/.npmrc` — including
this one — the seed was inert. And chezmoi's `output` aborts the whole template
on a subprocess failure, which the `--init` apply path takes without
`--keep-going`: one missing `readlink` would have produced an account with no
dotfiles at all rather than one missing npm line.

The generator has none of that surface. It is image-owned, carries no user data,
is compared by no audit, and the environment variable it sets outranks any
`~/.npmrc` already on the machine, so it repairs a wrong value instead of
yielding to it. That `~/.npmrc` must not become a manifest entry is now itself a
gate.

Its one cost is timing: environment generators run when the user manager starts,
so an existing session keeps the old environment and the pin lands only after the
next login. It also does not reach a bare SSH session, which is outside the user
manager entirely.

**`scaffold` or `modify_` instead of `template`.** Worse. Both gain write power
and with it `chezmoi diff` exposure, and `just audit-diff` — the command the
audit output itself tells you to run — would print the merged live content,
credentials included.

---

## The browser teardown

Two orphaned headless Chrome stacks were alive during the investigation, 2.65
and 2.84 days old, one still holding the pages of a finished test session. The
reason is that nothing ever stopped them, and `playwright-cli close` — the
command the skill documents as closing the browser — cannot. Its daemon-side
`stop` unlinks the session file and exits node, and for a CDP attach
`playwright-core` builds `browserProcess = { close: doClose, kill: doClose }`
where `doClose` only tears down the WebSocket transport. A browser Playwright
never launched is one it cannot end.

So the helper needed a `--stop`, and the wrapper needed to reach it. What
identifies the browser turned out to be the whole problem.

**Kill `flatpak run`'s pid.** The obvious handle, and inert. flatpak moves the app
into its own transient `app-flatpak-*.scope`, so that bwrap owns no cgroup the
browser is in. Measured: after `kill`, 16 processes still alive and the CDP port
still answering. The same fact rules out a systemd user unit wrapping
`flatpak run` — it would own a cgroup Chrome is not in.

**`flatpak run --die-with-parent`.** This is the flag that looks like the fix, and
an A/B test says it works: without it, `kill <bwrap>` left `chrome_procs=16` and
CDP up; with it, `chrome_procs` went to 0 and CDP was gone. It was written in,
gated, and then failed the next test. The flag binds the app to the **invoking
shell**, not to bwrap: Chrome came up, printed `DevTools listening on
ws://127.0.0.1:9335`, and died the instant the helper exited. The browser
surviving between subcommands is the entire reason the helper exists, so the
teardown would have been bought by making every subcommand relaunch the browser —
and nothing would have reported it. It is now gated negatively, with the comment
that explains why stripped before the grep, because the file argues against the
flag at length in prose the gate would otherwise match.

**A bare `pkill -f`.** What the helper does instead is match on the profile
directory, which is its own per-boot path: an exact identity for every process of
that browser, zypak-forked children included, since they inherit the command line
that carries it, and one that cannot match the user's real Chrome. Firing that as
`pkill -f` also matches any process whose command line merely *mentions* the
path — including the shell that invoked the script, which is how a test run
killed its own shell with exit 144. The helper collects pids with `pgrep` and
excludes `$$` and `$PPID` before killing. Also gated.

---

## What is asserted

`tooling/validate/sources` gates ten things across four files, and every one of
them was mutation-tested: each assertion was confirmed to fail when its input was
broken, which caught two gates that passed against the file's own comments rather
than its code. Both files argue their own design at length in prose that repeats
every term the gates match, so the gates strip comments before matching.

The generator must exist, be executable, emit an `npm_config_cache` assignment,
resolve the home with `readlink -m`, and hardcode no home path; the manifest must
not track an `npmrc` at all. The helper
must carry `--max-time` on the CDP probe, must not pass `--die-with-parent`, must
identify the browser by its profile path, and must not use a bare `pkill -f`. The
wrapper must reach the helper's `--stop`.

---

## Loose ends

`--connect-timeout` bounds the connect, not the response. A wedged browser
accepts the connection and then answers nothing, which hung the CDP probe and
every `playwright-cli open` behind it; one was reproduced here returning nothing
after 3 s. `--max-time 3` was added in the same change.

The `script` process that caused the actual OOM is not a mechanism this
repository ships — there is no `script(1)` invocation anywhere in the tree, in
rtk, or in the Claude Code hooks. The kernel's task table shows it adjacent to a
`bash` and a blocked `yes`, which suggests an ad-hoc capture inside a herdr pane.
It happened once. It is recorded here only so the next person reading about a
frozen desktop does not attribute it to the browser or to npm.
