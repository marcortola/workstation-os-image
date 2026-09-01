# Development Environment

How code actually gets written on this workstation: no language runtimes on the
host, project-scoped Dev Containers, a Neovim that runs *inside* those
containers, one set of Vim bindings across every editor, and worktrees that
arrive populated instead of empty. Read this before you try to `dnf install`
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
project twice no longer stacks duplicate workspaces. The compare is exact, which
is what keeps it off worktree workspaces: `ga` labels those `<repo>/<branch>`.

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

## Vim Bindings in Every Editor

Neovim and the JetBrains IDEs answer to the same keys, so a habit built in one
transfers to the other. That parity is deliberate and it is enforced by
*subtraction*: `lua/config/create_keymaps.lua` is empty on purpose.

```lua
-- Deliberately empty. This workstation runs stock Vim/LazyVim bindings in both
-- editors ... A JetBrains-parity keymap that exists in only one of the two
-- editors is a habit that has to be unlearned later, so none are defined.
```

The IDEs get the same set through **IdeaVim**, driven by `~/.ideavimrc` — a
chezmoi seed at
`system_files/usr/share/workstation-os-image/dotfiles/create_dot_ideavimrc`,
declared in `tooling/data/dotfiles.manifest`. It sits at `~/.ideavimrc` rather
than under XDG because IdeaVim reads the first rc it finds and creates
`~/.ideavimrc` itself when absent, which would shadow an XDG one. Where LazyVim
and JetBrains disagree, **LazyVim wins** and the displaced IDE action is
re-exposed on its LazyVim `<leader>` key.

Four of the shared Marketplace plugins in
`tooling/data/jetbrains-settings/_shared/plugins.list` carry this:

| Plugin ID | Why |
|---|---|
| `IdeaVIM` | The emulator itself |
| `eu.theblob42.idea.whichkey` | The `<leader>` menus, so the same discovery affordance exists in both editors |
| `org.yelog.ideavim.flash` | flash.nvim parity for `s` / `S` / `r` / `f` / `t` / `;` / `,` |
| `com.magidc.ideavim.dial` | `<C-a>` / `<C-x>` over dates, booleans and semver — dial registers only ex-commands, so the keys are wired explicitly in the rc |

Every contested `Ctrl` key is assigned explicitly with `sethandler` — 26
directives, splitting each key between Vim, the IDE, or one owner per mode
(`sethandler <C-A> n-x:vim i:ide` gives dial the increment in normal and visual
but leaves Select All in insert). The reason is not taste:

```vim
"    keymapFlags.xml ships an empty descriptor list, so without this block the
"    IDE pops an "undefined handler" dialog per key on first launch and silently
"    defaults them to Vim.
```

Declaring them in the rc also makes them read-only in Settings | Editor | Vim,
which is what a repo-owned config wants. Each line that hands a key to Vim
carries the displaced IDE action in a trailing comment — `<C-F>` becomes Vim's
page-down and IDE Find moves to `<leader>sb`, `<C-R>` becomes redo and IDE
Replace moves to `<leader>sr`, and so on.

Case conversion is **vim-abolish** in both editors (`crs`, `crc`, `crm`, `cru`,
`cr-`, `cr.`, `crt`), which is why the Marketplace plugin
`de.netnexus.camelcaseplugin` is deliberately *not* in the shared list:
`plugins.list` records that abolish's `cr*` coercions replace it, and a second
case mechanism would exist on the JetBrains side only. The rc applies the same
argument to IdeaVim's emulated plugins under its own "deliberately NOT enabled"
list: `CamelCaseMotion` (`g:camelcasemotion_key` eats `<leader>w`),
`ReplaceWithRegister` (it owns `gr`, which LazyVim uses for LSP references),
sneak, NERDTree, yankring and multiple-cursors.

`hardtime.nvim` and `precognition.nvim` are seeded in
`lua/plugins/create_training.lua` as **transition scaffolding**, not editor
features — hardtime hints at shorter motions and hard-blocks the arrow keys,
precognition draws motion targets as virtual text. Neither has an IdeaVim
counterpart. Delete that seed and its deployed copy once the habits stick.

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
| **`ga <branch>`** | Delegates to herdr inside a session; on the plain-git path it calls `workstation-worktree-sync` itself as belt and braces |
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
deliberately minimal — herdr's own defaults (the `Ctrl+b` prefix, `prefix+?`
help, `~/.herdr/worktrees` checkouts) are accepted wholesale, and only the
settings whose defaults are wrong for a reproducible machine are pinned:
onboarding off, the tokyo-night theme, `default_shell = "/usr/bin/fish"` (a niri
keybind never sources `config.fish`, so herdr would otherwise inherit the
compositor's `$SHELL`), and both background calls to `herdr.dev` disabled —
`manifest_check` in particular downloads agent-detection rules and applies them
at runtime, which would change pane classification on a pinned binary with
nothing here changing.

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

Two fish functions cover the per-branch worktree loop. `ga` places the checkout
at `~/.herdr/worktrees/<repo>/<branch-slug>`, herdr's own layout, with `/`
replaced by `-` in the slug; `gd` acts on whatever worktree you are standing in:

| Command | Effect |
|---|---|
| `ga <branch>` | Create or open the worktree. Inside herdr it hands the job over so the checkout opens as its own workspace grouped under the parent repo; outside, plain `git worktree add` then `cd` |
| `gd` | Confirm, then remove the current worktree *and* its branch, returning to the main checkout. Refuses to remove the main worktree |

`ga` passes `--label <repo>/<branch>` on purpose: herdr labels a worktree
workspace with the branch alone, and the Agent sidebar's only location token is
that workspace name, so without the label every worktree row loses the
repository it belongs to. That is also why `sidebar_width = 36` (herdr's maximum)
is pinned. `gd` asks herdr to remove the workspace when herdr opened the
checkout, so the workspace goes away with the directory; deleting the branch
stays the function's job on either path, because herdr never deletes branches.

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

- **Four code comments still name `workmux`.** The repository migrated to herdr,
  and the root `.worktreeinclude` header has been corrected — but two comments in
  `tooling/worktree/init` (lines 7 and 82), one in
  `create_executable_workstation-worktree-sync` and one in the `post-checkout`
  hook still name the old multiplexer. Line 82 is the one that matters: it is the
  header `tooling/worktree/init` writes into every starter `.worktreeinclude` it
  generates, so the stale name keeps spreading to newly onboarded repositories
  even though the file it was copied from is now right. Only the wording is
  stale: the mechanism is unaffected, since every path goes through
  `git worktree add`.
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
- **IdeaVim has no `<localleader>`.** LazyVim's `<localleader>` bindings are
  Neovim-only and cannot be practised in the IDEs, so the parity claim has this
  one hole by construction.
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
