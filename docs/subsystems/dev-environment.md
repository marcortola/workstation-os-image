# Development Environment

How code actually gets written on this workstation: no language runtimes on the
host, project-scoped Dev Containers, a Neovim that runs *inside* those
containers, two editors that deliberately do not share bindings, and worktrees
that arrive populated instead of empty. Read this before you try to `dnf install`
a compiler.

**The host is an editor and a container runtime; everything that compiles,
resolves imports or runs a test lives inside the project's Dev Container.**

---

## No Global Runtimes

No project toolchain is declared for the host. PHP, Composer, Java, Maven,
Gradle and Terraform are absent entirely; the Python 3 the image carries as an
RPM dependency (DMS needs it) and the Node that Homebrew pulls in for
`devcontainer` are there to run the tooling, and neither is ever pinned to a
project's required version. Two things follow: the image stays small and boring to upgrade, and two
projects that need different major versions of the same runtime never fight over
`/usr/bin`.

Project-scoped runtimes come from [Dev Containers](https://containers.dev/).
Each repository pins its own versions in `.devcontainer/devcontainer.json` (or a
top-level `.devcontainer.json`), which is the same file VS Code Dev Containers,
GitHub Codespaces and JetBrains Gateway read, so the container is not a
workstation-only artefact.

The CLI is a Homebrew formula — `brew "devcontainer"` in
`system_files/usr/share/workstation-os-image/dotfiles/dot_config/homebrew/create_Brewfile`
— and it drives Docker, which the image already provisions rootful and
usable without `sudo`: `system_files/usr/lib/sysusers.d/workstation-docker.conf`
creates the group (`g docker - -`) so a local user can be added to it. See
[packages.md](packages.md) for how the Brewfile relates to RPMs and Flatpaks.

The raw CLI still works, and is what to reach for when something is broken and
you want the noise:

```bash
devcontainer up --workspace-folder .
devcontainer exec --workspace-folder . <command>
```

Day to day you use the wrapper instead.

---

## The `dev` Wrapper

`dev` is a fish function seeded at
`system_files/usr/share/workstation-os-image/dotfiles/dot_config/fish/functions/create_dev.fish`.
It resolves the project's container, starts it if needed, and runs something
inside it. (Throughout this page, repo filenames carry chezmoi's `create_`
prefix, which is stripped on deploy: `create_dev.fish` here is
`~/.config/fish/functions/dev.fish` on the machine.)

| Invocation | What happens |
|---|---|
| `dev` | An interactive `bash` in the container, in the directory you were standing in |
| `dev <cmd> [args...]` | Runs `<cmd>` in the container, same working directory |
| `dev nvim [files...]` | Neovim inside the container, with the host config and the project's real dependencies |
| `nv [files...]` | `dev nvim` where a `.devcontainer` exists, plain host `nvim` where it does not |

**Container resolution** walks upward from the current directory looking for the
first `.devcontainer/devcontainer.json` or `.devcontainer.json`, and stops at the
repository root. Outside a git repository the search does not walk at all — only
the current directory is considered — because otherwise a stray
`~/.devcontainer` would hijack every unrelated subtree beneath `$HOME`. The
function is explicit about this:

```bash
# Boundary for the upward search: never look above the repo root. Outside a
# git repo there is no root to anchor to, so only the current directory is
# considered …
```

`devcontainer exec` always lands in the workspace folder, so `dev` computes
`realpath --relative-to="$root" .` and `cd`s to it inside the container. You come
out where you went in, not at the repo root.

Startup is idempotent: `devcontainer up` builds on the first call and is a fast
no-op afterwards, and the same mount set is passed on every `up`, so a plain
`dev` and a `dev nvim` share one container with no rebuild. When `up` fails, the
function prints the exact verbose command to re-run rather than swallowing the
error.

---

## Choosing a Project: `pro` and the Picker

`pro` is a thin fish function over
`system_files/usr/share/workstation-os-image/dotfiles/private_dot_local/bin/create_executable_workstation-dev`:
the picker prints a path, `pro` `cd`s the *current shell* into it.

The picker is fzf over every Git checkout one or two directories below
`$WORKSTATION_PROJECTS_ROOT` (default `~/projects`), displayed as
`group / repository`. It has three modes, selected by argument:

| Mode | Behaviour |
|---|---|
| (none) | Print the chosen path on stdout — what `pro` consumes |
| `--shell` | `cd` and `exec` a fish shell there |
| `--herdr` | Ask herdr for a workspace scoped to the chosen repo, then `exec herdr` |

`Mod+Shift+P` is bound to the `--herdr` mode, so picking a project from the
compositor drops you into a herdr session whose workspace is already that
repository. The picker resolves the `herdr` binary defensively —
`command -v herdr >/dev/null 2>&1 || herdr_bin=/home/linuxbrew/.linuxbrew/bin/herdr`
— because a niri keybind runs it with a minimal `PATH`. Keybind ownership and the
full bind inventory belong to [desktop-session.md](desktop-session.md).

Scoping goes over herdr's socket, never through the launch directory. herdr
scopes its startup workspace from the cwd only while the restored session has no
workspaces, and `session.json` carries them across restarts, so the first pick
after a reboot would otherwise land in whichever workspace was persisted —
`restored session already has workspaces; ignoring startup cwd` in
`herdr-server.log`. With a server already up the picker scopes inline before it
`exec`s the client; when this launch is the one starting the server, a
background waiter polls `workspace list` for up to ten seconds and scopes as
soon as the socket answers. Both paths first look for a workspace already
labelled with the repository's basename and focus that, so picking the same
project twice no longer stacks duplicate workspaces. The compare is exact and
matches the repository basename, so it never captures a worktree workspace,
which the `dev.flow` popup labels with the branch slug.

Either path then applies the default dev layout — `main` running the agent, plus
`nvim` and `term`. The `dev.flow` plugin applies it only for a herdr-created
worktree or on demand from `prefix+shift+n`, and a workspace opened from the
picker got neither. The gate is what the workspace already holds rather than
which branch reached it: `layout.sh` creates its tabs unconditionally, so a
second run would stack another `nvim` and `term`, while a workspace restored from
an older session is laid out on the next pick. One tab is not enough on its own,
because the split layout described below is one tab too, so the gate is one tab
**and** one pane — the shape of a workspace nothing has laid out yet. Without the
second half, picking a project again would take a chosen split layout apart.
`layout.sh` calls `herdr`, `jq`, `git` and `dirname` by name, so the picker hands
it a `PATH` rather than trusting the keybind's, and a failure never propagates,
because the picker still owes the caller its `exec`.

Scoping is also the whole job when a herdr window is already open. Every
attached client mirrors the others, so the window on screen has already moved
to the picked project by the time the workspace is focused — a second client
would only be a second view of it. The picker therefore asks niri for a window
whose app-id is `herdr` or `dev-terminal`, excluding its own by the focused
window's id, and focuses that instead of `exec`ing a client; its own terminal
closes behind it. Both launch binds are matched because both can hold a client:
`Mod+Shift+T` opens one as `herdr`, the picker as `dev-terminal`. When niri
answers with nothing to focus — no window open, or no compositor at all — the
lookup fails and the picker falls through to `exec`ing a client as before.

---

## `dev nvim`: Neovim Inside the Container

Neovim (LazyVim) is the workstation IDE, and it runs **in** the container for
real language work. That is not a preference; a host language server cannot
resolve `vendor/`, `node_modules` or site-packages that only exist inside the
container image, so a host LSP against a containerised project reports phantom
errors on every import.

### Two tiers

- **Host `nvim`** — git work, quick edits, config, and repositories with no Dev
  Container. On the host `NVIM_MASON_LANGS` is unset, so `config.scope` reports
  no language in scope and only the universal extras load.
- **`dev nvim`** — where LSP, DAP, tests and linters run. Use `nv` if you would
  rather not decide each time.

### What `up` attaches

Three bind mounts go on every `devcontainer up`, plus lazygit when it exists on
the host:

| Mount | Purpose |
|---|---|
| `$HOME/.config/nvim` → `/nvimconf-src` | The host Neovim config; copied into the store on each launch, never written back |
| `$HOME/.local/share/nvim/lazy` → `/nvim-plugins` | The host's already-cloned plugins, reused instead of re-cloning ~50 repos over the container network |
| `<per-project store>` → `/nvimdata` | The in-container nvim binary, private Node, Mason servers and compiled treesitter parsers |
| host `lazygit` binary + `~/.config/lazygit` | LazyVim's `<leader>gg` only exists where the binary does |

lazygit is mounted rather than downloaded because it is a static Go binary and
therefore runs on any base image. Its config rides along so the theme and
nerd-font icons match the host, mounted read-only at `/lazygitconf-src` and then
*copied* into the store, because lazygit writes state beside its config and must
not write into the host's copy.

Committing from the in-container lazygit needs an identity, so `dev nvim`
forwards `GIT_AUTHOR_NAME`/`EMAIL` and `GIT_COMMITTER_NAME`/`EMAIL` from the
host's `git config` rather than mounting `~/.config/git/config`, which sets
`pager = delta` — a binary the container does not have. Staging, committing and
diffing work inside; pushing stays on the host, which holds the credentials.

### The per-project store

The store lives at `~/.local/share/dev-nvim/<12 hex chars>`, where the suffix is
the first twelve characters of the SHA-256 of the workspace path. Host and
container both run as uid 1000, so the store is writable from inside and its
native artefacts match the container's libc.

First launch provisions it, which takes minutes; every launch after that is
fast. Provisioning installs a pinned Neovim (0.12.4, checksum-verified against
the release `shasum.txt` when that file can be fetched), a private Node 22.11.0
when the container has none, `fd` and `ripgrep` for the pickers, and a build
toolchain via `apt-get` when `cc`/`git` are missing *and* passwordless `sudo` is
available — otherwise it warns that treesitter may fail rather than dying.

The store **auto-resets** when the container's base changes. The provisioner
fingerprints `/etc/os-release`, `ldd --version` and `uname -m`, compares it to
`/nvimdata/.builtfor`, and on a mismatch wipes the nvim binary, Node and the four
XDG directories, because those artefacts are libc-bound. To force a clean
reprovision yourself, delete the store directory.

> A container created *without* these mounts — by JetBrains Gateway, or by an
> older `dev` — is happily reused by `devcontainer up` with the mounts still
> absent. `dev nvim` probes for `/nvimconf-src/init.lua`, `/nvimdata` and
> `/nvim-plugins` and recreates the container once (`--remove-existing-container`)
> when any is missing. That is the one case where `dev nvim` throws your
> container away.

### Language scoping

`dev.fish` detects the project's languages **host-side**, from the workspace
directory, and passes them as `NVIM_MASON_LANGS`. `lua/config/create_lazy.lua`
imports only those LazyVim language extras. Gating the *import* is the single scoping
point, and the comment in that file explains why nothing smaller works:

```lua
-- scoping point: disabling only the LSP server would still leave the parser, the
-- mason tools (nvim-lint/conform then error on the missing binary), and
-- lang.astro's ts-plugin path-probe installing or warning.
```

| Key | Detected from | LazyVim extra imported |
|---|---|---|
| `php`, `twig` | `composer.json` | `lang.php`, `lang.twig` |
| `ts` | `package.json` | `lang.typescript` plus `linting.eslint` |
| `tailwind` | `"tailwindcss"` or `"@tailwindcss/` in `package.json` | `lang.tailwind` |
| `astro` | `"astro"` in `package.json` | `lang.astro` |
| `python` | `pyproject.toml`, `requirements*.txt`, `setup.py`, `setup.cfg`, `Pipfile`, `environment.yml`, `.python-version`, or any top-level `*.py` | `lang.python` |
| `docker` | any top-level `Dockerfile*`, `Containerfile*`, `compose*.y*ml`, `docker-compose*.y*ml` | `lang.docker` |

JSON, YAML, Markdown, TOML and SQL are universal and load everywhere, along with
Prettier, the test and DAP cores, the REST client and aerial. Two server choices
are pinned in `lua/config/create_options.lua` rather than left to LazyVim
defaults: `vim.g.lazyvim_python_lsp = "basedpyright"` and
`vim.g.lazyvim_php_lsp = "intelephense"`.

What each extra actually starts is LazyVim's choice, not this repository's, so it
is worth naming — a table of extras tells you nothing about which binary ends up
running in the container:

| Extra | Servers and tools it brings up |
|---|---|
| `lang.python` | the pinned `basedpyright`, plus `ruff` as a second attached client for linting and formatting (`vim.g.lazyvim_python_ruff = "ruff"` upstream) |
| `lang.typescript` | `vtsls`, LazyVim's current default (`vim.g.lazyvim_ts_lsp = "vtsls"`); this is the JS/TS/React path |
| `linting.eslint` | `eslint`, imported alongside `lang.typescript` by the same detector row |
| `lang.astro` | the `astro` language server, plus the `@astrojs/ts-plugin` it path-probes for — which is the reason the import itself is the scoping point |
| `lang.php` | `intelephense` by the pin above; upstream would otherwise start `phpactor`. This is the PhpStorm/Symfony replacement path |

Mason installs follow the same scoping, with one documented exception in
`lua/plugins/create_mason.lua`: the universal SQL extra's `sqlfluff` is a Python
tool and errors with "python3 failed" in a container without Python, so it is
dropped from the eager set unless `python` is in scope. The SQL server still
provides diagnostics.

Intelephense premium is machine-local and never seeded into the image. Store the
key once with `just intelephense-licence`; `dev nvim` reads
`~/.config/intelephense/licence.key` and injects it as
`INTELEPHENSE_LICENCE_KEY`, which `lua/plugins/create_lang-php.lua` passes as the
server's `licenceKey` (nil means free tier). `just ide-setup` runs the same step
as part of the wider post-deploy IDE setup.

### Formatting and prerequisites

Nothing reformats on save. `lua/config/create_options.lua` sets
`vim.g.autoformat = false` so that "a formatter resolved on the host cannot
silently reformat code that a devcontainer owns". Formatting is invoked
deliberately, through LazyVim's own format keymaps.

Two prerequisites are owned by each repository's devcontainer, not by this
image: dependencies actually installed (`composer install`, `npm install`,
`pip install`), and — for step debugging — Xdebug in the PHP image, or
`debugpy` / `--inspect` for Python and Node. `dev nvim` will not install them
for you.

---

## Adding a Language

Two edits and a rule, then two commands. Every file named below is a create-only
chezmoi seed under `system_files/usr/share/workstation-os-image/dotfiles/`; the
Neovim ones sit in its `dot_config/nvim/` subtree.

1. **`lua/config/create_lazy.lua`** — add a `{ "<key>", "<extra module>" }` pair
   to the gated loop. Left is the key `dev.fish` emits in `NVIM_MASON_LANGS`;
   right is the LazyVim extra name. They differ where upstream disagrees with
   the short key (`ts` → `typescript`).
2. **`dot_config/fish/functions/create_dev.fish`** — teach the detector to emit
   that key from whatever manifest identifies the language.
3. **`lua/config/create_scope.lua`** is the gate a *user plugin* consults. Any
   plugin of yours that configures a language server or a test adapter must open
   with `if not require("config.scope").has("<key>") then return {} end`, the
   way `create_lang-php.lua`, `create_lang-python.lua` and `create_testing.lua`
   already do — otherwise it reintroduces the language, and triggers its LSP and
   tool install, in a container scoped to something else.

Then `just sync` to refresh the seeds from the live config, and `just validate`,
which compile-checks every Lua seed with the image's own Neovim
(`tooling/validate/all` feeds them to `tooling/validate/lint-nvim-seeds.lua` via
`nvim --clean -l`) — the Lua analogue of `bash -n`, no execution.

> Never add an extra ungated, and never hand-edit `create_lazyvim.json`. The
> first defeats the entire scoping mechanism and puts every language's servers
> in every container; the second is LazyVim's own state file, captured from live
> by `just sync`, so an edit there is overwritten on the next capture.

---

## Two Editors, Two Keymaps

Neovim and the JetBrains IDEs are deliberately separate. Neovim runs LazyVim
with the bindings [../keybindings.md](../keybindings.md) documents; the IDEs run
their own keymap and emulate nothing. That is the point of keeping them both:
the IDEs are the alternative to the herdr-plus-Neovim flow, not a second skin
over it.

They used to share a keymap. **IdeaVim** drove the IDEs from a `~/.ideavimrc`
seed so that a habit learned in either editor transferred, and
`_shared/keymaps/custom.xml` was emptied to get out of its way. The sharing was
never free — 26 `sethandler` directives to arbitrate every contested `Ctrl` key,
four Marketplace plugins, and a rule that LazyVim won every disagreement, which
meant reaching for a displaced IDE action through a `<leader>` chord. It was
removed: the IDEs now keep the keymap that suits them, and Neovim keeps the one
that suits it.

What that restored, in `_shared/keymaps/custom.xml`:

| Key | Action |
| --- | --- |
| `ctrl t`, `alt f12` | Terminal tool window |
| `ctrl alt r` | Rename |
| `shift ctrl b` | Git branches |
| `shift alt s` | Reveal in project view |
| `shift ctrl insert` | Paste history |
| `shift alt left` / `shift alt right` | Back / Forward |
| `shift ctrl u` | Toggle CamelCase |

`shift ctrl u` needs `de.netnexus.camelcaseplugin`, which is back in
`_shared/plugins.list` — with no Vim emulation it is the IDEs' only case
mechanism, where previously vim-abolish's `cr*` coercions covered it.
`tooling/jetbrains/validate` gates that the binding and the plugin entry agree,
in both directions.

> An `<action>` element **replaces** the parent keymap's whole shortcut list
> rather than adding to it. That is why `GotoTypeDeclaration` has no entry: a
> mouse-only override was silently deleting its default `control+shift+B`, and
> `$default` already supplies both that and `ctrl+shift+button1`. `Back` and
> `Forward` restate their mouse halves for the same reason.

Case conversion in Neovim is still **vim-abolish** (`crs`, `crc`, `crm`, `cru`,
`cr-`, `cr.`, `crt`). It was originally chosen over text-case.nvim because it
was the only case plugin IdeaVim emulated; that reason is gone, but the plugin
works and swapping it would cost the muscle memory for nothing.

`hardtime.nvim` and `precognition.nvim` are seeded in
`lua/plugins/create_training.lua` as **transition scaffolding**, not editor
features — hardtime hints at shorter motions and hard-blocks the arrow keys,
precognition draws motion targets as virtual text. They train the Neovim half
only. Delete that seed and its deployed copy once the habits stick.

JetBrains settings capture, promotion and application are
[../capturing-changes.md](../capturing-changes.md)'s subject, not this page's.

---

## Worktree File Propagation

A git worktree is a fresh checkout, so the untracked files a project needs in
order to *run* — `.env*`, `.idea/`, `.claude/settings.local.json` — do not come
along. Every worktree therefore starts broken until someone copies them by hand,
and everyone copies a slightly different set.

Each repository declares them once, in a committed **`.worktreeinclude`** using
gitignore syntax. Only files git already ignores and that match a pattern are
copied; tracked files never are. Because the file is committed, the whole team
gets the same list. This repository ships one at its root; its patterns are:

```text
# Local environment & secrets
.env
.env.local
.env.*.local

# IDE / editor local config
.idea/
.vscode/

# Claude Code local (machine-specific) settings
.claude/settings.local.json

# Machine-specific Claude local memory (gitignored)
CLAUDE.local.md
```

### The four creation paths

All four reach the same inventory, and `tooling/validate/sources` asserts the
wiring that keeps them in sync.

| Path | How it reaches `.worktreeinclude` |
|---|---|
| **herdr** (`herdr worktree create`) | Shells out to `git worktree add`, so the `post-checkout` hook fires |
| **`dev.flow` `worktree-setup.sh`** | A second, machine-local net on the `worktree.created` event: the union of every `.worktreeinclude` in `~/projects`, copied only where git already ignores the file and the target does not have it |
| **Claude Code** (`--worktree`, subagent isolation) | Reads `.worktreeinclude` natively |
| **JetBrains "New Worktree"** | The IDE shells out to git, so the same `post-checkout` hook applies |

The hook is
`system_files/usr/share/workstation-os-image/dotfiles/dot_config/git/template/hooks/create_executable_post-checkout`.
It fires only on branch checkouts (`[ "${3:-}" = "1" ] || exit 0`, so a file
checkout is ignored) and immediately delegates. `init.templateDir` in
`system_files/usr/share/workstation-os-image/dotfiles/dot_config/git/create_config`
seeds it into every *new* clone.

For a repository whose hooks path has been hijacked — Husky and lefthook both do
this — the fallback is the **Sync worktree files** External Tool, shipped in
`tooling/data/jetbrains-settings/_shared/tools/`. It runs `git worktreeinclude
apply` in `$ProjectFileDir$` from Tools → External Tools, and appears in the main
menu, the project view and search-everywhere.

### The copy itself

The underlying tool is `git worktreeinclude` (Homebrew:
`satococoa/tap/git-worktreeinclude`), wrapped by `workstation-worktree-sync` at
`system_files/usr/share/workstation-os-image/dotfiles/private_dot_local/bin/create_executable_workstation-worktree-sync`.
The wrapper exists to make the operation impossible to get wrong. It is a no-op
outside a work tree, a no-op in the *main* checkout — detected by
`--git-dir` equalling `--git-common-dir`, which matters because `post-checkout`
also fires on every ordinary branch switch — a no-op when the tool or the
`.worktreeinclude` is absent, and it never exits non-zero, because it must never
abort the worktree or checkout operation that invoked it. It resolves the
Homebrew binary by explicit path candidates, since a GUI-launched IDE runs hooks
with a minimal environment. `git worktreeinclude` itself never overwrites an
existing file and never touches a tracked one, so re-running the sync in a
worktree you have already edited is safe.

Onboard a repository — install the hook into `.git/hooks` and drop a starter
`.worktreeinclude` where there is none — with `tooling/worktree/init`:

```bash
just worktree-init            # the current repo
just worktree-init --all      # every repo under $WORKSTATION_PROJECTS_ROOT
```

`WORKSTATION_PROJECTS_ROOT` defaults to `~/projects`, the same root the project
picker scans.

It is idempotent and non-destructive: it never overwrites an existing
`.worktreeinclude`, and never replaces a hook it did not write. An existing
managed hook with local edits, or any unmanaged `post-checkout`, is reported and
skipped rather than clobbered.

Dependencies (`node_modules`, `vendor`, `.venv`) are deliberately **not** copied.
They are large, often platform-specific, and belong in a per-repo install step.
The JetBrains index is per-worktree and always rebuilds anyway; copying `.idea/`
carries settings and run configurations, not the index.

---

## herdr

herdr is the terminal multiplexer and the agent sidebar. Its config seed is
`system_files/usr/share/workstation-os-image/dotfiles/dot_config/herdr/create_config.toml`,
deliberately minimal outside `[keys]` and `[ui]`, which carry the ported
scheme. Elsewhere herdr's own defaults (`prefix+?` help, `~/.herdr/worktrees`
checkouts) are accepted wholesale, and only the settings whose defaults are
wrong for a reproducible machine are pinned:
onboarding off, the tokyo-night theme, `default_shell = "/usr/bin/fish"` (a niri
keybind never sources `config.fish`, so herdr would otherwise inherit the
compositor's `$SHELL`), and both background calls to `herdr.dev` disabled —
`manifest_check` in particular downloads agent-detection rules and applies them
at runtime, which would change pane classification on a pinned binary with
nothing here changing.

The prefix is `Ctrl+G`. The scheme was ported carrying `ctrl+s`, which is XOFF
and is also lazygit's `confirmInEditor-alt`, so a prefix on it would be
swallowed in every pane; `ctrl+g` is bound by nothing here and costs only
Neovim's built-in show-file-info. `[keys]` is a cascade — four actions are
parked on chords nobody presses so the rest can move one slot along — so run
`herdr config check` after editing it. It reports a collision as
`kept keys.X, disabled keys.Y` rather than failing.

Three rules, each with a failure behind it:

- **Launch it deliberately** — `Mod+Shift+T`, or the project picker's
  `Mod+Shift+P`. Never auto-attach from a shell rc, because every attached client
  mirrors every other one, so a second terminal would echo the first.
- **Keep one default session.** The agent-state rollup is per server, so named
  sessions fragment the one thing herdr was adopted for.
- **Run coding agents inside a herdr pane.** The config's own comment on the
  bound `prefix+alt+o` opencode pane says it plainly: "an agent outside a herdr
  pane never reaches the sidebar". Outside a pane the state hook exits 0
  silently, so nothing warns you.

### The two layouts

There are two, and either can be applied on top of the other. `prefix+shift+n`
builds the default: three tabs, `main` running the agent plus `nvim` and `term`.
`prefix+shift+v` builds the alternative, a single `dev` tab holding all three:

```
+----------+---------------------------+
|          |           nvim            |
|   main   +---------------------------+
|   33%    |      term (a sliver)      |
+----------+---------------------------+
```

`main` keeps its third of the width whatever you are working in; the right-hand
column is the editor's at rest and the terminal takes it on `prefix+t`. The three
ratios are named constants at the top of
`system_files/usr/share/workstation-os-image/dotfiles/dot_config/herdr/plugins/dev-flow/layout-common.sh`,
which also holds everything both layouts share — the editor and agent commands,
the idle-pane probe, and the socket calls the CLI does not expose.

**Neither layout is built with `layout.apply`, and that is deliberate.** It is
the socket method that looks made for the job, and it replaces the tab it is
handed: a request naming an existing `tab_id` and an existing `pane_id` comes
back with a new tab holding new panes, the old ones closed and the `pane_id`
ignored rather than adopted. Building a layout that way would kill the agent
every time it was applied. `pane split` and `pane move` are the calls that carry
a process across, so both layouts are built from those. Switching therefore moves
the live panes in and out of the `dev` tab rather than recreating them: the agent
keeps its conversation, Neovim keeps its unsaved buffers, and a tab closes itself
once its last pane leaves.

`prefix+m`, `prefix+n` and `prefix+t` answer in both layouts. `focus-tab.sh`
looks for a tab of that label first and falls back to a pane of that label in the
focused tab, which is why the split tab is called `dev` — a tab named `main`
would be found first and the key would never reach the pane inside it. Focusing
`nvim` or `term` also hands them the column, and focusing `main` does not: the
resize is restricted to a `down` split, and the vertical split is the one that
pins `main` to its third.

The per-branch worktree loop lives in the `dev.flow` plugin, reachable by key
from any pane. Checkouts land beside the repository at
`<repo>__worktrees/<branch-slug>`:

| Key | Effect |
|---|---|
| `prefix+shift+w` | Popup: prompt for a branch, validate it with `git check-ref-format`, create the worktree and apply the dev layout |
| `prefix+shift+x` | Popup: show the checkout and any uncommitted work, confirm, then remove it. The branch is never deleted |
| `prefix+s` | Space picker: live workspaces plus on-disk worktrees that have no workspace yet, grouped by repository and sorted so a blocked or finished agent rises to the top |
| `prefix+shift+u` | Open every linked worktree of every repository as a workspace. Also runs at server start |

The worktree workspace is labelled with the branch slug alone. The repository is
not lost, because `agent_panel_sort = "spaces"` groups rows under their space
and `[ui.sidebar.spaces]` carries `branch` and `git_status` on the second row —
which is why the previously pinned `sidebar_width = 36` is gone and herdr's
default 26 is enough. The sidebar also starts collapsed, which takes two keys,
not one: `sidebar_collapsed_mode = "hidden"` only chooses how a collapsed sidebar
draws, and `sidebar_start_collapsed = true` is what decides it begins that way.
`Ctrl+G` `b` brings it back. Removal never touches the branch, deliberately: herdr does
not delete branches and neither does the popup.

The `ga` and `gd` fish functions this replaced are gone. Outside a herdr pane,
use `git worktree add` directly; the `post-checkout` hook still fires, so
`.worktreeinclude` propagation is unaffected.

For heavier parallel work — several agents on several branches at once — the
unit is one herdr workspace plus one worktree per branch, and the agent drives
it rather than you. The same trio of helpers is seeded for all three CLIs:
`worktree-create`, `worktree-push` and `worktree-remove`, as slash commands for
Claude Code and OpenCode and as skills for Codex. The workflow is therefore
identical whichever agent is in the pane, which is the point — the isolation
model does not change when you switch tools. The seed paths are inventoried in
[ai-clis.md](ai-clis.md).

---

## Gotchas and Tech Debt

- **The `dev.flow` plugin reads herdr's API, so it drifts silently.** It was
  vendored against a herdr that reported each foreground process as `argv0`;
  0.8.2 reports `name`/`argv`/`cmdline`, `jq`'s `test` aborts on the resulting
  null, and the probes answered "not a shell" and "not vim" for every pane. The
  cost was invisible: `layout.sh` never started the agent in its `main` tab and
  `ctrl+hjkl` never reached Neovim or fzf, both without an error. `layout.sh` now
  asks whether the shell is the foreground process group — a comparison with no
  process names in it, which also rides through the `direnv hook fish` fish runs
  at startup — while `navigate.sh` still has to match names because it needs to
  know Neovim from any other busy pane. When a herdr upgrade changes behaviour
  here, the symptom is silence, so check the plugin's `jq` filters against a real
  `herdr pane process-info` before looking anywhere else.

- **Never run `:Lazy clean` on the host.** The host session has no project
  language in scope, so every language extra's plugins look unused there — but
  containers bind-mount that same directory as `/nvim-plugins`. Cleaning on the
  host deletes plugins the containers depend on. `:Lazy! install` is the safe
  half of the pair.
- **The `/nvim-plugins` mount is read-write.** A container that needs a plugin
  the host has not cloned will clone it into the host's shared plugin directory.
  That is what makes plugin reuse work, but it means container sessions can
  mutate host state. The nvim *config* mount is read-only only by convention:
  the provisioner copies it into the store and never writes back, but nothing
  enforces that.
- **The store reset does not clear `/nvimdata/bin`.** The base-image fingerprint
  check wipes the nvim binary, Node and the XDG directories, but `fd` and
  `ripgrep` survive it. `fd` is fetched as the `x86_64-unknown-linux-gnu` build,
  so a base swapped to a musl image keeps a glibc-linked `fd` that will not run.
  Delete the store directory to recover.
- **Provisioning assumes x86_64 and Debian.** Neovim, Node, `fd` and `ripgrep`
  are all downloaded as x86_64 tarballs, and the only toolchain fallback is
  `apt-get`. Another architecture, or an RPM/Alpine base missing `cc`, gets no
  working store.
- **The Neovim checksum check is conditional.** If `shasum.txt` cannot be
  fetched the tarball is installed unverified — a soft failure that is silent.
- **`hardtime.nvim` and `precognition.nvim` are scheduled for deletion.** Their
  own seed says to remove the file once the habits stick — a condition nobody
  re-checks. Leaving them in indefinitely turns scaffolding into config.

---

## Where to go next

The Brewfile lines behind `devcontainer`, `herdr`, `lazygit` and
`git-worktreeinclude`, and the rule about which declaration site owns which
package, are in [packages.md](packages.md). `Mod+Shift+T`, `Mod+Shift+P` and the
rest of the bind inventory — including who owns a key when DMS and the system
config both bind it — are in [desktop-session.md](desktop-session.md), and the
AI CLIs whose worktree commands are seeded alongside these are in
[ai-clis.md](ai-clis.md).

When you change any seed named on this page, [../capturing-changes.md](../capturing-changes.md)
is the audit → capture → sync → validate loop that gets it back into the
repository, and [../conventions.md](../conventions.md) explains why these are
create-only chezmoi seeds rather than files the image drops into `/etc`.
