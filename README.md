# Workstation OS image

A personal, reproducible Fedora bootc workstation built on
[Zirconium](https://github.com/zirconium-dev/zirconium). The repository turns OS
packages, services, desktop defaults and selected user preferences into one
reviewable Git workflow. A new machine can switch to the published image, sign
in and converge on the same working environment.

Published image:

```text
ghcr.io/marcortola/workstation-os-image:latest
```

## What it provides

- Zirconium's Niri and DankMaterialShell desktop, still updated upstream.
- DankCalendar (`dcal`) tray daemon and DankSearch (`dsearch`) filesystem
  search, both Zirconium-shipped and enabled here; `dsearch` powers the DMS
  launcher's `/` file search.
- Rootful Docker with its socket enabled and local users added dynamically to
  the `docker` group, so Docker does not require `sudo` after login.
- Fish, Foot, Omarchy-based Tmux, Starship, Neovim and Tokyo Night defaults.
- OpenCode (`oc` and `Mod+Shift+O`), Caps Lock as Ctrl, and
  `gpt-4o-transcribe` dictation on `Mod+Shift+V`.
- Default Claude Code MCP servers (`context7`, `playwright`, `ahrefs`) seeded
  once into the user account; `playwright` drives the per-user Flatpak Google
  Chrome on demand through a CDP wrapper (`workstation-playwright-mcp`), so no
  browser is layered into the image; Ahrefs needs a one-time
  `claude mcp login ahrefs`.
- Screen recording via `wf-recorder` on `Mod+Shift+R`.
- `dev` to select a repository and change the current shell into it;
  `Mod+Shift+P` opens the same picker in a new Foot terminal.
- `ga <branch>` / `gd` create and remove a per-branch git worktree at
  `../<repo>--<branch>`, keeping parallel branches — and the AI agents working
  them — in separate directories.
- `workmux` for heavier parallel work: each branch gets its own tmux window and
  worktree under `<repo>__worktrees/`, driven by matching `worktree` /
  `ship-worktree` / `rm-worktree` helpers seeded for Claude Code (commands),
  Codex (skills) and OpenCode (commands).
- Brewfile and Flatpak restoration, JetBrains Toolbox, personal fonts and the
  accepted Microsoft-font installer.
- Private video codecs (RPM Fusion), RAR extraction, `pandoc`, `mkcert`,
  Insync and FileZilla.
- System tuning: inotify watch limits for JetBrains/node file watchers,
  journald caps, and zstd-compressed zram sized to half of RAM.
- Audits for image/package drift, portable personal configuration, upstream
  Niri/DMS changes and captured DMS preferences.
- Containerfile and workflow linting (`hadolint`, `actionlint`) and secret
  scanning (`gitleaks`), enforced by both local validation and CI.

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

## Architecture

```text
Zirconium image ──> Containerfile + system_files ──> GHCR image ──> bootc A/B OS
                              │
                              ├─> create-only chezmoi seeds ──> portable $HOME defaults
                              └─> partial DMS overlay ─────────> selected GUI preferences

local terminal/GUI edits ──> audit + interactive capture ──> Git branch/PR ──┘
```

| Source | Owns | Update behavior |
| --- | --- | --- |
| Zirconium | Niri/DMS scaffolding and desktop integration | Continues moving with the base image |
| This image | RPMs, daemons, sockets, privileged helpers and factory defaults | Replaced transactionally by bootc |
| Chezmoi seeds | Portable Fish, Foot, Tmux, Niri and application defaults | Create missing files; preserve later edits |
| DMS overlay | Explicitly captured, portable GUI preferences | Seeds a new account once; later UI edits win unless explicitly restored |
| JetBrains config | One shared canonical (`_shared/`) plus per-product remainder | Applied into the IDEs on demand; never auto-synced |
| Persistent home | Secrets, projects, histories, device state and application databases | Never stored in the image or Git |

The image extends Zirconium's existing chezmoi source. It does not introduce a
second dotfile manager, hardcode a username, or use rpm-ostree package layers.

Image builds keep the slow runtime-package transaction ahead of the volatile
`system_files/` copy, while compiled helpers use isolated builder stages. CI
stores Buildah intermediate layers in the companion GHCR cache repository and
reuses cache entries for ordinary pushes and pull requests. The daily scheduled
build deliberately skips cache reads so DNF metadata and packages are refreshed;
it then replaces the remote cache. Changes that do not affect `Containerfile`,
`system_files/` or the build workflow still run their tests but skip the image
job. The build context contains only `Containerfile` and `system_files/`.

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

Run workstation recipes from any Fish terminal and any directory with
`wjust`. Plain `just` remains project-local.

```bash
wjust audit
wjust capture
```

`capture` synchronizes manifest-listed live files into create-only seeds, runs
all validation and shows the resulting diff. Review that diff before committing.

| Command | Purpose |
| --- | --- |
| `wjust audit` | Report deployment, packages, personal files, Zirconium and DMS drift |
| `wjust audit-diff` | Show the complete upstream Niri/DMS diff when diagnosing it |
| `wjust sync` | Refresh manifest-listed create-only seeds from the live account |
| `wjust capture` | Sync, validate and display the complete pending change |
| `wjust validate` | Check structure, syntax, linting, secret scan, manifests and the effective workstation |
| `wjust build` | Build and lint the bootc image locally with Podman |
| `wjust status` | Show the current Git branch and diff summary |

For a new portable file, add one entry to `config/dotfiles.manifest`; it is the
only personal-file inventory. Do not add whole application directories.

### Share JetBrains IDE settings

The repository keeps one canonical JetBrains configuration so every IDE feels the
same, and applies it explicitly — it is not an automatic sync.
`config/jetbrains-settings/_shared/` holds the portable "feel the same" subset
once (keymaps, colour schemes, fonts, product-neutral editor/UI options); each
`config/jetbrains-settings/<Product>/` holds only that IDE's product-specific
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

Plugins are declared as Marketplace IDs and installed headlessly with the IDE's
`installPlugins` command; the JARs are fetched at apply time, never vendored.
`config/jetbrains-settings/_shared/plugins.list` installs into every IDE, and each
`config/jetbrains-settings/<Product>/plugins.list` adds plugins for just that IDE.

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
wjust dms-apply     # explicitly restore the tracked overlay
wjust audit
```

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

`audit-diff` may still show the full generated DMS file differing from
Zirconium's sparse seed. The actionable result is the later “Captured DMS
preference defaults” section: it reports whether tracked values match and
whether portable deviations remain uncaptured.

## Add a feature

Use the smallest durable owner:

- RPM, daemon, socket, privileged helper or system preset: `Containerfile` or
  `system_files/`.
- Homebrew formula, cask or Flatpak: `~/.config/homebrew/Brewfile`, then
  `wjust sync`.
- Portable user configuration: add it to `config/dotfiles.manifest`, then
  `wjust sync`.
- Niri customization: `~/.config/niri/local.kdl`, never the upstream-managed
  `config.kdl` or DMS-generated fragments.
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

## Install a workstation

The target must already be bootc-based. Inspect and switch it once:

```bash
skopeo inspect docker://ghcr.io/marcortola/workstation-os-image:latest
sudo bootc switch ghcr.io/marcortola/workstation-os-image:latest
sudo bootc status --verbose
systemctl reboot
```

After graphical login, first-login services clone this repository, restore the
Brewfile/Flatpaks, install Toolbox and fonts, seed the DMS preference overlay
once, and seed the default Claude Code MCP servers once. Check convergence with:

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
and `brew upgrade` daily as the `linuxbrew` user (`uupd.timer`, 04:00), next to
its Flatpak, Distrobox and bootc modules. The standalone upstream
`brew-update.timer` and `brew-upgrade.timer` stay inert here — brew-proxy
replaces `/home/linuxbrew/.linuxbrew/bin/brew` with a dispatch wrapper, so their
`ConditionPathIsSymbolicLink` never matches and every firing skips. That is
expected, not drift; `uupd` owns brew upgrades. Force one with `brew upgrade`
and authenticate the brew-proxy prompt so it runs as `linuxbrew`. Third-party
tap formulae are trusted for `linuxbrew` automatically by
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
wjust dms-apply  # only when intentionally restoring captured DMS defaults
```

Create-only chezmoi targets and the one-time DMS preference seed intentionally
preserve later user edits. To adopt a changed default on an existing account,
review and apply it deliberately.
