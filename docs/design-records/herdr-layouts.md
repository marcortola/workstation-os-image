# Herdr Layouts

The record for giving the dev workspace a second shape: why there are two
layouts rather than one, why neither is built with the API named after the job,
and which four arrangements lost.

**`layout.apply` replaces the tab it is handed, so the one call that describes a
layout declaratively is also the one call that kills the agent sitting in it.**

---

## Context

The dev layout was three tabs — `main` running the agent, `nvim`, `term` — built
by `layout.sh` and reached from `prefix+shift+n`, from a herdr-created worktree,
and from the project picker. Three tabs means one thing on screen at a time. The
agent is the thing you read while the editor is the thing you type in, and a tab
switch is exactly the wrong granularity for that pair: you lose sight of the
conversation the moment you go to act on it.

The ask was a second layout keeping the agent visible at a third of the width
with the editor and the terminal sharing the rest, the editor showing by
default, and the three-tab layout staying the default.

---

## What herdr Can Actually Do

A tab's layout is a binary tree and nothing else. `herdr api schema` gives
`LayoutNode` as `oneOf` a `pane` and a `split`, and `pane zoom` zooms a pane to
the whole tab rather than to a region of it. There is no stacked or tabbed pane
group, so "the right-hand column shows one of two things" has no direct
expression: a region either draws both children or one of them lives in another
tab.

A pane belongs to exactly one tab. `pane move` relocates a pane, it never shares
one, so no arrangement can put the same editor — or the same agent — in two tabs
at once.

---

## Decision

One `dev` tab, three panes, built from `pane split` and `pane move`:

```
root split right 0.33   first : main
                        second: split down 0.85   first : nvim
                                                  second: term
```

Three things follow from that shape.

**Ratios are named once.** `LAYOUT_MAIN_RATIO`, `LAYOUT_EDITOR_RATIO` and
`LAYOUT_TERMINAL_RATIO` sit at the top of `layout-common.sh`. A split's `ratio`
is always the share of its first child, so all three describe the same thing and
the file says so rather than leaving each reader to work it out.

**Switching moves panes, it does not rebuild them.** Applying the split adopts
the `nvim` and `term` panes out of their tabs when they exist; going back moves
them out again with `pane move --new-tab`. A tab closes itself once its last pane
leaves. The measured result: the editor's process group id is unchanged across a
round trip, so unsaved buffers survive, and so does the agent's conversation.

**The toggle is a resize, not a switch.** `prefix+n` and `prefix+t` focus the
pane and grow it, and growing is restricted to a `down` split. The vertical split
is what pins `main` to its third, and it has to keep that width whichever pane
you move to — so `prefix+m` focuses and resizes nothing, and the restriction is a
property of the split direction rather than a special case naming `main`.

---

## What Lost

**`layout.apply`.** The obvious route: one request carrying the whole tree, with
`command`, `cwd` and `label` per pane. It was tried against a live server before
anything was written. Handed an existing `tab_id` and an existing `pane_id`, it
answered with a *new* tab holding *new* panes; the old tab and its panes were
gone and the `pane_id` had been ignored rather than adopted. Every application of
a layout would have restarted the agent. Rejected on the evidence, and
`layout-common.sh` carries the finding as a comment so the next edit does not
rediscover it the expensive way.

**Two tabs with the editor duplicated** — `main | nvim` and `term | nvim`. The
literal shape asked for, and the one a pane's single-tab membership makes
impossible to do honestly: it means two Neovim processes over one tree, two sets
of buffers and two swapfiles racing on the same file.

**Two tabs with the agent following focus** — a `tab.focused` hook moving the one
`main` pane into whichever tab you switched to. It would have been the only
arrangement giving a truly shared agent column, at the cost of relocating a
running agent's pane on every tab switch. A moving part on the hot path, for a
layout whose whole point is that nothing moves.

**The editor alone in the column, with the terminal left as a tab.** Cheapest to
build and it gives up the premise: the agent is invisible from the terminal tab,
which is the state the second layout exists to remove.

---

## Shipping

The layout is `layout-split.sh` and the action is `dev.flow.layout-split`. It
shipped on its own key, `prefix+shift+v`, the sibling of `prefix+v`
`split_vertical`. That did not survive contact: see **One key** below.

Two things had to learn about the second layout. `focus-tab.sh` now falls back
from a tab of the requested label to a pane of it, which is why the split tab is
named `dev`: a tab called `main` would be found first and `prefix+m` would never
reach the pane inside it. And the project picker's gate, which applied the
default layout to any single-tab workspace, now requires a single pane as well —
the split layout is one tab too, and picking the project again would otherwise
have taken it apart.

---

## One key

Two keys were one too many. A layout is a place you are, not a command you issue,
so there is one key — `prefix+shift+n`, through `layout-toggle.sh` — and it reads
which layout the workspace is in and applies the other. A *pane* called `nvim` or
`term` is the split layout's mark and exists under no other; a *tab* of that name
is the default layout's; neither means nothing is laid out yet, so the first
press builds the default and every press after it alternates. Each question is
asked of the whole workspace: asking inside the agent's tab made the answer
depend on finding the agent first, which a split workspace whose agent pane had
exited could not do.

The two scripts stay separately runnable, because `worktree-create.sh` and
`workstation-dev` want the default layout and not a toggle, and both `exec`
`layout.sh` by path.

**The keys were the smaller half.** Pressing the layout key twice stacked a
second `nvim` and `term` tab, and four independent roots each did it:

- The builders ran unconditionally. They reuse a tab that already carries the
  label instead.
- The agent's tab was whichever tab came first. With the agent pane exited that
  was the editor's tab — renamed `main`, given a second Neovim, left with no
  agent. Both layouts find it by label now, and build a new one when the
  workspace has genuinely lost it.
- **`pane move` answers a refusal with a `SUCCESS` reply.** `changed` is `false`
  and `reason` is `same_tab` or `zoomed_tab`, while `pane` — required on every
  answer — still reports the *unchanged* tab. Reading the tab id back out of that
  reply made a zoomed tab rename the tab everything was still in. Read
  `created_tab`, which is null unless a tab was really made, check `changed`, drop
  the zoom before moving, and never build a replacement for a pane that would not
  move. This is the trap under the other three and the one to remember.
- herdr accepts two tabs called `nvim` and every lookup takes the first, so one
  duplicate was permanent: the orphan shadowed the tab being worked in. The tie
  breaks on which tab is running something, and a tab the user split further
  loses the label when its pane is adopted away.

Nothing here closes a tab. Duplicates from before the fix shrink as the layouts
reuse them, but they never disappear on their own.

**Editing `herdr-plugin.toml` does nothing until the plugin is re-linked.** herdr
caches the manifest in `plugins.json` and `server reload-config` covers
`config.toml` only — it reports `"status":"applied"` while the registry still
holds the previous actions, so a key bound to an action herdr has not registered
is silently dead. Checked on this machine while making this change,
`plugins.json` listed only `adopt-worktrees` and `layout`, so the running server
had `prefix+shift+v` bound to an action it did not know about.

---

## Where to go next

[../subsystems/dev-environment.md](../subsystems/dev-environment.md) owns the
current behaviour of both layouts, and [../keybindings.md](../keybindings.md)
owns the keys. [agent-recency.md](agent-recency.md) covers the stamp
`claude_command` reads — in `layout-common.sh`, for both layouts — to decide
whether the agent resumes the conversation or starts clean.
