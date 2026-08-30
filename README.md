# Workstation OS image

A personal, reproducible Fedora bootc workstation built on ublue's
[base-main](https://github.com/ublue-os/main). The repository turns OS
packages, services, desktop defaults and selected user preferences into one
reviewable Git workflow. A new machine can switch to the published image, sign
in and converge on the same working environment.

Published image:

```text
ghcr.io/marcortola/workstation-os-image:latest
```

## What it provides

- The niri + DankMaterialShell desktop, installed from the `yalter/niri` and
  `avengemedia` COPRs and driven by an image-owned niri system config under
  `/usr/share/workstation-os-image/niri/`. Those COPRs float on HEAD; the NEVRA
  manifest at `/usr/share/workstation-os-image/package-manifest.txt` is the
  bisection record.
- DankSearch (`dsearch`) filesystem search, installed from the
  `avengemedia/danklinux` COPR and enabled here; it powers the DMS launcher's
  `/` file search.
- DankCalendar, which ships as the `com.danklinux.dankcalendar` Flatpak rather
  than an RPM user service. The Brewfile declares it, a captured
  Flatpak override grants read-only access to the DMS colour cache so it follows
  the session palette, and a captured XDG autostart entry starts its daemon and
  tray icon at login.
- Rootful Docker with its socket enabled and local users added dynamically to
  the `docker` group, so Docker does not require `sudo` after login.
- Fish, Foot, herdr, Starship, Neovim and Tokyo Night defaults.
- OpenCode (`oc`, or `Ctrl+b Alt+O` for a pane inside herdr), Caps Lock as
  Ctrl, and
  `gpt-transcribe` dictation on `Mod+Shift+V`.
- Default Claude Code MCP servers (`context7`, `ahrefs`) seeded once into the
  user account; Ahrefs needs a one-time `claude mcp login ahrefs`. Browser
  automation is the token-lean `playwright-cli` (not an MCP): it attaches to the
  per-user Flatpak Google Chrome over CDP (`workstation-playwright-chrome`) and
  snapshots to disk, so no browser is layered into the image.
- Screen recording via `wf-recorder` on `Mod+Shift+R`.
- `Ctrl+Alt+U`, or the power menu's **Switch User**, moves between logged-in
  users (see [Switch user](#switch-user)).
- `pro` to select a repository and change the current shell into it;
  `Mod+Shift+P` opens the same picker and hands the chosen repository to herdr
  as its own workspace.
- `dev [cmd]` runs a command inside the current repo's Dev Container (no args
  drops into a shell), starting it on demand via the `devcontainer` CLI —
  e.g. `dev terraform apply`.
- `herdr` as the coding multiplexer on `Mod+Shift+T`, prefixed on `Ctrl+b`. It
  labels each pane's coding agent as working, blocked, done or idle in its
  sidebar, which is the reason it replaced tmux. `Mod+T` stays a plain Foot
  window: herdr is never started from the shell, because every attached client
  mirrors the others, so a second terminal would be a clone rather than a
  second context. An agent started outside a herdr pane reports no state and
  says nothing about it, so start them from the herdr window.
- `ga <branch>` / `gd` create and remove a per-branch git worktree at
  `~/.herdr/worktrees/<repo>/<branch>`, keeping parallel branches — and the AI
  agents working them — in separate directories.
- For heavier parallel work each branch gets its own herdr workspace and
  worktree, driven by matching `worktree-create` / `worktree-push` /
  `worktree-remove` helpers seeded for Claude Code (commands), Codex (skills)
  and OpenCode (commands).
- New worktrees inherit a repo's untracked files (`.env`, `.idea`, ...) from a
  committed `.worktreeinclude`, applied identically by `ga`, herdr, Claude Code
  and the JetBrains IDE (see [Worktree file propagation](#worktree-file-propagation)).
- Brewfile and Flatpak restoration, JetBrains Toolbox, personal fonts and the
  accepted Microsoft-font installer.
- Private video codecs (negativo17, enabled from base-main at build time),
  RAR5 extraction (`unar`), `pandoc`, `mkcert`,
  Insync and FileZilla.
- System tuning: inotify watch limits for JetBrains/node file watchers,
  journald caps, and zstd-compressed zram sized to half of RAM.
- Audits for image/package drift, portable personal configuration,
  image-owned Niri/DMS scaffolding and captured DMS preferences.
- Containerfile and workflow linting (`hadolint`, `actionlint`) and secret
  scanning (`gitleaks`), enforced by both local validation and CI.

## Switch user

The login manager (greetd) runs one graphical session at a time, so a second
user logs in on a spare virtual terminal and you hop between them:

1. Press `Ctrl+Alt+F3` to reach a free console and log in as the other user.
2. Run `run-ui` there to start their desktop (an easy-to-remember front for
   `niri-session`).
3. Move between sessions with `Ctrl+Alt+F1` (you) and `Ctrl+Alt+F3` (them), or
   press `Ctrl+Alt+U` to jump to the other running session. The power menu's
   **Switch User** entry lists the same sessions.

To go back to a single session, log out (power menu → **Log Out**).

## Development environments

Language runtimes (Node.js/npm, Python, PHP/Composer, Java/Maven/Gradle,
Terraform, etc.) are **not** installed globally on the host. This keeps the
image lean and avoids version conflicts between projects.

Use [devcontainers](https://containers.dev/) for project-scoped runtimes:

```bash
devcontainer up --workspace-folder .     # build and start the container
devcontainer exec --workspace-folder . <command>
```

The `devcontainer` CLI (installed via Homebrew) uses Docker, which is already
configured rootful and passwordless. Each project pins its own runtime versions
in a `.devcontainer/devcontainer.json`. This is the same workflow used by VS
Code Dev Containers and GitHub Codespaces.

### Neovim IDE (`dev nvim`)

Neovim (LazyVim) is the workstation IDE. Because language runtimes and project
dependencies live inside the Dev Container, **`dev nvim` runs Neovim inside the
project's container** — the same model VS Code Dev Containers and JetBrains
Gateway use — so LSP, debugging and tests see the real `vendor/`, `node_modules`
and site-packages. It shares the host config and reuses the plain `dev`
container (no rebuild).

- **Two tiers.** Host `nvim` is the editor for git, quick edits and
  non-container repos; **`dev nvim`** is where LSP/DAP/tests run for a
  containerized project. A host LSP cannot resolve container-only dependencies,
  so use `dev nvim` for real language work.
- **Git:** lazygit is LazyVim's `<leader>gg`, and the keymap only exists where
  the binary does, so the host's static binary and its config are mounted into
  the container and the host git identity is forwarded. Staging, committing and
  diffing work in there; pushing stays on the host, which has the credentials.
- **First run per container** provisions a pinned Neovim, a private Node (for
  node-based servers), and the Mason LSP/DAP servers, linters and treesitter
  parsers **for the project's detected languages only** into a per-project store
  under `~/.local/share/dev-nvim/` (minutes; subsequent launches are fast). The
  store auto-resets if the container's base image changes; delete its directory
  to force a clean reprovision.
- **Languages:** Python (basedpyright + ruff), JS/TS/React/Astro (vtsls +
  astro), PHP/Symfony (intelephense — run `just ide-setup` once after deploy to
  store a premium key that `dev nvim` injects into the container; free tier
  otherwise), plus Twig, SQL, YAML, Docker. Formatting is
  on-demand (`<leader>cf`); nothing reformats on save.
- **Per-project prerequisites** (owned by each repo's devcontainer, not this
  image): dependencies installed (`composer`/`npm`/`pip`), and for step
  debugging, Xdebug in the PHP image or `debugpy`/`--inspect` for Python/Node.
- The config ships as create-only chezmoi seeds (`dot_config/nvim/`). `dev nvim`
  scopes the servers/parsers/tools to the project's detected languages
  (`NVIM_MASON_LANGS`); add a language by extending the gated import list in
  `lua/config/lazy.lua` and the detector in `dev.fish`, then `just sync`. `just
  validate` compile-checks every lua seed.

### Vim bindings in every editor

Neovim and the JetBrains IDEs answer to the same keys, so a habit learned in one
works in the other. Neovim runs stock LazyVim bindings — `lua/config/keymaps.lua`
is deliberately empty, because a binding that exists in only one of the two
editors is a habit that has to be unlearned later. The IDEs get the same set
through **IdeaVim**, driven by `~/.ideavimrc` (a chezmoi seed; see
`tooling/data/dotfiles.manifest`). Where LazyVim and JetBrains disagree, LazyVim wins
and the displaced IDE action moves to its LazyVim `<leader>` key.

Four Marketplace plugins in `_shared/plugins.list` back this: `IdeaVIM` itself,
`eu.theblob42.idea.whichkey` for the `<leader>` menus, `org.yelog.ideavim.flash`
for LazyVim's `s`/`S`/`r`/`f`/`t` flash motions, and `com.magidc.ideavim.dial` for
`<C-a>`/`<C-x>`. Every contested `Ctrl` key is assigned explicitly with
`sethandler`, because `keymapFlags.xml` ships no conflict resolutions and IdeaVim
would otherwise prompt once per key and silently default them to Vim. Case
conversion is `vim-abolish` in both — the only case plugin IdeaVim emulates —
which is why `de.netnexus.camelcaseplugin` is not in the shared list.

`hardtime.nvim` and `precognition.nvim` are seeded as transition scaffolding in
`lua/plugins/create_training.lua`; delete that seed and its deployed copy once the
habits stick.

### Worktree file propagation

A git worktree is a fresh checkout, so the untracked files a project needs to run
— `.env*`, `.idea/`, `.claude/settings.local.json` — do not come along. Each repo
declares them once in a committed **`.worktreeinclude`** (gitignore syntax; only
files git already ignores are copied, never tracked ones), and every worktree
creation path reads that single inventory:

- **herdr** (`worktree-create`) creates the checkout by shelling out to `git
  worktree add`, so the `post-checkout` hook below applies it.
- **`ga`** applies it after `git worktree add`.
- **Claude Code** (`--worktree`, subagent isolation) reads `.worktreeinclude`
  natively.
- **JetBrains** "New Worktree" fires a git `post-checkout` hook that applies it;
  `init.templateDir` seeds that hook into new clones. A **Sync worktree files**
  External Tool (Tools → External Tools) is the manual fallback for repos whose
  own hooks path (Husky, lefthook) bypasses the hook.

The copy is `git worktreeinclude` (Homebrew), wrapped by
`workstation-worktree-sync` so it is a no-op outside a linked worktree and never
blocks creation. Onboard a repository — install the hook and generate a starter
`.worktreeinclude` — with:

```bash
just worktree-init            # the current repo
just worktree-init --all      # every repo under ~/projects
```

Dependencies (`node_modules`, `vendor`) are deliberately not copied — add a
per-repo install step instead. The JetBrains
index is per-worktree and always rebuilds; copying `.idea/` carries settings and
run configs, not the index.

## AI coding CLIs

Three CLIs — **Claude Code**, **codex**, **opencode** — split into two layers:
your **personal config** ships in the image (chezmoi lays it down at login,
secret-free), and four **token-optimization tools** install on top with one
command. Configs are *captured*; tools are *installed* via their own official
installers — the same split the Brewfile uses for packages.

The tools: **opencode-fusion** (a main agent that plans/reviews and delegates
edits to a cheap sidekick), **caveman** (~65% shorter model output), **rtk**
(compresses shell output before it reaches context), and **@playwright/cli**
(token-lean browser automation that drives the Flatpak Chrome over CDP). Codex
also gets OpenAI's developer-docs MCP, which needs no credentials.

**First-time setup** (once, after switching to a new image):

```bash
just brew-apply         # install the rtk binary + any new Brewfile entries
just ai-tools-install   # install the tools, log in, and print secret-file setup
```

`ai-tools-install` walks the interactive parts for you: it offers to run each
CLI's login (`codex login`, `claude auth login`, `opencode auth login` — skipping
any you are already signed in to) and prompts for the Context7 key (hidden input,
stored 0600). Answer `n` to any prompt to do that piece later. Re-enter the key
by deleting `~/.config/opencode/context7-key` and re-running.

Codex gets OpenAI's official developer-docs MCP at
`https://developers.openai.com/mcp`; it needs no secret. Restart Codex after
changing MCP config or credentials.

**Everyday commands:**

| Command | What it does |
| --- | --- |
| `just ai-diff` | show how live config has drifted from canonical (read-only) |
| `just ai-reset` | restore config to canonical (dry run; add `--force`) — keeps auth, trust grants and keys |
| `just ai-tools-install` | (re)install the four tools |
| `just ai-tools-uninstall` | remove the four tools — leaves config, auth and history alone |

**Reset to a clean base** (canonical config, no tools; keeps your logins and history):

```bash
just ai-tools-uninstall && just ai-reset --force
```

**Share to a non-image machine:** the self-contained `tooling/ai/ai-cli-setup/` bundle
does the same install with its own `install.sh` — see its README.

## Architecture

The top level separates the image payload from the host-side tooling that
manages a live machine:

| Directory | Holds | In the image? |
| --- | --- | --- |
| `system_files/` | OS image payload copied into `/` (`COPY system_files/ /`): systemd units, helpers, factory defaults, the image-owned niri system config under `usr/share/workstation-os-image/niri/`, and the chezmoi seeds under `usr/share/workstation-os-image/dotfiles/`. | Yes — copied verbatim into `/` |
| `build_files/` | Everything the build reads and nothing it ships: the build scripts (`00-toolchain.sh` runs first in its own stage, then `10-repos.sh`, `20-packages.sh`, `30-desktop.sh`, `40-signing.sh`, `50-services.sh`, `60-metadata.sh`, `90-cleanup.sh`, `99-check-build.sh`), `packages/` (one `.list` per group plus `exclude.list`), `repos/` (vendored `.repo` files, deleted again by `90-cleanup.sh`), `keys/` (vendored RPM signing keys), `src/` (`workstation-x11-clipsync.c`). | No — bind-mounted at `/ctx`, never `COPY`d into a layer |
| `tooling/` | Host-side management scripts grouped by concern (`audit/`, `dms/`, `dotfiles/`, `jetbrains/`, `validate/`, `worktree/`), plus `data/` (the declarative source they read: the `dotfiles.manifest` inventory, JetBrains canonical settings, the AI-CLI MCP fragment, policy deny-lists), `ai/` (the AI-CLI machinery), `lib/`, `scrub/` and `fixtures/`. | No |

Root files (`Containerfile`, `Justfile`, `image.env`, `README.md`, `AGENTS.md`) stay at the
top level.

```text
ublue base-main ──> Containerfile + system_files ──> GHCR image ──> bootc A/B OS
                              │
                              ├─> create-only chezmoi seeds ──> portable $HOME defaults
                              └─> partial DMS overlay ─────────> selected GUI preferences

local terminal/GUI edits ──> audit + interactive capture ──> Git branch/PR ──┘
```

| Source | Owns | Update behavior |
| --- | --- | --- |
| COPR desktop stack | niri, DankMaterialShell, quickshell, dgop, matugen, danksearch | Floats on COPR HEAD; the NEVRA manifest baked by `90-cleanup.sh` is the bisection record |
| Image-owned scaffolding | The niri system config, the niri/foot entrypoints, greetd and the greeter theme | Replaced on every image update; personal overrides live in `local.kdl` / `workstation.ini` |
| This image | RPMs, daemons, sockets, privileged helpers and factory defaults | Replaced transactionally by bootc |
| Chezmoi seeds | Portable Fish, Foot, herdr, Niri and application defaults | Create missing files; preserve later edits |
| DMS overlay | Explicitly captured, portable GUI preferences | Seeds a new account once; later UI edits win unless explicitly restored |
| JetBrains config | One shared canonical (`_shared/`) plus per-product remainder | Applied into the IDEs on demand; never auto-synced |
| Persistent home | Secrets, projects, histories, device state and application databases | Never stored in the image or Git |

The image owns its chezmoi source outright at
`/usr/share/workstation-os-image/dotfiles/`, applied by
`workstation-chezmoi-init.service` and refreshed by
`workstation-chezmoi-update.timer`. It does not introduce a second dotfile
manager, hardcode a username, or use rpm-ostree package layers.

Image builds keep the slow runtime-package transaction ahead of the volatile
`system_files/` copy, while compiled helpers (keyd, clipsync, the FiraCode release)
are built once in a single isolated `toolchain` stage. CI
stores Buildah intermediate layers in the companion GHCR cache repository and
reuses cache entries for ordinary pushes and pull requests. The daily scheduled
build deliberately skips cache reads so DNF metadata and packages are refreshed;
it then replaces the remote cache. Changes that do not affect `Containerfile`,
`system_files/` or the build workflow still run their tests but skip the image
job. The build context is `Containerfile`, `system_files/` and `build_files/`; it
travels in a `scratch` stage that every `RUN` bind-mounts at `/ctx`, so build
inputs never land in a layer of the shipped image.

### Image signing

Published images are signed with cosign and the machine is configured to require
that signature. Three pieces have to line up, and the third is the one whose
absence looks like success:

- `cosign.pub` in this repository is the public half. CI signs the **digest**
  (a tag can move; a digest cannot), then immediately verifies the result
  against this file, so a key or format mismatch fails the build rather than
  publishing something the machine will refuse.
- `/etc/containers/policy.json` carries a `sigstoreSigned` entry for
  `ghcr.io/marcortola`, merged into what base-main ships. The
  `ghcr.io/ublue-os` entry must survive that merge or the machine cannot pull
  its own base.
- `/etc/containers/registries.d/workstation-signing.yaml` sets
  `use-sigstore-attachments: true`. Without it the signature is never fetched
  and the policy has nothing to check. `build_files/40-signing.sh` generates it
  from `image.env` rather than shipping it, so the scope follows a fork.

Signing alone changes nothing on the host: a deployment whose origin is
`ostree-unverified-registry:` ignores `policy.json` entirely. Enforcement is a
one-time switch:

```bash
sudo bootc switch --enforce-container-sigpolicy \
  ghcr.io/marcortola/workstation-os-image:latest
```

`rpm-ostree status` then shows an `ostree-image-signed:` origin, and any future
update whose signature does not verify is refused rather than deployed. Do this
only after a signed image has been published, or the switch has nothing valid
to pull.

### RPM signing keys

Third-party `.repo` files are vendored so `baseurl` and `gpgkey` are reviewable
in git. Vendoring the repo file alone only covers half of that: if `gpgkey=`
points at a URL, the trust anchor that authenticates every package is still
fetched on build day. So the keys are vendored too, under
`build_files/keys/rpm/`, referenced by `file://`, with provenance and pinned
fingerprints recorded in `build_files/keys/rpm-key-sources.json`.

`tooling/validate/rpm-keys` re-fetches each upstream key and asserts the
vendored copy is byte-identical and still carries the pinned fingerprint. A key
rotating upstream becomes a failure to review rather than a silent change in
what the build trusts. An unreachable upstream is a skip, not a failure, so an
offline build still works.

One gap stated plainly: negativo17's repo file comes from base-main and still
fetches its key over the network. That file is not ours to rewrite, and the
chain has a defined root anyway — base-main is digest-pinned and
cosign-verified before anything is built on it, so that key is trusted
transitively rather than unconditionally.

### Vendored from Zirconium

This image used to derive from
[Zirconium](https://github.com/zirconium-dev/zirconium). It no longer does, but
the niri system configuration was carried over rather than rewritten. Six
includes under `system_files/usr/share/workstation-os-image/niri/includes/` —
`dms-base.kdl`, `input.kdl`, `layout.kdl`, `misc.kdl`, `shadow.kdl` and
`window-rules.kdl` — were copied verbatim from
[zirconium-dev/zdots](https://github.com/zirconium-dev/zdots), and `binds.kdl`
was substantially rewritten from the same source. That work is licensed under
the Apache License 2.0; this repository's own code is MIT. The attribution
lives in `system_files/usr/share/workstation-os-image/niri/NOTICE`, ships inside the
image, and `workstation.kdl` points at it. Upstream no longer feeds these
files: they are changed and reviewed here.

### XWayland interop

niri has no built-in XWayland; it routes X11 clients through `xwayland-satellite`,
which does not bridge two cross-boundary interactions:

- **Clipboard** — `workstation-x11-clipsync.service` mirrors the Xwayland
  CLIPBOARD selection into the Wayland clipboard.
- **Drag-and-drop** — cannot be bridged by a helper. Instead
  `workstation-flatpak-wayland.service` sets a global Flatpak override
  (`--socket=wayland --env=ELECTRON_OZONE_PLATFORM_HINT=auto`) so
  Electron/Chromium Flatpaks (Typora, Postman, …) run as native Wayland clients
  and never cross the boundary. The socket grant covers apps whose manifest
  omits `wayland` (e.g. Postman ships `x11` only). Genuinely X11-only apps (no
  Wayland backend) still cannot drag-and-drop with Wayland apps until upstream
  lands support.

Tracked upstream at
[Supreeeme/xwayland-satellite#133](https://github.com/Supreeeme/xwayland-satellite/issues/133).

## Working with AI agents

`AGENTS.md` is the canonical maintenance policy. `CLAUDE.md` imports it, and
global Codex/Claude pointers direct agents here even when they start elsewhere.
An agent making a durable workstation change should:

1. Inspect the live setting and repository state.
2. Put OS packages/services in the image, deterministic user files in the
   manifest, and portable DMS preferences in the DMS overlay.
3. Keep credentials, histories, device identifiers and generated DMS state out
   of Git.
4. Run `wjust audit`, capture the intended state, and run `wjust validate`.
5. Commit on an `agent/*` branch, open a PR, wait for the image build, and merge
   before upgrading the workstation.

A useful prompt is:

```text
Implement <feature> on this workstation and in workstation-os-image. Follow
AGENTS.md, capture only portable state, validate it, and open a PR. Do not stage
the bootc upgrade until its image build passes and the PR is merged.
```

## Capture local changes

Run workstation recipes from any shell and any directory with `wjust`, an
image-provided launcher (`/usr/bin/wjust`) that clones the checkout on demand
the first time it runs. Plain `just` remains project-local.

```bash
wjust audit
wjust capture
```

`capture` synchronizes manifest-listed live files into create-only seeds, runs
all validation and shows the resulting diff. Review that diff before committing.

| Command | Purpose |
| --- | --- |
| `wjust audit` | Report deployment, unit state, image-owned `/etc` drift, packages, personal files, image-managed Niri scaffolding and DMS drift |
| `wjust audit-diff` | Show the complete upstream Niri/DMS diff when diagnosing it |
| `wjust sync` | Refresh manifest-listed create-only seeds from the live account |
| `wjust capture` | Sync, validate and display the complete pending change |
| `wjust validate` | Check structure, syntax, linting, secret scan, manifests and the effective workstation |
| `wjust build` | Build and lint the bootc image locally with Podman |
| `wjust status` | Show the current Git branch and diff summary |

For a new portable file, add one entry to `tooling/data/dotfiles.manifest`; it is the
only personal-file inventory. Do not add whole application directories.

### Share JetBrains IDE settings

The repository keeps one canonical JetBrains configuration so every IDE feels the
same, and applies it explicitly — it is not an automatic sync.
`tooling/data/jetbrains-settings/_shared/` holds the portable "feel the same" subset
once (keymaps, colour schemes, fonts, product-neutral editor/UI options); each
`tooling/data/jetbrains-settings/<Product>/` holds only that IDE's product-specific
remainder (code styles, templates, inspections, toolbars). Capture resolves the
newest installed product directory, so no IDE version is pinned, and nothing is
deployed by chezmoi. Only portable, secret-free files are tracked — `wjust
validate` fails on any license key, database source, `settingsSync/`, or runtime
state, and enforces that a file lives in exactly one place.

| Command | Purpose |
| --- | --- |
| `wjust jetbrains-diff` | Show where each installed IDE diverges from the shared canonical |
| `wjust jetbrains-promote [Product]` | Refresh `_shared/` from the canonical IDE (default: first listed) |
| `wjust jetbrains-apply [--force]` | Write `_shared/` + remainder and install shared plugins (dry run without `--force`) |
| `wjust jetbrains-plugins [--force]` | Install the `_shared/plugins.list` plugins into each IDE (dry run without `--force`) |
| `wjust ide-setup [--force]` | One-shot post-deploy IDE setup: intelephense premium key + JetBrains plugins (dry run without `--force`), then an interactive offer to apply the shared JetBrains settings (defaults to no) |

Plugins are declared as Marketplace IDs and installed headlessly with the IDE's
`installPlugins` command; the JARs are fetched at apply time, never vendored.
`tooling/data/jetbrains-settings/_shared/plugins.list` installs into every IDE, and each
`tooling/data/jetbrains-settings/<Product>/plugins.list` adds plugins for just that IDE.

Typical unification: edit settings in the canonical IDE, `wjust jetbrains-promote`
to capture them into `_shared/`, review the diff, then `wjust jetbrains-apply
--force --i-understand-overwrites-cloud` to fan them into the other IDEs. `apply`
refuses a running IDE, backs up the live config plus `settingsSync/`, and prints
the manual "Push Settings to Account" step (the cloud force-push is GUI-only).

### Capture DMS preferences

DMS's raw `settings.json` contains hundreds of schema defaults plus mutable and
device-specific state, so it is not copied wholesale. The capture tool reads
the `SettingsSpec.js` from the installed DMS version and compares the live file
to those current defaults:

```bash
wjust dms-capture   # Tab selects portable values to add or update
wjust dms-remove    # Tab selects tracked overrides to stop applying
wjust dms-apply     # explicitly restore the tracked overlay (prompts)
wjust audit
```

`dms-apply` overwrites live DMS settings with no backup, so it asks before
acting. That prompt needs a terminal: it aborts under a non-interactive shell,
which includes an agent running without a tty. Invoke
`system_files/usr/bin/workstation-apply-dms-settings --force` directly if you
genuinely need it unattended, and understand that it will not ask.

The tracked overlay is
`system_files/usr/share/workstation-os-image/dms-settings.json`. Simple values
merge by top-level key; bar settings merge by bar ID and field so future DMS
fields survive. Paths use portable tokens, and device pins, monitor layouts,
histories and similar state are excluded from the interactive picker.
Custom bars are captured as complete portable records; built-in bars remain
field-selectable. The first graphical login seeds this overlay after DMS has
migrated its schema. Later UI changes persist across login and reboot.

The UI remains the live editor. Run `dms-capture` after a reviewed change to
make it a default for reconstructed workstations. The image never writes live
DMS changes back into Git automatically.

The actionable result is the later “Captured DMS preference defaults” section:
it reports whether tracked values match and whether portable deviations remain
uncaptured.

## Add a feature

Use the smallest durable owner:

- RPM, daemon, socket, privileged helper or system preset: `Containerfile` or
  `system_files/`.
- Homebrew formula, cask or Flatpak: `~/.config/homebrew/Brewfile`, then
  `wjust sync`.
- Portable user configuration: add it to `tooling/data/dotfiles.manifest`, then
  `wjust sync`.
- Niri customization: `~/.config/niri/local.kdl`, never the upstream-managed
  `config.kdl` or DMS-generated fragments. A keybind DMS also claims wins only
  from `local.kdl`: it is the last include, and niri resolves duplicate binds
  last-definition-wins.
- DMS preference: change it in the GUI, then run `wjust dms-capture`.
- Secret or machine-specific state: leave it untracked and document only the
  setup command when necessary.

Before opening a PR:

```bash
wjust audit
wjust capture
git diff
wjust build
```

GitHub Actions also builds every relevant PR. A separate lint workflow runs
`hadolint`, `actionlint` and `gitleaks` on every push and pull request. Merges
to `main` and the daily scheduled workflow publish both `latest` and an
immutable commit tag. Image builds consume and update
`ghcr.io/marcortola/workstation-os-image-cache`; scheduled builds bypass that
cache on input and repopulate it after refreshing packages.

## Fork this image

The image is personal but the skeleton is not. Everything below is what a fork
has to touch, and nothing else needs attention.

**Edit**

| Path | Why |
|---|---|
| `image.env` | Image name, registry owner, description. The only place the identity is written; the Justfile, `tooling/audit/deployment`, the OCI labels, the signing policy scope and `wjust`'s clone URL all derive from it. The `ARG` defaults at `Containerfile:52-54` mirror it so a bare `podman build` still labels correctly, and `tooling/validate/image-build` fails if the two drift. |
| `cosign.pub` and `system_files/etc/pki/containers/workstation-signing.pub` | Your own signing keys. Generate with `COSIGN_PASSWORD="" cosign generate-key-pair`, store the private half as the `COSIGN_PRIVATE_KEY` repository secret (with `COSIGN_PASSWORD`), and never commit `cosign.key`. |
| `system_files/usr/share/workstation-os-image/dotfiles/` | The chezmoi seed tree is one person's dotfiles. Replace wholesale. |
| `Documentation=` URLs in `system_files/usr/lib/systemd/**` | Ten units point at this repo. Cosmetic, but wrong on a fork. |

**Delete if you do not want it**

| Path | What it is |
|---|---|
| `build_files/packages/insync.list`, `build_files/repos/insync.repo`, the `insync` entry in `build_files/keys/rpm-key-sources.json` | Insync is proprietary and needs a licence. Self-contained: one package, one repo, one key. |
| `tooling/data/jetbrains-settings/` and `tooling/jetbrains/` | Repo-owned JetBrains config plus the machinery that applies it. The settings are personal; the machinery is generic, so you may want to keep `tooling/jetbrains/` and empty the data. |
| `tooling/data/ai-tools/`, `tooling/ai/` | The AI-CLI seeds and bundle. |

**Do not touch**

| Path | Why |
|---|---|
| `system_files/usr/share/workstation-os-image/niri/NOTICE` | Apache-2.0 attribution for the niri includes vendored verbatim from Zirconium. Stripping it breaks the licence terms. |
| `tooling/validate/`, `tooling/scrub/` | The gates. `tooling/scrub/` is the real secret boundary: gitleaks does not know these tools' key shapes. Fix the input, never the check. |

**Not included:** there is no `disk_config/` and no ISO pipeline, so the only
install path is rebasing an already-bootc machine (see *Install a workstation*).
There is also no `artifacthub-repo.yml`; add one with the `repositoryID` Artifact
Hub issues you if you want the image indexed there.


## Install a workstation

The target must already be bootc-based. Inspect and switch it once:

```bash
skopeo inspect docker://ghcr.io/marcortola/workstation-os-image:latest
sudo bootc switch ghcr.io/marcortola/workstation-os-image:latest
sudo bootc status --verbose
systemctl reboot
```

After graphical login, first-login services restore the Brewfile/Flatpaks,
install Toolbox and fonts, seed the DMS preference overlay once, and seed the
default Claude Code MCP servers once. The repository checkout is not cloned
eagerly; `wjust` clones it on demand the first time you run a recipe. Check
convergence with:

```bash
wjust audit
systemctl --user status workstation-bootstrap.service \
  workstation-microsoft-fonts.service workstation-dms-settings.service \
  workstation-claude-mcp-seed.service
systemctl is-enabled --quiet containerd.service docker.service keyd.service
systemctl is-active --quiet containerd.service docker.service keyd.service
docker run --rm hello-world
```

Configure the one untracked dictation secret with:

```bash
workstation-openai-key
```

## Update

First merge desired repository changes and wait for the post-merge image
publication. Then stage and inspect the update:

```bash
skopeo inspect docker://ghcr.io/marcortola/workstation-os-image:latest
sudo bootc upgrade
sudo bootc status --verbose
systemctl reboot
```

After reboot:

```bash
wjust audit
```

Do not install image-owned software with rpm-ostree layering. Add it to this
repository so every future workstation gets the same result.

Homebrew updates run automatically: Universal Blue's `uupd` runs `brew update`
and `brew upgrade` daily (`uupd.timer`, 04:00), next to its Flatpak, Distrobox
and bootc modules. It runs them as the uid that owns the brew prefix — 1000,
because `brew-setup.service` chowns `/home/linuxbrew` to `1000:1000`. There is
no `linuxbrew` user on this image; that user came from brew-proxy, which is no
longer installed. The brew payload's own `brew-update.timer` and
`brew-upgrade.timer` are disabled by `build_files/50-services.sh`: on the previous
base they were inert because brew-proxy broke their
`ConditionPathIsSymbolicLink`, and with brew-proxy gone they would fire every
six and eight hours alongside uupd's brew module. `uupd` is the single updater.
Force an upgrade with `brew upgrade`; no authentication prompt is involved.
Third-party tap formulae are trusted automatically by
`workstation-brew-trust.service`, which re-derives the trust set from the
Brewfile on every boot, so adding a tap-qualified `brew`/`cask` line is enough
for it to be auto-upgraded. That line is not self-installing on an existing
machine, though: run `just brew-apply` once after deploy to install newly added
Brewfile entries (`just audit` flags any that are declared but missing).

## Recover

Inspect both bootc and ostree state before changing deployments:

```bash
sudo bootc status --verbose
rpm-ostree status -v
ostree admin status
```

Roll back to the previous A/B deployment:

```bash
sudo bootc rollback
systemctl reboot
```

If a user service failed, inspect its log and rerun it rather than deleting
state markers blindly:

```bash
journalctl --user -u workstation-bootstrap.service -b
journalctl --user -u workstation-microsoft-fonts.service -b
journalctl --user -u workstation-dms-settings.service -b
journalctl --user -u workstation-claude-mcp-seed.service -b
wjust dms-apply  # only when intentionally restoring captured DMS defaults; prompts
```

Create-only chezmoi targets and the one-time DMS preference seed intentionally
preserve later user edits. To adopt a changed default on an existing account,
review and apply it deliberately.
