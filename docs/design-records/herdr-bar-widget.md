# herdr Bar Widget

The record for putting the herdr space rollup on the DMS bar: why it is a
Quickshell plugin rather than a cheatsheet or a niri bind, why it renders the
space picker's rows instead of reading herdr itself, and what is silent about it.

**The state of every agent on this machine was already computed, already
ordered, and already coloured — and it was only visible from inside a terminal
you had to open first.**

---

## Context

`prefix+s` opens the space picker: every open herdr workspace plus every on-disk
worktree, grouped by repository, sorted so a `blocked` or `done` agent rises to
the top, with a `*` on anything that finished in the last ten minutes. It is the
one place the answer to "who is waiting on me?" exists.

Getting to it costs a herdr window and two keys. With several agents running
across several repositories, the question is asked far more often than that is
worth, and the answer between askings is invisible.

The bar is on screen permanently. What was missing was a surface on it.

---

## Decision

A DMS plugin, `herdrJobs`, that renders `spaces.sh --json`.

DMS supports third-party bar widgets as a first-class surface. A `plugin.json`
with `"type": "widget"` and `capabilities: ["dankbar-widget"]`, plus a QML file
extending `PluginComponent`, is the whole contract; the base component provides
`horizontalBarPill`, `popoutContent` and the click that toggles between them, so
none of the window plumbing is ours.

The load-bearing decision is not the widget. It is that the widget computes
nothing.

`spaces.sh` already derived state, the freshness mark, the expiry window and the
attention ordering, in one `jq` program. The refactor split that program's tail
in two: `rows_json` emits one object per row, and the picker's `space_rows`
became that piped through a formatter producing the same padded TSV it always
did — verified byte-identical against the pre-refactor script, at both the raw
cache and the rendered-row layer. `--json` is the same builder with an empty
worktree topology.

That keeps [agent-recency.md](agent-recency.md)'s invariant intact. herdr times
nothing, so the `*` mark exists only because a hook writes a stamp per checkout;
a widget that folded the agent list again in QML would be a second clock, and it
would disagree the first time either side changed.

### Open spaces only

`--json` passes an empty topology, so the closed-checkout scan — a
`git worktree list --porcelain` per repository — never runs. The widget is an
ambient indicator; the picker stays the navigator, and it is the one that needs
to reach a checkout with no space yet. The poll is two herdr socket reads and a
`jq` pass, measured at ~90 ms, on a three-second timer, with an in-flight guard
so a wedged herdr cannot stack processes against the 10 s command timeout.

### Clicking a row

Focusing a space from the bar is two steps, not one. `herdr workspace focus`
scopes the session, but the client is attached in a window the popout is not, so
the window has to be raised as well. `focus-space.sh` does both.

The second half is `workstation-dev`'s `herdr_focus_existing_window` minus its
self-exclusion: that one runs in a terminal of its own and must skip it, while a
layer-shell popout is not a toplevel and never appears in `niri msg -j windows`
at all. Both `herdr` and `dev-terminal` app-ids are matched, because both binds
can hold a client.

This was the one part with no established answer at the start. It works because
`dms.service` inherits `NIRI_SOCKET` from the session — confirmed in the running
process environment, not assumed.

---

## What Lost

| Route | Why not |
|---|---|
| A DMS cheatsheet provider | The mechanism already exists here — `Mod+Slash` is a generated JSON file DMS renders. But a cheatsheet is a static payload with no pill, no click target on the bar and no per-row colour, so it answers a different question. It would also need a timer to regenerate, and would be stale between writes. |
| A niri bind spawning the picker in a bare `foot` | Near-zero work and full parity by construction. It is also not a widget: nothing ambient, nothing on the bar, which is the entire point. `spaces.sh` also reads `/dev/tty` on its error path, so running it outside a herdr pane is untested. |
| A second script reading `herdr agent list` directly | The shape the invariant exists to prevent. It would duplicate state, freshness and ordering, and the two views would disagree the first time one changed. It is also wrong on its own terms: two of sixteen live workspaces carry no `worktree` key, and one of them was `blocked` — the state the widget exists to surface. `workspace list` alone misses them; the join with `pane list` is what `spaces.sh` already does. |
| Installing to `/etc/xdg/quickshell/dms-plugins` | `/etc` is a three-way ostree merge, so anything landing there becomes machine-local forever. The chezmoi scaffold route into `~/.config` is the one that matches how the rest of this repository ships user-visible config. |

---

## What Is Silent About It

Three things, all worth knowing before the next change touches this.

**Nothing lints QML.** `tooling/validate/all` shellchecks scripts, compiles the
Neovim Lua seeds and parses every tracked JSON file. There is no `qmllint` on
this machine and adding one means a Qt development package in the image for a
lint. So a broken widget passes `just validate` and shows up as an empty space
on the bar. The check is `dms ipc call plugins reload herdrJobs`, which answers
`PLUGIN_RELOAD_SUCCESS` or names the error — and it catches errors inside the
popout too, which is only built on click, because the whole document compiles at
load. That was verified by breaking it deliberately.

**Enablement had no home.** DMS records which plugins are on in
`~/.config/DankMaterialShell/plugin_settings.json`, which is not the settings
overlay: `tooling/dms/validate-overlay` requires every top-level overlay key to
exist in the installed `SettingsSpec.js`, and there is no `pluginSettings` key
among its 529. So it is a `dotfiles.manifest` entry instead, create-only rather
than scaffold — DMS owns that file afterwards for every other plugin, and a
scaffold seed would rewrite it on every apply and delete theirs. If some future
plugin writes the file before chezmoi seeds it, `herdrJobs` is silently never
enabled; `dms ipc call plugins enable herdrJobs` is the recovery.

**A plugin directory created while DMS is running is invisible.**
`PluginService` binds its folder watcher once at startup, and a watcher aimed at
a directory that does not exist yet never fires when it appears. On a fresh
account there is no gap — chezmoi runs at `graphical-session-pre.target` and
`dms.service` starts after `graphical-session.target` — but on a machine that
already existed, one `dms ipc call plugin-scan scan` is required, once.

---

## Where to go next

[../subsystems/desktop-session.md](../subsystems/desktop-session.md) owns the
plugin as it stands, [../subsystems/dev-environment.md](../subsystems/dev-environment.md)
owns the picker it mirrors, and [agent-recency.md](agent-recency.md) is why
there is exactly one clock behind both.
