# Workstation OS Image

Personal Fedora bootc derivative containing host-integrated packages that must
survive image updates and switches.

It is also the reproducible definition of the owner's workstation: Zirconium
remains responsible for its evolving desktop defaults, while this repository
adds create-only personal defaults and first-login restoration.

The build accepts `BASE_IMAGE`, but the current desktop integration requires a
Zirconium-compatible base that provides `/usr/share/zirconium/zdots` and its
chezmoi user services. Supporting an unrelated bootc base requires a deliberate
adapter for those contracts; the generic repository name leaves room for that
future migration.

## Included host packages

- Fish
- keyd
- Docker Engine, CLI, Buildx, Compose, and containerd
- First-login open and Microsoft font installer prerequisites and helper
- Create-only Fish, Foot, Zellij, Niri, Starship, Neovim, TUI, Fontconfig, and
  Brewfile defaults layered into Zirconium's own chezmoi source
- First-login Homebrew/Brewfile and JetBrains Toolbox restoration

The image enables `containerd.service`, `docker.service`, and `keyd.service`
through image-owned systemd presets. Docker log rotation and the Copilot-key
mapping live under `/usr/share/factory/etc` and are linked into `/etc` by
systemd-tmpfiles, following Zirconium's factory-default convention. Docker
creates `/run/docker.sock` when its service starts. See
[configuration boundaries](docs/configuration-boundaries.md) for what belongs
in this image versus user dotfiles. The complete, versioned recreation and
recovery runbook is [immutable workstation setup](docs/immutable-workstation-setup.md).

## Published image

GitHub Actions builds daily and after relevant changes, publishing:

```text
ghcr.io/marcortola/workstation-os-image:latest
ghcr.io/marcortola/workstation-os-image:<commit-sha>
```

After the first successful workflow run, ensure the GHCR package is public.

## Switch a fresh workstation

Inspect the image before switching, then stage it:

```bash
skopeo inspect docker://ghcr.io/marcortola/workstation-os-image:latest
sudo bootc switch ghcr.io/marcortola/workstation-os-image:latest
sudo bootc status --verbose
systemctl reboot
```

If the machine already tracks this image, stage routine updates with `sudo
bootc upgrade` instead of switching again. Before rebooting, confirm that
`bootc status` reports the intended digest under `staged`.

After reboot and graphical login, verify host integration:

```bash
rpm -q containerd.io docker-buildx-plugin docker-ce docker-ce-cli \
  docker-compose-plugin fish keyd
systemctl is-enabled containerd.service docker.service keyd.service
systemctl is-active containerd.service docker.service keyd.service
systemctl show workstation-docker-users.service --property=Result
test -S /run/docker.sock
id -nG | tr ' ' '\n' | grep -Fx docker
docker info --format '{{.LoggingDriver}}'
docker run --rm hello-world
sudo keyd check /etc/keyd/default.conf
```

Then verify the create-only defaults and first-login provisioning:

```bash
systemctl --user is-enabled workstation-bootstrap.service \
  workstation-microsoft-fonts.service
systemctl --user show workstation-bootstrap.service \
  workstation-microsoft-fonts.service --property=Result
test -f ~/.local/state/workstation-os-image/bootstrap-complete
test -f ~/.local/share/fonts/.workstation-fonts-installed
test -x /home/linuxbrew/.linuxbrew/bin/brew
test -L ~/.local/bin/jetbrains-toolbox
test -f ~/.config/foot/workstation.ini
chezmoi managed -S /usr/share/zirconium/zdots | \
  grep -E '^(\.config/niri/local\.kdl|dotfiles/Brewfile)$'
foot --check-config -c ~/.config/foot/foot.ini
niri validate -c ~/.config/niri/config.kdl
```

The provisioning services are `oneshot` units, so they normally become
inactive after completion; `Result=success` and the marker files are the useful
checks. If either result is not successful, inspect its user journal before
retrying it.

Docker is rootful. Before graphical login, the image adds interactive local
users with homes under `/home` or `/var/home` to the root-equivalent `docker`
group. This avoids hardcoded usernames and allows Docker commands without
`sudo` after login:

Microsoft font binaries are not redistributed in this public image. An enabled
user service records the workstation owner's standing EULA acceptance by
invoking the installer with `--accept-microsoft-eula` on first login. It
downloads the fonts from their original distributors into the persistent user
font directory. To run it immediately or retry it:

```bash
systemctl --user start workstation-microsoft-fonts.service
```

## Zirconium and personal dotfiles

Zirconium continues to own and update its Niri/DMS defaults. Put partial Niri
customizations only in `~/.config/niri/local.kdl` or `/etc/niri/local.kdl`.
Personal files in `system_files/usr/share/zirconium/zdots` use chezmoi's
`create_` attribute, so Zirconium creates them when absent and never overwrites
later user edits. The image does not ship a competing chezmoi service.

From a checked-out repository on the workstation, audit installed upstream
drift and validate the effective Niri configuration with:

```bash
scripts/audit-dotfiles
```

Use `scripts/audit-dotfiles --strict` when DMS-generated preferences should
also fail the audit. After reviewing drift and deliberate local changes, run
`scripts/sync-dotfiles` to refresh the create-only files committed here.
Run `scripts/validate` before committing to check the manifest copy, shell and
Fish syntax, effective Niri/Foot configuration, and the combined chezmoi target
map.

On a new account, Zirconium applies the combined source. An enabled user
service then installs Homebrew if needed, applies `~/dotfiles/Brewfile`, and
installs JetBrains Toolbox below `~/.local`. Existing accounts are not reset;
remove the relevant target deliberately if a new image default should be
created again.

## Updates and rollback

The scheduled workflow rebuilds against the current base-image tag. Apply a
published update transactionally:

```bash
sudo bootc upgrade --download-only
bootc status --verbose
sudo bootc upgrade --from-downloaded --apply
```

Rollback remains available through:

```bash
sudo bootc rollback
systemctl reboot
```

## Changing the Fedora derivative

Set the GitHub repository variable `BASE_IMAGE` only to another image that
provides the Zirconium dotfile contracts described above. For an unrelated
bootc base, first replace the zdots patch and chezmoi activation integration,
then trigger the workflow manually and inspect the result before using `bootc
switch`. Routine updates should continue to use `bootc upgrade`.
