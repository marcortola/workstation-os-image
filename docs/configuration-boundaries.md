# Configuration boundaries

The image owns host integration and carries reproducible, create-only personal
defaults. Zirconium still owns its managed desktop files, and `/var/home`
persists independently of bootc deployments.

## Image-owned

- Fish, keyd, Docker Engine, containerd, Buildx, and Compose packages
- `containerd.service`, `docker.service`, and `keyd.service` enablement
- Docker log rotation and keyd mapping as factory defaults under
  `/usr/share/factory/etc`, linked into `/etc` by systemd-tmpfiles
- Service policy under system and user preset directories
- Docker's Fedora package repository
- Microsoft font installer prerequisites and download helper
- Dynamic Docker-group membership for interactive local workstation users
- First-login Microsoft font installation with standing EULA acceptance
- Create-only personal defaults inside Zirconium's existing chezmoi source
- First-login restoration of user fonts, Homebrew packages, Flatpaks from the
  Brewfile, and JetBrains Toolbox

## Created once, then user-owned

- Homebrew and the Brewfile
- Fish initialization and utility functions
- Starship, Foot, Zellij, Niri, Neovim, DMS, Lazygit, and Lazydocker settings
- User-local fonts and Fontconfig preferences
- Partial Niri customization in `~/.config/niri/local.kdl`

These defaults are embedded using chezmoi `create_` entries. They reproduce a
new workstation but do not overwrite an existing target, so local edits remain
authoritative. `scripts/sync-dotfiles` updates the image's seed copies after
the local changes have been reviewed.

Zirconium-owned Niri scaffolding, DMS-generated fragments/preferences, GTK
settings, and other upstream-managed targets are deliberately not copied. The
personal Niri seed is only `local.kdl`, which Zirconium's managed `config.kdl`
already includes.

## Deliberately excluded

- Usernames, passwords, tokens, SSH keys, and registry credentials
- Microsoft font binaries; the image ships only a helper that downloads
  them from their original distributors into persistent user storage
- Secrets, application databases, caches, histories, IDE projects/settings,
  and mutable DMS runtime state

Font binaries remain in persistent user storage and are refreshed explicitly,
not replaced during every bootc update.
