# Workstation OS Image

Personal Fedora bootc derivative containing host-integrated packages that must
survive image updates and switches.

The default base is Zirconium, but the build accepts a different bootc base
through the repository variable `BASE_IMAGE`.

## Included host packages

- Fish
- keyd
- Docker Engine, CLI, Buildx, Compose, and containerd
- Microsoft font installer prerequisites and an opt-in installation helper

The image enables `containerd.service`, `docker.service`, and `keyd.service`
through image-owned systemd presets. Docker log rotation and the Copilot-key
mapping live under `/usr/share/factory/etc` and are linked into `/etc` by
systemd-tmpfiles, following Zirconium's factory-default convention. Docker
creates `/run/docker.sock` when its service starts. See
[configuration boundaries](docs/configuration-boundaries.md) for what belongs
in this image versus user dotfiles.

## Published image

GitHub Actions builds daily and after relevant changes, publishing:

```text
ghcr.io/marcortola/workstation-os-image:latest
ghcr.io/marcortola/workstation-os-image:<commit-sha>
```

After the first successful workflow run, ensure the GHCR package is public.

## Switch this workstation

Inspect the image before switching, then stage it:

```bash
skopeo inspect docker://ghcr.io/marcortola/workstation-os-image:latest
sudo bootc switch ghcr.io/marcortola/workstation-os-image:latest
bootc status --verbose
systemctl reboot
```

After reboot:

```bash
rpm -q containerd.io docker-buildx-plugin docker-ce docker-ce-cli \
  docker-compose-plugin fish keyd
systemctl is-enabled containerd.service docker.service keyd.service
systemctl is-active containerd.service docker.service keyd.service
test -S /run/docker.sock
docker info --format '{{.LoggingDriver}}'
sudo keyd check /etc/keyd/default.conf
```

Docker is rootful. Before graphical login, the image adds interactive local
users with homes under `/home` or `/var/home` to the root-equivalent `docker`
group. This avoids hardcoded usernames and allows Docker commands without
`sudo` after login:

```bash
docker run --rm hello-world
```

Microsoft font binaries are not redistributed in this public image. An enabled
user service records the workstation owner's standing EULA acceptance by
invoking the installer with `--accept-microsoft-eula` on first login. It
downloads the fonts from their original distributors into the persistent user
font directory. To run it immediately or retry it:

```bash
systemctl --user start workstation-microsoft-fonts.service
```

## Zirconium configuration drift

Zirconium continues to own and update its Niri/DMS defaults. Put partial Niri
customizations only in `~/.config/niri/local.kdl` or `/etc/niri/local.kdl`.
Audit managed scaffolding, informational DMS preference differences, local
overrides, and the effective Niri configuration with:

```bash
workstation-config-drift
```

Use `workstation-config-drift --strict` when DMS preference differences should
also produce a nonzero exit status.

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

Set the GitHub repository variable `BASE_IMAGE` to another compatible bootc
image, trigger the workflow manually, inspect the result, and use `bootc
switch` for the deliberate migration. Routine updates should continue to use
`bootc upgrade`.
