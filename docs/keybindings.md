# Keybindings

Every key this workstation binds, in one place: the compositor, the terminal
multiplexer, Neovim, the TUI applications and the shell. This is a lookup sheet,
not an explanation — where a binding exists for a reason, the reason lives on
the page that owns the subsystem and is linked from here. Read this when you
have forgotten a key, or after an update moved one.

**Five layers, and each is opened by a single key: `Mod` reaches the
compositor, `Ctrl+G` the multiplexer, `Space` the editor. Learn the three
gateways and the rest is lookup.**

---

## The Five Layers

A chord belongs to exactly one layer, and the layer is decided by whichever
program grabs the key first. The compositor sees every key before the terminal
does; the multiplexer sees its prefix before the pane's process does; inside a
pane the running program sees the rest.

| Layer | Gateway | Owns | Configured in |
|---|---|---|---|
| Desktop | `Mod` | Windows, columns, workspaces, monitors, capture, media | `system_files/usr/share/workstation-os-image/niri/includes/binds.kdl` |
| Session | `Ctrl+G` | Panes, tabs, spaces, worktrees, agents | `system_files/usr/share/workstation-os-image/dotfiles/dot_config/herdr/create_config.toml` |
| Editor | `Space` | Buffers, pickers, LSP, git, everything in a file | `system_files/usr/share/workstation-os-image/dotfiles/dot_config/nvim/lua/config/create_keymaps.lua` and the plugin seeds beside it |
| Applications | varies | foot, lazygit, lazydocker, btop | Mostly stock; the exceptions are noted below |
| Shell | `Ctrl+R` | History, file and directory pickers, project functions | `system_files/usr/share/workstation-os-image/dotfiles/dot_config/fish/conf.d/create_aliases.fish` |

`Mod` is the Super key. `prefix` means `Ctrl+G`, pressed and released before the
next key. `<leader>` is the space bar.

> Never learn a key from this page alone when the machine can tell you.
> `Mod+Slash` opens niri's own overlay, `prefix+?` opens herdr's, `<leader>sk`
> opens a searchable picker of every Neovim mapping, and `?` works in both
> lazygit and lazydocker. Those four are always current; this page is only as
> current as its last edit.

---

## Desktop: `Mod`

niri lays windows out as an endless horizontal strip of columns, and a column
may hold several stacked windows. That geometry is why the bindings separate
*column* movement from *window* movement.

Keybind ownership, the DMS reclaims and the hotkey overlay's ordering belong to
[subsystems/desktop-session.md](subsystems/desktop-session.md), which also
carries the rationale for each launcher bind that reaches one of this image's
own scripts.

### Launching

| Key | Action |
|---|---|
| `Mod+T` | Terminal |
| `Mod+Shift+T` | Coding session — herdr |
| `Mod+Shift+P` | Project picker, then herdr |
| `Mod+Shift+D` | lazydocker |
| `Mod+F` | File manager |
| `Mod+Space` | Application launcher |
| `Ctrl+Alt+Delete` | Activity — btop |

### Windows

| Key | Action |
|---|---|
| `Mod+Q` | Close window |
| `Mod+V` | Toggle floating |
| `Mod+W` | Toggle tabbed column display |
| `Mod+Shift+F` | Fullscreen |
| `Mod+Ctrl+F` | Maximise to edges |
| `Mod+Comma` | Consume window into the column |
| `Mod+Period` | Expel window from the column |
| `Mod+BracketLeft` / `Mod+BracketRight` | Move a window between columns |
| `Mod+Ctrl+R` | Reset window height |
| `Mod+Shift+Minus` / `Mod+Shift+Equal` | Window height, ten per cent either way |

### Columns

| Key | Action |
|---|---|
| `Mod+R` | Cycle the column-width preset |
| `Mod+M` | Maximise column |
| `Mod+Minus` / `Mod+Equal` | Column width, ten per cent either way |
| `Mod+C` | Centre the column |
| `Mod+Ctrl+C` | Centre every visible column |

### Focus

| Key | Action |
|---|---|
| `Mod+H` / `Mod+L` | Column left / right |
| `Mod+Left` / `Mod+Right` | Column left / right |
| `Mod+J` / `Mod+K` | Window down / up inside the column |
| `Mod+Home` / `Mod+End` | First / last column |
| `Mod+O` | Overview |
| `Mod+Slash` | Hotkey overlay |

Scroll works too: `Mod` plus a horizontal wheel moves between columns, `Mod`
plus a vertical wheel moves between workspaces.

### Moving windows

| Key | Action |
|---|---|
| `Mod+Ctrl+H` / `Mod+Ctrl+L` | Move column left / right |
| `Mod+Ctrl+J` / `Mod+Ctrl+K` | Move window down / up |
| `Mod+Ctrl+Home` / `Mod+Ctrl+End` | Move column to first / last position |
| `Mod+Ctrl+Up` / `Mod+Ctrl+Down` | Move column to the workspace above / below |
| `Mod+Ctrl+1` … `Mod+Ctrl+9` | Move column to workspace *n* |

### Workspaces and monitors

| Key | Action |
|---|---|
| `Mod+Up` / `Mod+Down` | Workspace up / down |
| `Mod+I` / `Mod+U` | Workspace up / down |
| `Mod+Page_Up` / `Mod+Page_Down` | Workspace up / down |
| `Mod+1` … `Mod+9` | Go to workspace *n* |
| `Mod+Shift+I` / `Mod+Shift+U` | Move the workspace itself up / down |
| `Mod+Shift+H`, `Mod+Shift+J`, `Mod+Shift+K`, `Mod+Shift+L` | Focus the monitor in that direction |
| `Mod+Shift+Ctrl+H`, `J`, `K`, `L` | Move the column to that monitor |

### Capture, dictation and session

| Key | Action |
|---|---|
| `Mod+Shift+S` | Screenshot a region |
| `Print` / `Ctrl+Print` / `Alt+Print` | Region / whole screen / focused window |
| `Mod+Print` | Screenshot, then OCR the result to the clipboard |
| `Mod+Shift+R` | Start or stop a screen recording |
| `Mod+Shift+V` | Start or stop dictation |
| `Mod+Alt+L` | Lock the screen |
| `Ctrl+Alt+U` | Switch user |
| `Ctrl+Alt+Space` | Cycle the keyboard layout |
| `Mod+Escape` | Toggle shortcut inhibit, so an application can grab keys |
| `Mod+N` / `Mod+Shift+N` | Notification centre / notepad |
| `Mod+Y` | Browse wallpapers |

Volume, mute, microphone mute, media transport and brightness are on their
`XF86` hardware keys and keep working while the screen is locked.

There is deliberately no quit bind.

---

## Session: `Ctrl+G`

herdr is one server with many clients, and **every attached client mirrors every
other one**. A second window is a second view of the same session, not a second
context. That single fact explains most of the design below.

The `dev.flow` plugin that supplies the popups lives in
`system_files/usr/share/workstation-os-image/dotfiles/dot_config/herdr/plugins/dev-flow`.
Its worktree behaviour is owned by
[subsystems/dev-environment.md](subsystems/dev-environment.md).

### Panes

| Key | Action |
|---|---|
| `ctrl+h`, `ctrl+j`, `ctrl+k`, `ctrl+l` | Focus pane, and continue into Neovim splits. No prefix |
| `prefix+left`, `prefix+down`, `prefix+up`, `prefix+right` | Focus pane |
| `prefix+v` | Split vertical |
| `prefix+h` | Split horizontal |
| `prefix+x` | Close pane |
| `prefix+z` or `prefix+enter` | Zoom the pane |
| `prefix+tab` / `prefix+shift+tab` | Cycle panes forward / back |
| `prefix+plus` | Equalise pane widths |
| `prefix+alt+r` | Resize mode |
| `prefix+y` | Copy mode |
| `prefix+u` | URL picker, read from the pane's scrollback |
| `prefix+shift+e` | Edit the scrollback |
| `prefix+shift+p` | Rename the pane |

### Tabs

| Key | Action |
|---|---|
| `prefix+c` | New tab, prompting for a name |
| `ctrl+alt+n` / `ctrl+alt+p` | Next / previous tab. No prefix |
| `prefix+1` … `prefix+9` | Switch to tab *n* |
| `prefix+m` | Focus the tab named `main` |
| `prefix+n` | Focus the tab named `nvim` |
| `prefix+t`, or `ctrl+alt+t` | Focus the tab named `term` |
| `prefix+shift+n` | Build the `main` / `nvim` / `term` layout in this space |
| `prefix+shift+t` | Rename the tab |
| `prefix+alt+x` | Close the tab |

### Spaces and worktrees

| Key | Action |
|---|---|
| `prefix+s` | Space picker: every space, plus on-disk worktrees that have no space yet, sorted so a blocked or finished agent rises |
| `prefix+shift+c` | New workspace |
| `prefix+shift+r` | Rename workspace |
| `prefix+shift+x` | Close the space, or delete a worktree after showing its uncommitted work and asking |
| `prefix+shift+w` | New worktree: prompt for a branch, validate it, create it, apply the layout |
| `prefix+shift+o` | Open an existing worktree |
| `prefix+shift+u` | Adopt every repository's worktrees as spaces |
| `prefix+alt+g` | Goto, which opens navigate mode |

### Agents

| Key | Action |
|---|---|
| `prefix+a` | Agent picker, with a live preview of each pane, sorted blocked, then done, then idle, then working |
| `prefix+alt+o` | Run opencode in a pane |

Inside that picker: `enter` focuses, `ctrl+o` sends the agent a prompt,
`ctrl+d` and `ctrl+u` scroll the preview, and `ctrl+s` then `a` closes it.

### Session and tools

| Key | Action |
|---|---|
| `prefix+?` | Built-in keybinding help |
| `prefix+g` | lazygit, at the focused pane's repository root |
| `prefix+b` | Toggle the sidebar |
| `prefix+r` | Reload the config |
| `prefix+shift+s` | Settings |
| `prefix+q` | Detach |

### Navigate mode

Live only while the `prefix+alt+g` overlay is open, and deliberately inverted
from herdr's own defaults.

| Key | Action |
|---|---|
| `j` / `k` | Walk spaces down / up |
| `up` / `down` | Walk panes up / down |
| `h` / `l` | Pane left / right |
| `esc` | Leave |

### Keys the cascade left dead

The scheme is a cascade: four actions are parked on chords nobody presses
because plugin popups replace them, and freeing those keys is what lets the rest
of the block shift along. Stock herdr muscle memory therefore hits nothing.

| Stock key | Was | Now reach it with |
|---|---|---|
| `prefix+w` | Workspace picker | `prefix+s` |
| `prefix+shift+d` | Close workspace | `prefix+shift+x` |
| `prefix+shift+g` | New worktree | `prefix+shift+w` |
| `prefix+p`, `prefix+e`, `prefix+j`, `prefix+k`, `prefix+l`, `prefix+minus` | Various | Unbound; see the tables above |

---

## Editor: `Space`

`<leader>` is the space bar. Neovim is LazyVim with the snacks picker and
blink completion; the tables below separate what this configuration adds from
the stock bindings worth remembering.

Everything in the first table is Neovim-only. The JetBrains IDEs get LazyVim's
*stock* set and nothing above it, through
`system_files/usr/share/workstation-os-image/dotfiles/create_dot_ideavimrc`,
which [subsystems/dev-environment.md](subsystems/dev-environment.md) explains.

### What this configuration adds

| Key | Action |
|---|---|
| `jk` | Escape, from insert mode |
| `f` | Buffer search — remapped to `/` |
| `d`, `D`, and `d` in visual mode | Delete without touching the unnamed register |
| `p` in visual mode | Paste over a selection; the register survives |
| `Tab` | Accept a completion. `Enter` inserts a newline instead |
| `Ctrl+j` / `Ctrl+k` | Move through the completion and command-line lists |
| `Ctrl+h`, `Ctrl+j`, `Ctrl+k`, `Ctrl+l` | Window, then herdr pane, in one chord |
| `<leader>sv` / `<leader>sx` | Split vertical / close split |
| `<leader>S` | Global grep, whatever the working directory |
| `<leader>ss` | Sticky root grep, seeded with the last search |
| `<leader>fs` | Grep the visual selection, literally |
| `<leader>fi` | Which files reference this one |
| `<leader>fy` / `<leader>fY` | Yank the buffer path, relative or absolute |
| `<leader>sr` / `<leader>sR` | Search and replace, this file or the whole root |
| `<leader>sy` | LSP symbols, moved off `<leader>ss` |
| `<leader>gs` | Stage or unstage the current file |
| `<leader>gd` | Diffview |
| `<leader>gb` | Branch review against `main`, toggling |
| `<leader>gH` / `<leader>gx` | File history / close the diff view |
| `<leader>n` | Volatile scratch buffer that scrubs the registers on close |
| `<leader>H` | Close every buffer and open the dashboard |
| `<leader>br` | Reload the buffer from disk |
| `<leader>uu` | Undo tree |
| `<leader>DD` | lazydocker |
| `<leader>uH` / `<leader>uR` | Hardtime toggle / report |

In the Diffview panel `<leader>gs` stages the entry under the cursor and `e`
opens the real file, revealing it in the explorer. In the file explorer, `gs`
stages the file under the cursor and `<leader>fy` copies its path.

### Stock LazyVim worth knowing

| Key | Action |
|---|---|
| `<leader><space>` | Find files |
| `<leader>fr` / `<leader>e` / `<leader>,` | Recent files / explorer / buffer picker |
| `<leader>/` | Grep the root directory |
| `<leader>sw` | Grep the word under the cursor |
| `<leader>sk` | Keymap picker, searchable |
| `s` / `S` | Flash jump / flash treesitter |
| `Shift+h` / `Shift+l` | Previous / next buffer |
| `<leader>bd` | Delete the buffer |
| `gd`, `gr`, `gI`, `gy` | Definition, references, implementation, type |
| `K` / `gK` | Hover documentation / signature |
| `<leader>ca` / `<leader>cr` | Code action / rename symbol |
| `<leader>cf` | Format — manual here, because format-on-save is off |
| `<leader>cs` | Symbol outline |
| `]d` / `[d` | Next / previous diagnostic |
| `<leader>xx` | Diagnostics list |
| `gcc` / `gc` | Comment the line / the selection |
| `gsa`, `gsd`, `gsr` | Add, delete, replace a surrounding pair |
| `Ctrl+a` / `Ctrl+x` | Increment / decrement numbers, dates and booleans |
| `Alt+j` / `Alt+k` | Move the line or selection |
| `<leader>gg` | lazygit |
| `<leader>ghs` / `<leader>ghr` / `<leader>ghp` | Stage / reset / preview a hunk |
| `]h` / `[h` | Next / previous hunk |
| `Ctrl+Slash` | Terminal |
| `<leader>tr` / `<leader>tt` | Run the nearest test / the file |
| `<leader>db` / `<leader>dc` | Toggle breakpoint / continue |
| `<leader>D` | Database UI |

### hardtime blocks the arrow keys

`Up`, `Down`, `Left` and `Right` do nothing in normal, visual and insert mode.
That is a hard block, not a hint, and it is not governed by the plugin's
`restriction_mode`. `h`, `j`, `k` and `l` only produce a suggestion after four
presses inside a second, and are never swallowed.

Arrows still work in Diffview, undotree, the dashboard, help, mason, trouble,
aerial and the picker prompts, and `Ctrl` plus an arrow still resizes a window.
`<leader>uH` turns the whole thing off.

### One chord crosses Neovim and herdr

`Ctrl+h`, `Ctrl+j`, `Ctrl+k` and `Ctrl+l` are bound on both sides, and both
halves are required.

herdr asks whether the focused pane is running Neovim or fzf. If it is, the key
is forwarded into the pane; if it is not, herdr moves pane focus itself. Neovim,
receiving the forwarded key, moves between its own windows — and only when the
window did not change, meaning the cursor was already at the edge of the layout,
does it ask herdr to move to the next pane. The Neovim half is
`system_files/usr/share/workstation-os-image/dotfiles/dot_config/nvim/lua/plugins/create_navigation.lua`.

That is why herdr's own pane focus sits on `prefix` plus the arrow keys: bare
`ctrl+h` and friends were claimed for this.

---

## Terminal and TUI Applications

### foot

foot ships entirely stock — no `[key-bindings]` section is defined in
`system_files/usr/share/workstation-os-image/dotfiles/dot_config/foot/create_workstation.ini.tmpl`
or in any file it includes.

| Key | Action |
|---|---|
| `Control+Shift+c` / `Control+Shift+v` | Copy / paste |
| `Shift+Insert` | Paste the primary selection |
| `Control+Shift+r` | Search the scrollback |
| `Control+Shift+o` | URL mode, which jump-labels every link |
| `Control+Shift+u` | Unicode input by codepoint |
| `Control+Shift+n` | New terminal |
| `Shift+Page_Up` / `Shift+Page_Down` | Scroll a page |
| `Control+plus` / `Control+minus` / `Control+0` | Font larger / smaller / reset |
| `Control+Shift+z` / `Control+Shift+x` | Jump to the previous / next shell prompt |

In search mode, `Control+r` and `Control+s` step between matches and `Return`
commits the match to the *primary* selection; use `Control+Shift+c` for the
regular clipboard.

### lazygit

Four bindings are overridden in
`system_files/usr/share/workstation-os-image/dotfiles/dot_config/lazygit/create_config.yml`;
everything else is stock.

| Key | Action |
|---|---|
| `?` | Keybinding menu, which is always the fastest answer |
| `1` … `5` | Status, files, branches, commits, stash |
| `+` / `-` | Larger / smaller screen mode |
| `space` | Stage or unstage; `a` stages everything |
| `enter` | Stage individual lines |
| `c` / `A` / `C` | Commit / amend / commit in the git editor |
| `d` / `D` | Discard / reset |
| `s` / `S` | Stash / stash options |
| `P` / `p` | Push / pull |
| `z` / `Z` | Undo / redo |
| `m` | Merge and rebase options |
| `w` | New worktree |
| `_` | Check out the previous branch |
| `/` | Filter the current view |
| `:` | Run a shell command |

`-` is the shrink half of the screen-mode pair, mirroring `+`. Taking it cost
the file tree's collapse-all and expand-all, which are now unbound, and pushed
checkout-previous-branch onto `_`. Per-directory collapse still works with
`enter`, and `` ` `` still toggles the tree view.

### lazydocker

| Key | Action |
|---|---|
| `x` | Context menu for the focused panel |
| `1` … `6` | Projects, services, containers, images, volumes, networks |
| `[` / `]` | Previous / next tab within the main panel |
| `E` | Exec a shell in the container |
| `a` / `m` | Attach / view logs |
| `s`, `r`, `p`, `d` | Stop, restart, pause, remove |
| `u` / `D` | Compose up / down the project |
| `b` | Bulk commands, where the prune actions live |
| `w` | Open in the browser |

### btop

| Key | Action |
|---|---|
| `h` or `?` | Help; `Esc` or `m` opens the menu |
| `p` / `Shift+p` | Cycle the three configured presets |
| `1`, `2`, `3`, `4` | Toggle the CPU, memory, network and process boxes |
| `f` or `/` | Filter processes; prefix with `!` for a regex |
| `e` / `E` | Tree view / expand every node |
| `t` / `k` | Terminate / kill the selected process |
| `Shift+n` | Renice |
| `Enter` / `F` | Process detail / follow the process |
| `c` / `r` | Per-core view / reverse the sort |

`vim_keys` is off, so in btop `h` is help and `k` is kill. Neither is motion.

---

## Shell

No key bindings are written by hand. Every chord below comes from fzf's own
fish integration, and `cd` is zoxide.

| Key | Action |
|---|---|
| `Ctrl+r` | Fuzzy history search |
| `Ctrl+t` | Pick a file and insert its path |
| `Alt+c` | Pick a directory and change into it |
| `Shift+Tab` | Fuzzy completion |

The functions and aliases that act as commands are inventoried in
[subsystems/dev-environment.md](subsystems/dev-environment.md) and
[subsystems/ai-clis.md](subsystems/ai-clis.md); the ones worth memorising are
`pro` to pick a project, `dev` and `dev nvim` to work inside a project's Dev
Container, and `nv` when you want whichever of the two applies.

---

## What Your Fingers Get Wrong

Muscle memory fails silently here, because a retired chord almost always does
nothing rather than complaining. These are the ones worth drilling.

| You press | It used to | It now |
|---|---|---|
| `Ctrl+b` | Open the herdr prefix | Nothing. The prefix is `Ctrl+G` |
| `prefix+h`, `prefix+j`, `prefix+k`, `prefix+l` | Focus a pane | `prefix+h` splits; the rest are unbound. Pane focus is on `prefix` plus arrows |
| `prefix+minus` | Split horizontal | Nothing. Splitting horizontally is `prefix+h` |
| `prefix+n` / `prefix+p` | Cycle tabs | Focus the `nvim` tab / nothing. Cycling is `ctrl+alt+n` and `ctrl+alt+p` |
| `ga` / `gd` in a shell | Create / remove a worktree | Nothing; both functions were removed. Use `prefix+shift+w` and `prefix+shift+x`, or plain `git worktree add` outside herdr |
| `f` in Neovim | Find a character forward | Buffer search. The character motions are `t`, `F`, `T`, `;` and `,` |
| `d` in Neovim | Delete into the unnamed register | Delete into the black hole. Name a register to cut: `"add` |
| `<leader>ss` | LSP symbols | Sticky root grep. Symbols moved to `<leader>sy` |
| An arrow key in Neovim | Move the cursor | Nothing. hardtime blocks all four |
| `_` in lazygit | Shrink the screen mode | Check out the previous branch. Shrinking is `-` |
| `-` / `=` in the lazygit file tree | Collapse / expand everything | Nothing; both were released |

Four chords mean different things in different layers, which is the price of
five keyspaces sharing one keyboard:

| Chord | Meaning by layer |
|---|---|
| `<leader>gs` | Stage the file in Neovim; open the commit window in the JetBrains IDEs |
| `f` | Buffer search in Neovim; flash find in the JetBrains IDEs |
| `h`, `j`, `k`, `l` | Motion in Neovim; monitors under `Mod+Shift`; help and kill in btop |
| `<leader>D` | Database UI, and it waits for a second `D` before firing lazydocker |

---

## Where to go next

Keybind ownership, the DMS reclaims, niri's include order and the hotkey
overlay's three-tier ordering are owned by
[subsystems/desktop-session.md](subsystems/desktop-session.md). The editor,
the `dev` wrapper, worktree propagation and herdr's role belong to
[subsystems/dev-environment.md](subsystems/dev-environment.md). To add or
reclaim a bind rather than look one up, the recipe is in
[cookbooks.md](cookbooks.md), and the rule for deciding which layer owns your
change is in [conventions.md](conventions.md).
