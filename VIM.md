# Vim on this workstation

Neovim runs stock LazyVim. PhpStorm, WebStorm, DataGrip, IntelliJ and PyCharm run
the same keys through IdeaVim. This is the map for both, and the order to learn
them in.

Keys written `<leader>ff` mean: press <kbd>Space</kbd>, then `f`, then `f`. Press
<kbd>Space</kbd> and wait — a menu appears in both editors, so none of this has to
be memorised.

- [The stack, briefly](#the-stack-briefly)
- [The one idea](#the-one-idea)
- [First four weeks](#first-four-weeks)
- [Cheatsheet](#cheatsheet)
- [Leader map](#leader-map)
- [Keys without the leader](#keys-without-the-leader)
- [Daily flows](#daily-flows)
- [JetBrains transition](#jetbrains-transition)
- [When stuck](#when-stuck)
- [Where the config lives](#where-the-config-lives)

## The stack, briefly

**Neovim** is the editor. **LazyVim** is a preconfigured starting point on top of
it — it bundles a plugin manager, sensible defaults, and a `<leader>` menu, so you
get an IDE-shaped setup without assembling one. An **extra** is a LazyVim feature
pack you switch on; this machine enables a fixed list rather than letting the UI
add them.

**Two tiers of Neovim.** Host `nvim` is for git, quick edits and repos with no
container. `dev nvim` (or just `nv`) runs the same config *inside* the project's
Dev Container, because language servers, debuggers and test runners need the real
`vendor/`, `node_modules` and site-packages, which only exist in there. It also
only installs the languages that project actually uses.

**What is installed, in plain terms:**

| Area | Plugins | What you notice |
| --- | --- | --- |
| Finding things | snacks picker, snacks explorer | fuzzy file/text search, file tree |
| Code intelligence | nvim-lspconfig, Mason, treesitter | go-to-definition, errors, syntax |
| Jumping | flash.nvim | `s` plus two characters, labelled targets |
| Editing | mini.surround, mini.ai, mini.pairs, vim-abolish, dial, yanky | brackets, text objects, case coercion, a yank history |
| Git | gitsigns, lazygit, diffview, git-conflict | hunks in the gutter, a full git UI, side-by-side diffs |
| Testing & debug | neotest, nvim-dap | run tests and set breakpoints in the editor |
| Reading code | illuminate, aerial, mini-hipatterns | highlights the symbol under the cursor, an outline |
| SQL & HTTP | vim-dadbod, kulala | query a database, send HTTP requests from a file |
| Learning aids | hardtime, precognition | coaching, removable once the habits stick |

**In the IDEs**, IdeaVim provides the modal editing and four Marketplace plugins
fill the gaps: Which-Key (the `<leader>` menu), vim-flash (`s`/`S`), Vim Dial
(`<C-a>`), and IdeaVim's own built-in emulations of surround, commentary, abolish
and friends.

**Nothing formats on save.** `<leader>cf` is the only thing that reformats a file,
in both editors. This is deliberate: a formatter resolved on the host must not
silently rewrite code a container owns.

## The one idea

Vim is a language. You type a **verb** and then a **noun**, and every verb
combines with every noun. Six verbs and eight nouns give you forty-eight commands
nobody taught you.

| Verbs | | Nouns | |
| --- | --- | --- | --- |
| `d` | delete | `w` | to the next word |
| `c` | change (delete, then insert) | `iw` | inside the word |
| `y` | yank (copy) | `i"` | inside the quotes |
| `v` | select | `i(` | inside the parens |
| `>` `<` | indent, dedent | `ip` | inside the paragraph |
| `gc` | comment | `t;` | up to the next `;` |

So `diw` deletes a word, `ci"` replaces a string, `ya(` copies a call with its
parens, `>ip` indents a paragraph. You never learned `ci"` — you derived it.

**`.` repeats the last change.** This is the payoff, and it is why Vim users
shrug at multi-cursor: change one occurrence with `ciw`, then `n` to the next
match and `.` to repeat, looking at each one before you commit.

The corollary: prefer a verb over a selection. `dt)` beats a mouse drag, because
`.` can repeat it and a drag cannot.

## First four weeks

Adapted from Peter Jang's much-copied plan, shortened because the setup work is
already done. The rule that matters: **do not reach for a plugin to avoid
learning a motion.**

**Week 1 — `:Tutor`, and nothing else.** Open `nvim`, run `:Tutor`, work through
it. About 30 minutes. Do it once a day for a week; by day five aim to finish in
under ten. Keep working in PhpStorm as normal. Do not try to be fast.

**Week 2 — real work, in the IDE, with vim keys on.** IdeaVim is already
installed, so this costs nothing but patience. Navigate with `w b e 0 ^ $ { } gg
G` instead of arrows and the mouse. Expect to be slow, and use the mouse when a
deadline says so. The arrow keys are blocked in Neovim but not in the IDE, on
purpose — the IDE stays usable while you are still bad at this.

**Week 3 — composition.** Stop moving and then editing; start combining. `ciw`,
`ci"`, `di(`, `ct,`, `ya{`, `>ip`, `dap`, then `.` and `/` + `n`. Run
`:Hardtime report` at the end of each day — it ranks the habits you actually
triggered, which beats a generic list.

**Week 4 — open Neovim for real.** Pick one project and use `nv` for a week. This
is where the things IdeaVim cannot teach live: the quickfix list, `:%s`, macros,
buffers as a real concept. Then keep both — the IDE is better at large refactors,
step debugging and databases; Neovim is better at everything that is text.

Two things people cargo-cult: relative line numbers are a preference (they are on
here; `<leader>uL` turns them off), and disabling arrow keys only helps if you are
actually composing operators with text objects.

## Cheatsheet

Everything in this section is plain Vim and works identically in both editors.

### Modes

| Key | Does |
| --- | --- |
| `Esc` | back to normal mode; also clears the search highlight |
| `i` / `a` | insert before / after the cursor |
| `I` / `A` | insert at the start / end of the line |
| `o` / `O` | open a line below / above |
| `v` / `V` | visual, visual line |
| `Ctrl-v` | visual block (column selection) |
| `gv` | reselect the last selection |
| `:` | command line |

### Moving

| Key | Does |
| --- | --- |
| `h` `j` `k` `l` | left, down, up, right |
| `w` / `b` / `e` | next word / back a word / end of word |
| `W` / `B` / `E` | same, but whitespace-separated |
| `0` / `^` / `$` | line start / first non-blank / line end |
| `f{char}` / `t{char}` | to / just before the next char on this line |
| `F{char}` / `T{char}` | the same, backwards |
| `;` / `,` | repeat the last `f`/`t` forward / backward |
| `{` / `}` | previous / next blank line |
| `gg` / `G` | top / bottom of the file |
| `{n}G` | go to line n |
| `%` | jump to the matching bracket |
| `Ctrl-d` / `Ctrl-u` | half a screen down / up |
| `Ctrl-f` / `Ctrl-b` | a full screen down / up |
| `zz` / `zt` / `zb` | centre / top / bottom the current line |
| `Ctrl-o` / `Ctrl-i` | back / forward through where you have been |
| `{n}j` | any motion takes a count |

### Text objects

Used after a verb. `i` is "inside", `a` is "around" (includes the delimiters).

| Object | Is |
| --- | --- |
| `iw` / `aw` | word / word plus trailing space |
| `is` / `as` | sentence |
| `ip` / `ap` | paragraph |
| `i"` `i'` `` i` `` | inside the quotes |
| `i(` `i[` `i{` | inside the brackets |
| `it` / `at` | inside an HTML/XML tag |
| `ii` / `ai` | indent block — the Python and YAML workhorse |
| `aq` / `ab` | any quote / any bracket, without picking the type |
| `ag` / `ig` | the whole buffer |
| `ih` | a git hunk (Neovim only) |
| `af` / `if` | a whole function — in the IDEs the same object is `am` / `im` |
| `ac` | a whole class (IDE only) |

### Editing

| Key | Does |
| --- | --- |
| `x` / `r{char}` | delete a character / replace it |
| `dd` / `yy` / `cc` | whole line: delete, copy, change |
| `D` / `C` / `Y` | to end of line: delete, change, yank |
| `p` / `P` | paste after / before |
| `u` / `Ctrl-r` | undo / redo |
| `J` | join this line with the next |
| `~` | flip the case of a character |
| `gU{motion}` / `gu{motion}` | uppercase / lowercase |
| `>>` / `<<` | indent / dedent the line |
| `Ctrl-a` / `Ctrl-x` | increment / decrement the number under the cursor |
| `g Ctrl-a` | in a selection, make an ascending sequence |
| `Alt-j` / `Alt-k` | move the line or selection down / up |

### Search and replace

| Key | Does |
| --- | --- |
| `/text` / `?text` | search forward / backward |
| `n` / `N` | next / previous match |
| `*` / `#` | search the word under the cursor, forward / back |
| `:%s/old/new/g` | replace in the file; add `c` to confirm each |
| `:%s/old/new/gc` | ...with confirmation |
| `:'<,'>s/old/new/g` | replace in the selection |
| `:S/old/new/g` | case-aware: `fooBar`→`bazQux` **and** `FooBar`→`BazQux` |
| `cgn` then `.` | change the next match, then repeat. The multi-cursor replacement. |

### Registers, marks, macros

| Key | Does |
| --- | --- |
| `"ayy` / `"ap` | yank into register `a` / paste from it |
| `"+y` / `"+p` | the system clipboard |
| `:reg` | list the registers |
| `ma` then `` `a `` | set mark `a`, jump back to it |
| `qa` … `q` | record a macro into `a` |
| `@a` / `@@` | play it / play the last one |
| `10@a` | play it ten times |

### Surround, comment, case

| Key | Does |
| --- | --- |
| `gsa{motion}{char}` | surround — `gsaiw"` wraps the word in quotes |
| `gsd{char}` | delete the surrounding character |
| `gsr{old}{new}` | replace the surrounding character |
| `gcc` / `gc{motion}` | comment the line / a motion |
| `gco` / `gcO` | new comment line below / above |
| `crs` `crc` `crm` | snake_case, camelCase, MixedCase |
| `cru` `cr-` `cr.` | UPPER_CASE, dash-case, dot.case |

### Flash — learn this one first

| Key | Does |
| --- | --- |
| `s{char}{char}` | every match gets a letter label; press it to jump |
| `S` | select the syntax node under the cursor, then labels for each enclosing one |
| `f` `t` `F` `T` | the plain find, but candidates are highlighted before you commit |
| `d` `r` `{label}` | operate somewhere else without moving there |

### Windows and files

| Key | Does |
| --- | --- |
| `Ctrl-w` `s` / `v` | split horizontally / vertically |
| `Ctrl-h` `j` `k` `l` | move between splits |
| `Ctrl-w` `=` | even out the splits |
| `Ctrl-w` `q` | close this split |
| `Shift-h` / `Shift-l` | previous / next open file |
| `[b` / `]b` | the same |
| `Ctrl-^` | back to the file you were just in |

## Leader map

The leader is <kbd>Space</kbd>. Tags mark where a key exists in only one editor.

### Top level

| Key | Does | |
| --- | --- | --- |
| `<leader><space>` | find file | |
| `<leader>/` | search across the project | |
| `<leader>,` | switch open file | |
| `<leader>:` | command history | |
| `<leader>e` | file tree | |
| `<leader>-` / `<leader>\|` | split below / right | |
| `<leader>p` | paste from the yank history | |
| `<leader>K` | look up the word under the cursor | nvim |

### `f` — file and find

| Key | Does | |
| --- | --- | --- |
| `<leader>ff` | find file (project root) | |
| `<leader>fF` | find file (current dir) | |
| `<leader>fg` | find a tracked file | nvim |
| `<leader>fr` | recent files | |
| `<leader>fb` | open buffers | |
| `<leader>fn` | new file | |
| `<leader>fe` / `<leader>fE` | file explorer, root / current dir | |
| `<leader>ft` / `<leader>fT` | terminal, root / current dir | |
| `<leader>fp` | switch project | |
| `<leader>fc` | open the Neovim config | nvim |

### `s` — search

| Key | Does | |
| --- | --- | --- |
| `<leader>sg` / `<leader>sG` | grep the project / current dir | |
| `<leader>sw` | grep the word under the cursor | |
| `<leader>sr` | search and replace across files | |
| `<leader>sb` | search within this file | |
| `<leader>ss` / `<leader>sS` | symbols in this file / the project | |
| `<leader>sj` | recent cursor positions | |
| `<leader>sd` | diagnostics | |
| `<leader>st` | TODO comments | |
| `<leader>sm` | marks | |
| `<leader>s"` | registers | nvim |
| `<leader>sh` | help pages | nvim |
| `<leader>sk` | search every keymap | nvim |
| `<leader>sq` / `<leader>sl` | quickfix / location list | nvim |
| `<leader>sR` | reopen the last search | nvim |
| `<leader>su` | undo history | nvim |
| `<leader>snh` | messages you missed | nvim |

### `c` — code

| Key | Does | |
| --- | --- | --- |
| `<leader>ca` | code action / quick fix | |
| `<leader>cA` | source action | |
| `<leader>cr` | rename symbol | |
| `<leader>cR` | rename file | |
| `<leader>cf` | format (nothing formats on save) | |
| `<leader>co` | organise imports | |
| `<leader>cd` | explain the error on this line | |
| `<leader>cs` | outline / structure | |
| `<leader>cl` | language server status | nvim |
| `<leader>cm` | Mason — install a language server | nvim |

### `g` — git

| Key | Does | |
| --- | --- | --- |
| `<leader>gg` / `<leader>gG` | lazygit, repo root / current dir | nvim |
| `<leader>gs` | status / commit | |
| `<leader>gb` | blame this line | |
| `<leader>gf` | history of this file | |
| `<leader>gl` | git log | |
| `<leader>gd` | diff the working tree | nvim |
| `<leader>gB` | open in the browser (nvim) / branches (IDE) | |
| `<leader>gv` / `<leader>gV` | side-by-side diff, file history | nvim |
| `<leader>gi` / `<leader>gp` | GitHub issues / pull requests | nvim |

### `gh` — git hunks

| Key | Does | |
| --- | --- | --- |
| `<leader>ghs` / `<leader>ghr` | stage / reset this hunk | stage is nvim only |
| `<leader>ghS` / `<leader>ghR` | stage / reset the whole file | nvim |
| `<leader>ghu` | undo the last stage | nvim |
| `<leader>ghp` | preview the hunk inline | nvim |
| `<leader>ghb` / `<leader>ghB` | blame this line / the file | nvim |
| `<leader>ghd` | diff this file | |

### `b` `w` `q` — buffers, windows, quit

| Key | Does | |
| --- | --- | --- |
| `<leader>bd` | close this file | |
| `<leader>bo` | close all the others | |
| `<leader>bb` | back to the previous file | |
| `<leader>wd` | close this split | |
| `<leader>wm` | maximise this split | |
| `<leader>qq` | quit everything | |
| `<leader>qs` | restore the last session | nvim |

### `d` `t` — debug and test

| Key | Does | |
| --- | --- | --- |
| `<leader>db` / `<leader>dB` | toggle breakpoint / set a condition | |
| `<leader>dc` | start or continue | |
| `<leader>di` / `<leader>dO` / `<leader>do` | step into / over / out | |
| `<leader>dC` | run to the cursor | |
| `<leader>de` | evaluate an expression | |
| `<leader>dt` | stop | |
| `<leader>du` | the debugger panel | |
| `<leader>tr` / `<leader>tt` | run the nearest test / the file's tests | |
| `<leader>tl` | run the last one again | |
| `<leader>td` | debug the nearest test | |
| `<leader>ts` | the test panel | |

### `x` — problems

| Key | Does | |
| --- | --- | --- |
| `<leader>xx` / `<leader>xX` | all problems / this file's | |
| `<leader>xq` / `<leader>xl` | quickfix / location list | nvim |
| `<leader>xt` | TODO comments | nvim |

### `u` — toggles

| Key | Does | |
| --- | --- | --- |
| `<leader>uw` | line wrap | |
| `<leader>ul` / `<leader>uL` | line numbers / relative numbers | |
| `<leader>uz` | zen mode | |
| `<leader>ud` | diagnostics | nvim |
| `<leader>uf` / `<leader>uF` | format on save, globally / this file | nvim |
| `<leader>us` | spellcheck | nvim |
| `<leader>ug` | indent guides | nvim |
| `<leader>uh` | inlay hints | |
| `<leader>ub` | light / dark background | nvim |
| `<leader>uC` | pick a colourscheme | nvim |
| `<leader>ui` / `<leader>uI` | inspect the highlight / the syntax tree | nvim |
| `<leader>uH` / `<leader>uR` | hardtime on-off / its report | nvim |
| `<leader>uv` / `<leader>uV` | motion hints / peek at them once | nvim |

## Keys without the leader

### Code intelligence

| Key | Does |
| --- | --- |
| `gd` | go to definition |
| `gr` | find usages |
| `gI` | go to implementation |
| `gy` | go to type definition |
| `K` | documentation for what is under the cursor |
| `gK` | signature help |
| `]]` / `[[` | next / previous use of this symbol |

### Paired jumps

| Key | Does |
| --- | --- |
| `]d` / `[d` | next / previous problem |
| `]e` / `[e` | next / previous error only |
| `]w` / `[w` | next / previous warning only |
| `]h` / `[h` | next / previous changed hunk |
| `]t` / `[t` | next / previous TODO comment |
| `]q` / `[q` | next / previous quickfix item (nvim) |
| `]y` / `[y` | cycle back through the yank history (nvim) |

### Selection

| Key | Does |
| --- | --- |
| `Ctrl-Space` | grow the selection to the enclosing syntax node (nvim) |
| `Backspace` | shrink it back (nvim) |
| `S` | the same idea in the IDE, with labels |

Inside tmux, `Ctrl-Space` is the prefix — press it twice to pass it through, or
use `S`, which is better anyway.

## Daily flows

### Starting work

```bash
pro                 # pick a project and cd into it
nv                  # Neovim — inside the project's dev container if it has one
dev nvim            # force the container one
dev                 # a shell inside the container
dev npm test        # run one command in the container
```

Use `nv` for anything with a `.devcontainer`. Host Neovim cannot see the
container's `vendor/` or `node_modules`, so code intelligence will be quietly
wrong. The first launch per container takes a few minutes while it provisions
Neovim, Node and the language servers; after that it is fast.

### Git

| Do this | With |
| --- | --- |
| Everything, interactively | `<leader>gg` (lazygit) |
| Stage a hunk while editing | `<leader>ghs` |
| Walk your changes | `]h` / `[h` |
| See a hunk without leaving the file | `<leader>ghp` |
| Full side-by-side diff | `<leader>gv` |
| Who wrote this line | `<leader>gb` |

In lazygit: <kbd>Space</kbd> stages, `c` commits, `P` pushes, `p` pulls, `s`
stashes, `z` undoes, `?` shows everything else.

### Worktrees

A worktree is a second checkout of the same repo on its own branch, in its own
directory — so you can work on two branches at once without stashing. Untracked
files a project needs (`.env`, `.idea/`) do not come along by default; every path
below copies them from the repo's committed `.worktreeinclude`.

**From the shell** — quickest, no tmux involved:

```bash
ga my-branch        # create ../repo--my-branch, cd into it, copy the untracked files
gd                  # remove this worktree and delete its branch (asks first)
```

**From an AI CLI** — these are slash commands in Claude Code, Codex and opencode:

```
/worktree-create    # asks for a branch name, then creates the worktree,
                    # a tmux window, and starts an agent in it
/worktree-push      # commit, open a PR, merge it, and clean everything up
/worktree-remove    # tear down a worktree without merging
```

Claude Code's own `--worktree` flag and its subagent isolation read the same
`.worktreeinclude`, so those are covered too.

**From workmux directly**, when you want the tmux layout — an agent pane, an
editor pane and a shell:

```bash
workmux add my-branch     # worktree + tmux window + panes
workmux list              # what exists
workmux open my-branch    # reopen its window
workmux merge my-branch   # squash-merge and clean up
workmux rm my-branch      # remove without merging
workmux dashboard         # status of every agent
workmux resurrect         # restore windows after a crash
```

**From JetBrains**, "New Worktree" fires a git hook that does the copy; the
"Sync worktree files" External Tool is the manual fallback.

To onboard a repo that has no `.worktreeinclude` yet:

```bash
just worktree-init          # this repo
just worktree-init --all    # every repo under ~/projects
```

> `gd` in the shell removes a worktree. `gd` in the editor goes to a definition.
> Same two letters, very different outcomes.

### tmux and workmux

| Key | Does |
| --- | --- |
| `Alt-Enter` / `Alt-Shift-Enter` | split below / right |
| `Alt-Escape` | close the pane |
| `Ctrl-Alt` + arrows | move between panes |
| `Alt-1` … `Alt-9` | jump to a window |
| `Alt-Left` / `Alt-Right` | previous / next window |
| `Alt-Up` / `Alt-Down` | previous / next session |
| `Ctrl-Space` `?` | the full cheatsheet in a popup |
| `Ctrl-Space` `z` | zoom this pane |
| `Ctrl-Space` `[` | scroll back; `v` selects, `y` copies |

### Keeping it running

| Command | When |
| --- | --- |
| `:Lazy` | plugin status; `U` updates, `X` cleans |
| `:Mason` | install or update a language server |
| `:checkhealth` | something is broken and you want to know why |
| `:LazyExtras` | see which LazyVim extras exist — but add them in the repo, not here |

## JetBrains transition

The IDEs mirror LazyVim. The keys you press are the same; what happens underneath
differs, and a few things the IDE has no concept of.

### Genuinely identical

Modes, all motions, all operators, text objects, registers, marks, macros, `.`,
`:%s`, `/` and `n`, surround, comments, case coercion, and the whole `<leader>`
tree above. That is most of what you do in a day.

### Who owns which Ctrl key

Both the IDE and Vim want these. The config decides, so you never see a conflict
dialog.

| Key | Goes to | Because |
| --- | --- | --- |
| `Ctrl-d` `Ctrl-u` `Ctrl-f` `Ctrl-b` | Vim | scrolling. Duplicate line is `yyp` now. |
| `Ctrl-o` `Ctrl-i` `Ctrl-r` | Vim | jump list and redo |
| `Ctrl-w` `Ctrl-h/j/k/l` | Vim | window commands |
| `Ctrl-y` `Ctrl-e` `Ctrl-t` | Vim | scroll, tag stack |
| `Ctrl-v` | Vim in normal, IDE while typing | block select vs paste |
| `Ctrl-a` `Ctrl-x` | Vim in normal, IDE while typing | increment vs select-all |
| `Ctrl-c` | IDE in normal, Vim while typing | copy stays copy, abort stays abort |
| `Ctrl-Space` `Ctrl-s` `Ctrl-z` `Ctrl-g` | IDE | completion, save, undo, go to line |

### What does not transfer

- **The quickfix list.** `:copen`, `]q`, and the whole grep-then-walk-the-results
  workflow do not exist in IdeaVim. The biggest gap, and the strongest reason to
  open real Neovim.
- **Buffers.** The IDE has editor tabs. `Shift-h`/`Shift-l` work, but `:ls` and
  `:bd` intuition will not build there.
- **`<localleader>` mappings.** IdeaVim does not support them at all.
- **Staging a single hunk.** No JetBrains action exists — use the commit window
  or lazygit.
- **Most `<leader>u` toggles.** They are settings checkboxes, not commands.
- **Multi-cursor.** `Alt-j` is move-line now, so the IDE's add-next-occurrence is
  gone. Use `*` then `cgn` then `.` — it works in both editors and you keep it
  forever.
- **`crt`** for Title Case is IDE-only; the other case coercions work in both.

### Practicalities

- **Turn Vim off temporarily** from the Vim icon in the status bar — the main
  menu is hidden on this setup, so that icon is the way.
- **Find an action's name** with `:set trackactionids`, then trigger it from a
  menu and read the notification.
- **Reload after editing** `~/.ideavimrc` with `:source ~/.ideavimrc`. Typing it
  by hand is also how you see errors; startup only logs them.

## When stuck

| Situation | Do |
| --- | --- |
| Lost in a mode | `Esc`, twice if unsure |
| Just broke something | `u` |
| Want out without saving | `:q!` |
| Save, or save and quit | `:w` / `:wq` |
| What can I press now? | `<leader>` and wait |
| What is bound to this key? | `<leader>sk`, or `:map gd` |
| What does this do? | `:help ciw` — help works on keys too |
| Something is broken | `:checkhealth` |
| Need the tutorial again | `:Tutor` |

The training wheels come off: hardtime and precognition are scaffolding, not
features. When `:Hardtime report` stops telling you anything new, delete
`lua/plugins/create_training.lua` from the repo and its live counterpart.

## Where the config lives

Everything is in this repository. The live files are chezmoi *create-only* seeds,
which means your local edits are never overwritten — but it also means a repo
change does not reach an already-deployed machine on its own.

| What | Where |
| --- | --- |
| Neovim config | `rootfs/usr/share/zirconium/zdots/dot_config/nvim/` |
| Which extras are on | `.../nvim/create_lazyvim.json` and `lua/config/create_lazy.lua` |
| Plugin versions | `.../nvim/create_lazy-lock.json` |
| IdeaVim config | `rootfs/usr/share/zirconium/zdots/create_dot_ideavimrc` |
| IDE plugins | `config/jetbrains-settings/_shared/plugins.list` |
| IDE keymap | `config/jetbrains-settings/_shared/keymaps/custom.xml` |
| `dev nvim` itself | `.../dot_config/fish/functions/create_dev.fish` |

To change something: edit the seed, copy it to the matching live path, then run
`just validate`. Adding a language means extending the gated import list in
`lua/config/lazy.lua` **and** the detector in `dev.fish` — see `AGENTS.md`.
