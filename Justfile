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
dms-capture:
    ./tooling/dms/capture

# Stop tracking selected DMS preference overrides.
dms-remove:
    ./tooling/dms/capture --remove

# Explicitly restore the tracked DMS preference overlay into this account.
[confirm("Overwrite live DMS settings from the tracked overlay?")]
dms-apply:
    WORKSTATION_DMS_SETTINGS_OVERLAY="$PWD/system_files/usr/share/workstation-os-image/dms-settings.json" \
        ./system_files/usr/bin/workstation-apply-dms-settings --force

# Report where installed JetBrains IDEs diverge from the shared canonical.
jetbrains-diff:
    ./tooling/jetbrains/diff

# Refresh the shared JetBrains canonical (_shared/) from the canonical IDE.
jetbrains-promote product="":
    ./tooling/jetbrains/promote-shared {{ product }}

# Write the shared JetBrains config and install shared plugins into the IDEs
# (dry run without --force).
jetbrains-apply *args:
    ./tooling/jetbrains/apply-settings {{ args }}
    ./tooling/jetbrains/apply-plugins {{ args }}

# Install the shared JetBrains plugins into the IDEs (dry run without --force).
jetbrains-plugins *args:
    ./tooling/jetbrains/apply-plugins {{ args }}

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

# Refresh create-only seeds from manifest-listed live files.
sync:
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
    ./tooling/jetbrains/intelephense-licence {{ args }}

# Set up this machine's IDE config (run once after deploy): store the intelephense
# premium PHP key for `dev nvim`, install the shared JetBrains plugins (dry run
# without --force), then optionally apply the shared JetBrains settings (asks
# interactively, defaults to no, skipped when non-interactive). `*args` scope the
# plugin step (--force installs, --product NAME). The settings step overwrites
# local IDE config and primes a GUI cloud push, hence the prompt; `jetbrains-apply`
# is the non-interactive path. JetBrains is the fallback; steps no-op without an IDE.
ide-setup *args:
    ./tooling/jetbrains/intelephense-licence
    ./tooling/jetbrains/apply-plugins {{ args }}
    ./tooling/jetbrains/ide-setup

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

# Show the current repository state without changing it.
status:
    git status --short --branch
    git diff --stat
