# Workstation OS Image

Personal Fedora bootc derivative containing host-integrated packages that must
survive image updates and switches.

The default base is Zirconium, but the build accepts a different bootc base
through the repository variable `BASE_IMAGE`.

## Included host packages

- Fish
- keyd
- Docker Engine, CLI, Buildx, Compose, and containerd

The image enables `containerd.service`, `docker.service`, and `keyd.service`
at build time. It also installs the Docker log-rotation policy and Copilot-key
mapping from `system_files/`. Docker creates `/run/docker.sock` when its service
starts. See [configuration boundaries](docs/configuration-boundaries.md) for
what belongs in this image versus user dotfiles.

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

To use Docker without `sudo`, add the user to the `docker` group and then log
out and back in. This membership grants root-equivalent privileges.

```bash
sudo usermod -aG docker "$USER"
```

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
