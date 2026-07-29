set shell := ["bash", "-euo", "pipefail", "-c"]

default:
    @just --list

# Report personal and Zirconium-managed configuration drift.
audit:
    ./tooling/audit-workstation

# Show complete diffs for informational Zirconium/DMS drift.
audit-diff:
    ./tooling/audit-workstation --diff

# Review portable DMS deviations and capture selected values.
dms-capture:
    ./tooling/capture-dms-settings

# Stop tracking selected DMS preference overrides.
dms-remove:
    ./tooling/capture-dms-settings --remove

# Explicitly restore the tracked DMS preference overlay into this account.
dms-apply:
    WORKSTATION_DMS_SETTINGS_OVERLAY="$PWD/rootfs/usr/share/workstation-os-image/dms-settings.json" \
        ./rootfs/usr/bin/workstation-apply-dms-settings --force

# Report where installed JetBrains IDEs diverge from the shared canonical.
jetbrains-diff:
    ./tooling/diff-jetbrains-settings

# Refresh the shared JetBrains canonical (_shared/) from the canonical IDE.
jetbrains-promote product="":
    ./tooling/promote-jetbrains-shared {{ product }}

# Write the shared JetBrains config and install shared plugins into the IDEs
# (dry run without --force).
jetbrains-apply *args:
    ./tooling/apply-jetbrains-settings {{ args }}
    ./tooling/apply-jetbrains-plugins {{ args }}

# Install the shared JetBrains plugins into the IDEs (dry run without --force).
jetbrains-plugins *args:
    ./tooling/apply-jetbrains-plugins {{ args }}

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
    ./tooling/sync-dotfiles

# Capture reviewed live changes, validate them, and show the Git diff.
capture: sync validate
    git status --short
    git diff --stat
    git diff

# Validate repository structure and the effective local workstation.
validate:
    ./tooling/validate

# Install not-yet-installed Brewfile entries (brew, cask, Flatpak); tap trust and daily upgrades are already automatic.
brew-apply:
    brew bundle install --file "${XDG_CONFIG_HOME:-$HOME/.config}/homebrew/Brewfile"

# Install the worktree post-checkout hook and a starter .worktreeinclude into a
# repo (cwd), the given repos, or every repo under ~/projects with --all.
worktree-init *args:
    ./tooling/worktree-init {{ args }}

# Store the intelephense premium PHP licence key for `dev nvim` (machine-local, never committed). Pass --force to overwrite.
intelephense-licence *args:
    ./tooling/set-intelephense-licence {{ args }}

# Set up this machine's IDE config (run once after deploy): store the intelephense
# premium PHP key for `dev nvim`, install the shared JetBrains plugins (dry run
# without --force), then optionally apply the shared JetBrains settings (asks
# interactively, defaults to no, skipped when non-interactive). `*args` scope the
# plugin step (--force installs, --product NAME). The settings step overwrites
# local IDE config and primes a GUI cloud push, hence the prompt; `jetbrains-apply`
# is the non-interactive path. JetBrains is the fallback; steps no-op without an IDE.
ide-setup *args:
    ./tooling/set-intelephense-licence
    ./tooling/apply-jetbrains-plugins {{ args }}
    ./tooling/ide-setup-jetbrains-settings

# Build and lint the complete bootc image locally.
build:
    podman build --pull=always --tag workstation-os-image:review -f Containerfile .

# Show the current repository state without changing it.
status:
    git status --short --branch
    git diff --stat
