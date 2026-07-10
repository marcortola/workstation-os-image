# Configuration boundaries

The image owns configuration that must be present before a user session starts
or that integrates with the host operating system. User preferences remain in
the user's dotfiles because `/var/home` persists independently of bootc image
deployments.

## Image-owned

- Fish, keyd, Docker Engine, containerd, Buildx, and Compose packages
- `containerd.service`, `docker.service`, and `keyd.service` enablement
- `/etc/docker/daemon.json` log rotation policy
- `/etc/keyd/default.conf` Copilot-key mapping
- Docker's Fedora package repository
- Microsoft font installer prerequisites and the opt-in download helper

## User-owned

- Homebrew and the Brewfile
- Fish initialization and utility functions
- Starship, Foot, Zellij, Niri, Neovim, DMS, Lazygit, and Lazydocker settings
- User-local fonts and Fontconfig preferences

These files belong in a dotfiles repository and can be restored after an OS
install without rebuilding or republishing the bootable image.

## Deliberately excluded

- Usernames, passwords, tokens, SSH keys, and registry credentials
- Docker-group membership; this image requires rootful Docker through `sudo`
- Microsoft font binaries; the image ships only an opt-in helper that downloads
  them from their original distributors after explicit EULA acceptance
- Files under `/var/home`, because image updates do not replace existing user
  home directories

Redistributable open fonts and system-wide Fontconfig defaults may be added to
the image later if they are made machine-independent and version-pinned.
