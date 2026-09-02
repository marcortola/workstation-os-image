# Keybindings

The shortcuts worth knowing on this workstation, grouped by what you are trying
to do rather than by which program answers. It is a study sheet, not an
inventory: the rare binds are left out on purpose, and every program here can
list its own keys better than this page can. Read this to learn the shape, and
ask the program when you need the exact key.

**Three keys open three layers: `Mod` reaches the desktop, `Ctrl+G` the terminal
session, `Space` the editor. Everything else hangs off one of them.**

---

## Every Day

The keys that carry most of the work, one block per layer. This section is the
cheatsheet's first screen, so it is deliberately kept to 25 rows per layer --
`tooling/keybindings/build-cheatsheet.py` fails the build if it grows past what
fits above the fold.

### Desktop (Mod)

#### Windows

| Key | Action |
|---|---|
| `Mod+H` / `Mod+L` | Focus the column left / right |
| `Mod+J` / `Mod+K` | Focus the window down / up in the column |
| `Mod+Ctrl+H` / `Mod+Ctrl+L` | Move the column |
| `Mod+Ctrl+J` / `Mod+Ctrl+K` | Move the window in the column |
| `Mod+R` | Cycle the column-width presets |
| `Mod+M` | Maximise the column |
| `Mod+W` | Tab the column instead of stacking it |
| `Mod+V` | Float it |
| `Mod+Q` | Close the window |

#### Workspaces and screens

| Key | Action |
|---|---|
| `Mod+1` … `Mod+9` | Go to a workspace |
| `Mod+Up` / `Mod+Down` | Workspace up / down — not the window |
| `Mod+Ctrl+Up` / `Mod+Ctrl+Down` | Send the column up / down |
| `Mod+Ctrl+1` … `Mod+Ctrl+9` | Send the column to a workspace |
| `Mod+O` | Overview of everything |
| `Mod+Shift+H` / `Mod+Shift+L` | Focus the monitor left / right |
| `Mod+Comma` / `Mod+Period` | Pull a window in / push it out |
| `Mod+Shift+F` | Fullscreen |

#### Launch and capture

| Key | Action |
|---|---|
| `Mod+Space` | Any application |
| `Mod+T` | A terminal |
| `Mod+Shift+T` | Coding session — herdr |
| `Mod+Shift+P` | A project, picked by repository |
| `Mod+Shift+S` | Screenshot a region |
| `Mod+Print` | OCR the screen to the clipboard |
| `Mod+Shift+V` | Dictate |
| `Mod+Slash` | This sheet |

### Herdr (Ctrl+G)

Written with the prefix here, unlike the reference below.

#### Projects and worktrees

| Key | Action |
|---|---|
| `Ctrl+G` `s` | Space picker — projects, branches, worktrees |
| `Ctrl+G` `shift+w` | New branch worktree, with the layout ready |
| `Ctrl+G` `shift+o` | Open an existing worktree |
| `Ctrl+G` `shift+u` | Adopt every repository's worktrees as spaces |
| `Ctrl+G` `shift+x` | Close a space, showing uncommitted work first |
| `Ctrl+G` `shift+m` | Ship the branch: push, PR, auto-merge |
| `Ctrl+G` `shift+n` | Toggle the layout: three tabs, or one split tab |
| `Ctrl+G` `g` | lazygit at this pane's repository |

#### Tabs and panes

| Key | Action |
|---|---|
| `Ctrl+H`, `Ctrl+J`, `Ctrl+K`, `Ctrl+L` | Focus panes, crossing into nvim. No prefix |
| `Ctrl+G` `m` | `main`, where claude runs |
| `Ctrl+G` `n` | `nvim` — not next-tab |
| `Ctrl+G` `t` | `term` |
| `Ctrl+Alt+T` | `term`, no prefix |
| `Ctrl+Alt+N` / `Ctrl+Alt+P` | Cycle tabs, no prefix |
| `Ctrl+G` `v` / `h` | Split beside / below |
| `Ctrl+G` `z` | Zoom one pane, and back |
| `Ctrl+G` `x` | Close the pane |

#### Agents

| Key | Action |
|---|---|
| `Ctrl+G` `a` | Agent picker, whatever needs you first |
| `Ctrl+G` `a` then `enter` | Focus that agent's pane |
| `Ctrl+G` `a` then `ctrl+o` | Send it a prompt without focusing it |
| `Ctrl+G` `alt+o` | opencode in a pane |
| `Ctrl+G` `u` | Pick a link out of the scrollback |
| `Ctrl+G` `c` | New tab |
| `Ctrl+G` `b` | Show or hide the sidebar |
| `Ctrl+G` `?` | Every herdr key |

### Nvim (Space)

#### Find

| Key | Action |
|---|---|
| `Space` `Space` | Find a file |
| `Space` `/` | Grep the project |
| `Space` `ss` | Grep, seeded with the last search |
| `Space` `,` | Open buffers |
| `Space` `e` | File tree |
| `Space` `sw` | Search the word under the cursor |
| `f` | Search inside this buffer |
| `s` | Jump anywhere on screen, by two letters |

#### Code

| Key | Action |
|---|---|
| `gd` / `gr` | Definition / references |
| `K` | Documentation under the cursor |
| `Space` `ca` | Code action — the "fix it for me" key |
| `Space` `cr` | Rename everywhere |
| `Space` `cf` | Format. Never happens on save |
| `]d` / `[d` | Next / previous problem |
| `gcc` / `gc` | Comment the line / the selection |
| `jk` | Escape |
| `Tab` | Accept the completion |

#### Git

| Key | Action |
|---|---|
| `Space` `gg` | lazygit |
| `Space` `gs` | Stage or unstage this file |
| `Space` `gd` | Diff the working tree |
| `Space` `gb` | Review the whole branch against main |
| `]h` / `[h` | Next / previous change |
| `Space` `ghs` | Stage just this hunk |
| `Space` `uu` | Undo history |
| `Ctrl+H`, `Ctrl+J`, `Ctrl+K`, `Ctrl+L` | Splits, then out into the next pane |

> The one chord worth internalising is `Ctrl+H`, `Ctrl+J`, `Ctrl+K`, `Ctrl+L`.
> It walks Neovim's splits and keeps walking into the next terminal pane when it
> runs out of editor. No prefix, no mode switch, and no thinking about which
> program you are currently inside.

---

## Desktop

`Mod` is the Super key. Windows sit in an endless horizontal strip of columns,
and a column can stack several windows — which is why moving a *column* and
moving a *window* are different keys.

### Launch

| Key | Action |
|---|---|
| `Mod+Space` | Application launcher |
| `Mod+T` | Terminal |
| `Mod+Shift+T` | Coding session |
| `Mod+Shift+P` | Project picker |
| `Mod+S` | Coding spaces (bar widget popout) |
| `Mod+Shift+D` | lazydocker |
| `Mod+F` | File manager |
| `Ctrl+Alt+Delete` | btop |

### Focus and move

| Key | Action |
|---|---|
| `Mod+H` / `Mod+L` | Column left / right |
| `Mod+J` / `Mod+K` | Window down / up inside the column |
| `Mod+Ctrl+H` / `Mod+Ctrl+L` | Move the column |
| `Mod+Ctrl+J` / `Mod+Ctrl+K` | Move the window |
| `Mod+Comma` / `Mod+Period` | Pull a window into the column / push it out |
| `Mod+Home` / `Mod+End` | First / last column |

The arrow keys work anywhere the letters do, and `Mod` plus the scroll wheel
moves as well.

### Size and shape

| Key | Action |
|---|---|
| `Mod+R` | Cycle the column-width presets |
| `Mod+M` | Maximise the column |
| `Mod+Minus` / `Mod+Equal` | Width, ten per cent either way |
| `Mod+Shift+Minus` / `Mod+Shift+Equal` | Height, ten per cent either way |
| `Mod+C` | Centre it |
| `Mod+W` | Tab the column instead of stacking it |
| `Mod+Shift+F` | Fullscreen |

### Workspaces and screens

| Key | Action |
|---|---|
| `Mod+1` … `Mod+9` | Go to a workspace |
| `Mod+Up` / `Mod+Down` | Workspace up / down |
| `Mod+Ctrl+1` … `Mod+Ctrl+9` | Send the column to a workspace |
| `Mod+Ctrl+Up` / `Mod+Ctrl+Down` | Send it up / down |
| `Mod+Shift+H` / `Mod+Shift+L` | Focus the monitor left / right |
| `Mod+Shift+Ctrl+H`, `J`, `K`, `L` | Send the column there |

### Capture and session

| Key | Action |
|---|---|
| `Mod+Shift+S` | Screenshot a region |
| `Print` | The same. `Ctrl+Print` the whole screen, `Alt+Print` the window |
| `Mod+Print` | Read the text off the screen — OCR to the clipboard |
| `Mod+Shift+R` | Start a screen recording, and again to stop |
| `Mod+Shift+V` | Dictate |
| `Mod+Q` | Close the window |
| `Mod+V` | Float it |
| `Mod+Alt+L` | Lock |
| `Mod+N` / `Mod+Shift+N` | Notifications / notepad |
| `Ctrl+Alt+Space` | Next keyboard layout |

---

## Session

Press `Ctrl+G`, let go, then the key. One window holds every project as a
*space*; each space holds tabs; each tab holds panes. Keys below are written
without the prefix.

### Projects

| Key | Action |
|---|---|
| `s` | Space picker — projects and branches, whatever needs you first |
| `shift+w` | New branch worktree, with the tab layout ready |
| `shift+x` | Close a space, showing anything uncommitted before it does |
| `shift+o` | Open an existing worktree |
| `shift+u` | Adopt every repository's worktrees as spaces, in one pass |
| `shift+m` | Ship the branch: push, open the PR, merge it when checks pass |
| `shift+n` | Toggle the layout: three tabs (`main`, `nvim`, `term`), or one split tab |

The space picker refreshes itself while it is open, so progress arrives without
reopening it. A `*` beside the state means that space finished within the last
ten minutes. A checkout nothing has finished in for twelve hours is expired: it
is hidden, and reopening it starts a clean conversation rather than resuming the
old one. Inside the picker, `ctrl+r` rescans for worktrees created elsewhere and
`ctrl+a` shows the expired rows.

`shift+m` is the mechanical half of shipping. It refuses a dirty tree rather
than writing a commit and never deletes a branch; `/worktree-push` is the half
that needs judgement.

`shift+n` reads which layout is applied and gives you the other one, so the
first press on a bare workspace builds the three tabs and every press after it
alternates. Neither direction recreates anything — the panes are moved, so the
agent keeps its conversation and Neovim its unsaved buffers — and neither adds a
tab that is already there.

### Tabs

| Key | Action |
|---|---|
| `m`, `n`, `t` | Jump to `main`, `nvim`, `term` — tabs, or panes in the split layout |
| `c` | New tab |
| `1` … `9` | Tab by number |
| `alt+x` | Close the tab |

Two of these skip the prefix: `ctrl+alt+n` and `ctrl+alt+p` cycle tabs, and
`ctrl+alt+t` jumps to `term`.

In the split layout the same three keys reach panes instead, and `n` and `t`
also hand the right-hand column to whichever of the two you asked for. `m` only
focuses: `main` keeps its third of the width whatever you are working in.

### Panes

| Key | Action |
|---|---|
| `ctrl+h`, `ctrl+j`, `ctrl+k`, `ctrl+l` | Focus, crossing into the editor. No prefix |
| `v` / `h` | Split beside / below |
| `z` | Zoom one pane, and back |
| `x` | Close the pane |
| `plus` | Even the widths out |
| `alt+r` | Resize mode |
| arrows | Focus, staying inside herdr |

### Agents and tools

| Key | Action |
|---|---|
| `a` | Agent picker — read any pane, and send it a prompt with `ctrl+o` |
| `g` | lazygit here |
| `u` | Pick a link out of the scrollback |
| `alt+o` | opencode in a pane |
| `b` | Show or hide the sidebar |
| `?` | Every key, from herdr itself |

---

## Editor

`Space` is the leader, in normal mode. Hold it for a moment and a menu appears
showing what can follow, so the tables below are a head start rather than
something to memorise.

### Files and search

| Key | Action |
|---|---|
| `Space` `Space` | Find a file |
| `Space` `fr` | Recent files |
| `Space` `e` | File tree |
| `Space` `,` | Open buffers |
| `Space` `/` | Search the project |
| `Space` `ss` | Search, seeded with the last thing you looked for |
| `Space` `sw` | Search the word under the cursor |
| `Space` `fi` | What uses this file |
| `Space` `sr` | Search and replace |
| `f` | Search inside this buffer |

### Code

| Key | Action |
|---|---|
| `gd` / `gr` | Definition / references |
| `K` | Documentation |
| `Space` `ca` | Code action |
| `Space` `cr` | Rename symbol |
| `Space` `cf` | Format. Always deliberate here, never on save |
| `Space` `cs` | Outline of this file |
| `]d` / `[d` | Next / previous problem |
| `Space` `xx` | Every problem |

### Editing

| Key | Action |
|---|---|
| `jk` | Escape |
| `s` | Jump to any word on screen |
| `gcc` / `gc` | Comment the line / the selection |
| `gsa`, `gsd`, `gsr` | Add, delete, change surrounding quotes or brackets |
| `Ctrl+A` / `Ctrl+X` | Increment / decrement, including dates and booleans |
| `Alt+J` / `Alt+K` | Move the line or selection |
| `Tab` | Accept the completion |
| `d` | Delete without replacing what you last copied |

### Git and tools

| Key | Action |
|---|---|
| `Space` `gg` | lazygit |
| `Space` `gs` | Stage / unstage this file |
| `Space` `gd` | Diff view |
| `Space` `gb` | Branch review |
| `]h` / `[h` | Next / previous change |
| `Space` `ghs` / `Space` `ghr` | Stage / undo a hunk |
| `Space` `uu` | Undo history |
| `Space` `fy` | Copy this file's path |

> The arrow keys do nothing in Neovim. That is deliberate, so the habit becomes
> `h`, `j`, `k`, `l` — but it also means you cannot arrow along a picker's
> search box. `Space` `uH` turns it off for the session.

---

## Terminal and Apps

### foot

| Key | Action |
|---|---|
| `Control+Shift+c` / `Control+Shift+v` | Copy / paste |
| `Control+Shift+r` | Search the scrollback |
| `Control+Shift+o` | Label every link on screen, then press its letter |
| `Control+plus` / `Control+minus` / `Control+0` | Font size |
| `Control+Shift+z` / `Control+Shift+x` | Jump to the previous / next shell prompt |

### Shell

| Key | Action |
|---|---|
| `Ctrl+R` | Search your history |
| `Ctrl+T` | Insert a file path |
| `Alt+C` | Jump to a directory |
| `Shift+Tab` | Fuzzy complete |
| `pro` | Pick a project and go there |
| `dev nvim` | Neovim with the project's real toolchain |

### lazygit

| Key | Action |
|---|---|
| `?` | Every key |
| `1` … `5` | Status, files, branches, commits, stash |
| `space` | Stage / unstage. `a` for everything |
| `enter` | Stage single lines |
| `c` / `A` | Commit / amend |
| `P` / `p` | Push / pull |
| `z` | Undo |
| `+` / `-` | Bigger / smaller layout |

### lazydocker and btop

| Key | Action |
|---|---|
| `x` | lazydocker: what can I do here |
| `1` … `6` | Projects, services, containers, images, volumes, networks |
| `E` / `m` | Shell into a container / read its logs |
| `b` | Bulk commands, including prune |
| `f` | btop: filter processes |
| `t` / `k` | btop: terminate / kill |
| `h` | btop help — note it is not a motion key there |

---

## When You Are Lost

Five keys that answer the question from inside the program. These are always
right, which no cheatsheet can promise.

`Mod+Slash` is the exception that proves it: it opens this page rather than a
separate list, because `tooling/keybindings/build-cheatsheet.py` generates that
modal from these tables and from the niri binds themselves. Editing this file
and running `just cheatsheet` is how the modal changes; `just validate` fails if
the two have drifted apart.

### From inside the program

| Key | Shows |
|---|---|
| `Mod+Slash` | This page, as a searchable modal |
| `Ctrl+G` then `?` | Every session shortcut |
| `Space` | Wait a beat and the editor lists what can follow |
| `Space` `sk` | Search every editor mapping |
| `?` | lazygit and lazydocker. `x` for lazydocker's context menu |

---

## Where to go next

Keybind ownership, the DMS reclaims, niri's include order and the hotkey
overlay's ordering belong to
[subsystems/desktop-session.md](subsystems/desktop-session.md), which is also
where the launcher binds that reach this image's own scripts are explained. The
editor, the `dev` wrapper, worktree propagation and herdr's role are in
[subsystems/dev-environment.md](subsystems/dev-environment.md). To add or
reclaim a bind rather than look one up, the recipe is in
[cookbooks.md](cookbooks.md); to decide which layer owns your change, read
[conventions.md](conventions.md).
