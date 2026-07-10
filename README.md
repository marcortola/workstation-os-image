# Workstation OS Image

This repository is the reproducible definition of a personal Fedora bootc
workstation. It layers host-integrated software onto Zirconium, seeds personal
configuration without taking ownership away from the user, and restores
user-space tools on first login.

Published images:

```text
ghcr.io/marcortola/workstation-os-image:latest
ghcr.io/marcortola/workstation-os-image:<commit-sha>
```

## Configuration model

Each kind of state has one owner and update path:

| Layer | Owns | Update behavior |
| --- | --- | --- |
| Zirconium | Niri/DMS scaffolding, GTK and other desktop defaults | Continues to update through Zirconium's existing chezmoi services |
| This bootc image | RPM packages, system services and factory defaults | Replaced transactionally by `bootc upgrade` |
| Personal seeds | Fish, Foot, Zellij, Niri `local.kdl`, Starship, Neovim, TUI, Fontconfig and Brewfile defaults | Chezmoi `create_` entries create missing files once and preserve later edits |
| First-login provisioning | Homebrew packages, Flatpaks, JetBrains Toolbox and user fonts | Idempotent user services run until their success markers exist |
| Persistent user state | Secrets, projects, histories, application databases and DMS runtime state | Deliberately stays outside the image and repository |

The image extends `/usr/share/zirconium/zdots`; it does not install a second
chezmoi updater. Existing files under `/var/home` remain authoritative across
image switches and upgrades.

## Included workstation behavior

The image installs and configures:

- Fish.
- Docker Engine, CLI, Buildx, Compose and containerd.
- keyd with the Copilot-key chord mapped to Right Ctrl.
- Docker log rotation using five 10 MiB `json-file` logs per container.
- Dynamic membership in the root-equivalent `docker` group for interactive
  local users whose homes are under `/home` or `/var/home`.
- First-login open and Microsoft font installation.
- First-login Homebrew/Brewfile restoration and JetBrains Toolbox installation.
- Personal create-only defaults for Fish, Fontconfig, Foot, Starship, Zellij,
  Niri, Neovim, btop, Lazygit and Lazydocker.

`containerd.service`, `docker.service` and `keyd.service` are enabled through
systemd presets. Docker and keyd configuration is shipped under
`/usr/share/factory/etc` and linked into `/etc` by systemd-tmpfiles, following
Zirconium's factory-default convention. Docker is intentionally rootful and
usable without typing `sudo` after login.

The user package manifest is embedded as `~/dotfiles/Brewfile`. Zirconium
already supplies btop, chezmoi, Git, fzf and Just, so the Brewfile does not
duplicate them.

## Repository layout

```text
Containerfile                         Image packages, validation and presets
.github/workflows/build.yml           Daily, PR and main image builds
AGENTS.md / CLAUDE.md                 Canonical cross-agent repository guidance
config/dotfiles.manifest              Single personal configuration inventory
config/image-provided-brew-formulae   Known image/Homebrew package shadows
justfile                              Human and agent command interface
system_files/usr/share/factory/etc    Docker and keyd factory defaults
system_files/usr/share/zirconium      Create-only personal chezmoi entries
system_files/usr/lib/systemd          System and user services/presets
system_files/usr/bin                  First-login provisioning helpers
scripts/audit-dotfiles                Local Zirconium drift report
scripts/audit-deployment              Booted image and rpm-ostree layer report
scripts/sync-dotfiles                 Refresh personal seeds from this account
scripts/validate                      Repeatable local repository validation
```

The repository contains defaults and automation, not credentials. Never commit
passwords, tokens, SSH keys, registry credentials, application databases,
caches, histories or mutable DMS state. Microsoft font binaries are also not
redistributed; the image downloads them from their original distributors under
the owner's standing EULA acceptance.

## Build and publication

GitHub Actions builds pull requests without publishing. Merges to `main` and
the daily scheduled workflow publish `latest` and an immutable commit tag.
Before deployment, compare the two when an exact revision matters:

```bash
skopeo inspect docker://ghcr.io/marcortola/workstation-os-image:latest
skopeo inspect docker://ghcr.io/marcortola/workstation-os-image:<commit-sha>
```

The build accepts `BASE_IMAGE`, but the current integration requires a
Zirconium-compatible base that provides `/usr/share/zirconium/zdots` and its
chezmoi user services. An unrelated bootc base needs an adapter for those
contracts before changing the repository variable.

## Install or update

### Fresh workstation

Switch a bootc-based machine once, inspect the staged deployment, and reboot:

```bash
skopeo inspect docker://ghcr.io/marcortola/workstation-os-image:latest
sudo bootc switch ghcr.io/marcortola/workstation-os-image:latest
sudo bootc status --verbose
systemctl reboot
```

Confirm that `bootc status` shows the expected image and digest under `staged`
before rebooting.

### Existing workstation

Once the machine tracks this image, routine OS updates are:

```bash
sudo bootc upgrade
sudo bootc status --verbose
systemctl reboot
```

Do not use rpm-ostree package layering for software already declared by the
image. The deployment remains A/B and the previous image is available for
rollback.

## What happens on first login

Zirconium applies its combined chezmoi source before the graphical session.
Personal entries use `create_`, so missing files are seeded while existing
files are left unchanged.

Two enabled user services then provision persistent user state:

- `workstation-bootstrap.service` installs Homebrew when absent, applies
  `~/dotfiles/Brewfile`, installs its Flatpaks, and installs JetBrains Toolbox
  below `~/.local`. On a fresh account it also clones this repository into
  `~/projects/personal/workstation-os-image` when that path is absent.
- `workstation-microsoft-fonts.service` installs Caskaydia Mono Nerd Font,
  iA Writer Mono, Font Awesome, Microsoft core/Vista fonts and Cambria below
  `~/.local/share/fonts`.

Both are `oneshot` services. They normally become inactive after completing;
`Result=success` and their marker files are the useful status checks. A failed
or interrupted run is retried at a later login because its marker is absent.

## Post-reboot verification

Run these after graphical login. The first group verifies the image and host
services:

```bash
rpm -q containerd.io docker-buildx-plugin docker-ce docker-ce-cli \
  docker-compose-plugin fish keyd
test -x /usr/bin/fish
systemctl is-enabled containerd.service docker.service keyd.service
systemctl is-active containerd.service docker.service keyd.service
systemctl show workstation-docker-users.service --property=Result
test -S /run/docker.sock
id -nG | tr ' ' '\n' | grep -Fx docker
docker info --format '{{.LoggingDriver}}'
docker run --rm hello-world
sudo keyd check /etc/keyd/default.conf
```

The second group verifies user defaults and provisioning:

```bash
systemctl --user is-enabled workstation-bootstrap.service \
  workstation-microsoft-fonts.service
systemctl --user show workstation-bootstrap.service \
  workstation-microsoft-fonts.service --property=Result
test -f ~/.local/state/workstation-os-image/bootstrap-complete
test -f ~/.local/share/fonts/.workstation-fonts-installed
test -x /home/linuxbrew/.linuxbrew/bin/brew
test -L ~/.local/bin/jetbrains-toolbox
test -d ~/projects/personal/workstation-os-image/.git
test -f ~/.config/foot/workstation.ini
chezmoi managed -S /usr/share/zirconium/zdots | \
  grep -E '^(\.config/niri/local\.kdl|dotfiles/Brewfile)$'
foot --check-config -c ~/.config/foot/foot.ini
niri validate -c ~/.config/niri/config.kdl
```

First-login downloads can take time. If a marker is missing, inspect the user
journal before retrying:

```bash
journalctl --user -u workstation-bootstrap.service --no-pager
journalctl --user -u workstation-microsoft-fonts.service --no-pager
systemctl --user start workstation-bootstrap.service
systemctl --user start workstation-microsoft-fonts.service
```

## Personal configuration and Zirconium updates

Zirconium remains responsible for its evolving defaults. In particular:

- `~/.config/niri/config.kdl`, `dms.kdl` and DMS-generated fragments remain
  upstream-managed.
- Personal Niri bindings live only in `~/.config/niri/local.kdl`, which the
  upstream configuration already includes.
- DMS preferences and generated colors are runtime state. Drift is reported
  but they are not copied into the image.
- The upstream Foot template remains managed and is extended with a final
  include of create-only `~/.config/foot/workstation.ini`.
- User edits to a create-only target are never overwritten by image updates.

The seeded Niri shortcuts are:

| Shortcut | Action |
| --- | --- |
| `Mod+Shift+G` | Lazygit in Foot |
| `Mod+Shift+D` | Lazydocker in Foot |
| `Mod+Shift+T` | btop in Foot |

Fish explicitly starts Zellij for interactive terminals, initializes Starship,
Homebrew, direnv, fzf and Zoxide, and uses `/usr/bin/fish` throughout the
Foot/Zellij chain. Foot, Zellij, fzf, btop, Lazygit, Lazydocker and Neovim use
the Tokyo Night palette. Dynamic templates derive the home directory from
chezmoi rather than hardcoding a username.

## Updating tracked defaults

`AGENTS.md` is the canonical instruction file for coding agents. Codex loads it
directly; the repository's `CLAUDE.md` imports it, following Claude Code's
recommended compatibility pattern. Create-only global pointers under
`~/.codex` and `~/.claude` direct agents back to this repository even when they
are launched elsewhere. `CLAUDE.local.md` remains available for uncommitted
machine-specific notes.

`config/dotfiles.manifest` is the only capture inventory. Add one entry there
when adopting another portable configuration file; both synchronization and
validation consume it. This prevents a file from being copied by one script
but silently ignored by another.

For any durable terminal, GUI, Claude, or Codex change:

1. Make the change locally and decide whether it belongs to the OS image, the
   Brewfile, a portable personal seed, Zirconium, or deliberately untracked
   runtime state.
2. Add new packages explicitly to the Containerfile or Brewfile. Do not accept
   an unreviewed `brew bundle dump`, because it can reintroduce image-provided
   formulae.
3. Add a portable GUI/config file to the manifest only after checking it for
   credentials, device IDs, histories, caches, and database state.
4. Capture, review, and validate the result:

```bash
cd ~/projects/personal/workstation-os-image
just audit
just capture
git diff
```

`just audit` reports the booted image, accidental rpm-ostree mutations,
undeclared Homebrew/Flatpak installs, uncaptured personal changes, removed
files, and structural Zirconium Niri drift. Known redundant Homebrew shadows
of image binaries are visible but informational. Expected DMS runtime
differences are summarized; use `just audit-diff` for their complete diff or
`scripts/audit-dotfiles --strict` to make them fail. Deployment inspection is
skipped when the host system bus is unavailable, such as inside a build
container.

`just capture` synchronizes manifest-listed files, validates the repository and
effective workstation, and shows the resulting Git diff. Niri, Starship and
Foot remain reviewed templates because they contain dynamic paths or compose
with upstream files.

Instructions guide agents, but `just validate` is the enforcement layer: it
checks shell/Fish syntax, manifest coverage, personal drift, the Brewfile,
effective Niri/Foot configuration, and the combined chezmoi target map. Use
`just build` for image changes before opening a pull request.

Because create-only targets preserve existing files, changing a seed affects
new accounts and targets that do not yet exist. To adopt a revised seed on an
existing account, review the diff and deliberately update or remove that one
target before running Zirconium's chezmoi update.

## Fonts and appearance

The intended defaults are:

- Terminal and monospace: FiraCode Nerd Font Mono, 12 pt.
- Sans serif: Noto Sans, 11 pt.
- Serif: Noto Serif.
- Emoji: Noto Color Emoji.

The image-provided first-login service adds the extra user fonts documented
above and refreshes Fontconfig. Verify resolution with `fc-match`, for example:

```bash
fc-match monospace
fc-match sans-serif
fc-match serif
fc-match emoji
fc-match Arial
fc-match Calibri
fc-match Cambria
fc-match 'CaskaydiaMono Nerd Font Mono'
fc-match 'iA Writer Mono S'
fc-match 'Font Awesome 6 Free'
```

## User updates and recovery

The OS follows the bootc flow above. Update user packages and desktop
applications independently:

```bash
brew update
brew upgrade
brew bundle install --file ~/dotfiles/Brewfile
flatpak update
```

Inspect deployments before recovery work:

```bash
sudo bootc status --verbose
rpm-ostree status -v
ostree admin status
```

Roll back the bootc deployment with:

```bash
sudo bootc rollback
systemctl reboot
```

If Zirconium's system Flatpak provisioning failed, inspect it before repairing:

```bash
systemctl status flatpak-preinstall.service --no-pager
journalctl -b -u flatpak-preinstall.service --no-pager
flatpak remotes --system --show-details
```

Do not remove `/var/lib/zirconium/preinstall-finished` unless diagnosing a
confirmed incomplete preinstall. Avoid deleting deployments or package layers
until `bootc status` and `ostree admin status` identify a known-good rollback.
