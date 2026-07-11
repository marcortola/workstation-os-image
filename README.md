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
- Fish, Foot, pane-focused Zellij, Starship, Neovim and Tokyo Night defaults.
- OpenCode (`oc` and `Mod+Shift+O`), Caps Lock as Ctrl, and
  `gpt-4o-transcribe` dictation on `Mod+Shift+V`.
- Screen recording via `wf-recorder` on `Mod+Shift+R`.
- `dev` to select a repository and change the current shell into it;
  `Mod+Shift+P` opens the same picker in a new Foot terminal.
- Brewfile and Flatpak restoration, JetBrains Toolbox, personal fonts and the
  accepted Microsoft-font installer.
- Private video codecs (RPM Fusion), RAR extraction, `pandoc`, `mkcert`,
  Insync and FileZilla.
- System tuning: inotify watch limits for JetBrains/node file watchers,
  journald caps, and zstd-compressed zram sized to half of RAM.
- Audits for image/package drift, portable personal configuration, upstream
  Niri/DMS changes and captured DMS preferences.

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
| Chezmoi seeds | Portable Fish, Foot, Zellij, Niri and application defaults | Create missing files; preserve later edits |
| DMS overlay | Explicitly captured, portable GUI preferences | Seeds a new account once; later UI edits win unless explicitly restored |
| Persistent home | Secrets, projects, histories, device state and application databases | Never stored in the image or Git |

The image extends Zirconium's existing chezmoi source. It does not introduce a
second dotfile manager, hardcode a username, or use rpm-ostree package layers.

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
| `wjust validate` | Check structure, syntax, manifests and the effective workstation |
| `wjust build` | Build and lint the bootc image locally with Podman |
| `wjust status` | Show the current Git branch and diff summary |

For a new portable file, add one entry to `config/dotfiles.manifest`; it is the
only personal-file inventory. Do not add whole application directories.

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
- Homebrew formula, cask or Flatpak: `~/dotfiles/Brewfile`, then `wjust sync`.
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

GitHub Actions also builds every relevant PR. Merges to `main` and the daily
scheduled workflow publish both `latest` and an immutable commit tag.

## Install a workstation

The target must already be bootc-based. Inspect and switch it once:

```bash
skopeo inspect docker://ghcr.io/marcortola/workstation-os-image:latest
sudo bootc switch ghcr.io/marcortola/workstation-os-image:latest
sudo bootc status --verbose
systemctl reboot
```

After graphical login, first-login services clone this repository, restore the
Brewfile/Flatpaks, install Toolbox and fonts, and seed the DMS preference
overlay once. Check convergence with:

```bash
wjust audit
systemctl --user status workstation-bootstrap.service \
  workstation-microsoft-fonts.service workstation-dms-settings.service
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
wjust dms-apply  # only when intentionally restoring captured DMS defaults
```

Create-only chezmoi targets and the one-time DMS preference seed intentionally
preserve later user edits. To adopt a changed default on an existing account,
review and apply it deliberately.
