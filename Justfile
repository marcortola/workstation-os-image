set shell := ["bash", "-euo", "pipefail", "-c"]
set dotenv-filename := "image.env"
set dotenv-load

default:
    @just --list

# Report personal and image-managed configuration drift.
audit:
    ./tooling/audit/workstation

# Show complete diffs for informational image/DMS drift.
audit-diff:
    ./tooling/audit/workstation --diff

# Review portable DMS deviations and capture selected values.
dms-capture *args:
    ./tooling/dms/capture {{ args }}

# Stop tracking selected DMS preference overrides.
dms-remove:
    ./tooling/dms/capture --remove

# Explicitly restore the tracked DMS preference overlay into this account.
[confirm("Overwrite live DMS settings from the tracked overlay?")]
dms-apply:
    WORKSTATION_DMS_SETTINGS_OVERLAY="$PWD/system_files/usr/share/workstation-os-image/dms-settings.json" \
        ./system_files/usr/bin/workstation-apply-dms-settings --force

# Install the AI CLI tools (caveman, rtk, opencode-fusion, playwright-cli) via their official installers; run once after deploy like brew-apply.
ai-tools-install:
    ./tooling/ai/install-ai-tools

# Uninstall the AI CLI tools via their official uninstallers (leaves personal config, auth and history alone).
ai-tools-uninstall:
    ./tooling/ai/uninstall-ai-tools

# Regenerate the portable tooling/ai/ai-cli-setup/ bundle from the repo seeds.
ai-bundle:
    ./tooling/ai/build-ai-cli-bundle

# Reset live codex/claude/opencode config to the repo canonical (dry run without --force).
ai-reset *args:
    ./tooling/ai/reset-ai-cli {{ args }}

# Report where live codex/claude/opencode config has drifted from canonical.
ai-diff *args:
    ./tooling/ai/reset-ai-cli --diff {{ args }}

# Rebuild the Mod+Slash cheatsheet from docs/keybindings.md and the niri binds.
cheatsheet:
    python3 ./tooling/keybindings/build-cheatsheet.py

# Refresh create-only seeds from manifest-listed live files.
sync: cheatsheet
    ./tooling/dotfiles/sync

# Capture reviewed live changes, validate them, and show the Git diff.
capture: sync validate
    git status --short
    git diff --stat
    git diff

# Validate repository structure and the effective local workstation.
validate:
    ./tooling/validate/all

# Install not-yet-installed Brewfile entries (brew, cask, Flatpak); tap trust and daily upgrades are already automatic.
brew-apply:
    brew bundle install --file "${XDG_CONFIG_HOME:-$HOME/.config}/homebrew/Brewfile"

# Install the worktree post-checkout hook and a starter .worktreeinclude into a
# repo (cwd), the given repos, or every repo under ~/projects with --all.
worktree-init *args:
    ./tooling/worktree/init {{ args }}

# Store the intelephense premium PHP licence key for `dev nvim` (machine-local, never committed). Pass --force to overwrite.
intelephense-licence *args:
    ./tooling/dev/intelephense-licence {{ args }}

# Build and lint the complete bootc image locally.
build:
    podman build --pull=always \
        --build-arg "IMAGE_NAME=$IMAGE_NAME" \
        --build-arg "REPO_ORGANIZATION=$REPO_ORGANIZATION" \
        --build-arg "IMAGE_DESC=$IMAGE_DESC" \
        --tag "$IMAGE_NAME:review-$(git branch --show-current | tr / -)" \
        -f Containerfile .

# Report whether the last automatic update succeeded, and which module failed.
update-status:
    ./tooling/audit/updates

# Remove Flatpak runtimes nothing installed still needs.
[confirm("Remove every unused Flatpak runtime from this account?")]
flatpak-prune:
    #!/usr/bin/env bash
    set -euo pipefail
    # uupd updates Flatpaks but never prunes -- it has no such option -- so
    # orphaned runtimes accumulate as apps change or are removed. Interactive
    # and confirmed rather than wired into the update path: this deletes data,
    # and a nightly job that silently removes things is the wrong default.
    flatpak uninstall --unused

# Remove local review images and untracked tool byproducts.
clean:
    #!/usr/bin/env bash
    set -euo pipefail
    # Mirrors .gitignore and deliberately goes no further: `gitleaks dir .` does
    # not respect .gitignore, so anything left in the checkout is inside the
    # secret-scan surface.
    podman image ls --format '{{{{ .Repository }}}}:{{{{ .Tag }}}}' \
        | grep -E '^localhost/'"$IMAGE_NAME"':review-' \
        | xargs -r podman rmi -f
    rm -rf .playwright-cli .agents .claude/skills .codex/skills .playwright
    rm -f nvim.log skills-lock.json
    echo "Removed local review images and untracked tool byproducts."

# Review what changed in Zirconium, the base this image was forked from.
upstream-diff *args:
    ./tooling/upstream/zirconium-diff {{ args }}

# Record that the current Zirconium HEAD has been reviewed. Commit the result.
upstream-accept *args:
    ./tooling/upstream/zirconium-diff --accept {{ args }}

# Show the current repository state without changing it.
status:
    git status --short --branch
    git diff --stat
