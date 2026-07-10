set shell := ["bash", "-euo", "pipefail", "-c"]

default:
    @just --list

# Report personal and Zirconium-managed configuration drift.
audit:
    ./scripts/audit-workstation

# Show complete diffs for informational Zirconium/DMS drift.
audit-diff:
    ./scripts/audit-workstation --diff

# Review portable DMS deviations and capture selected values.
dms-capture:
    ./scripts/capture-dms-settings

# Stop tracking selected DMS preference overrides.
dms-remove:
    ./scripts/capture-dms-settings --remove

# Merge the tracked DMS preference overlay into this account.
dms-apply:
    WORKSTATION_DMS_SETTINGS_OVERLAY="$PWD/system_files/usr/share/workstation-os-image/dms-settings.json" \
        ./system_files/usr/bin/workstation-apply-dms-settings

# Refresh create-only seeds from manifest-listed live files.
sync:
    ./scripts/sync-dotfiles

# Capture reviewed live changes, validate them, and show the Git diff.
capture: sync validate
    git status --short
    git diff --stat
    git diff

# Validate repository structure and the effective local workstation.
validate:
    ./scripts/validate

# Build and lint the complete bootc image locally.
build:
    podman build --pull=always --tag workstation-os-image:review -f Containerfile .

# Show the current repository state without changing it.
status:
    git status --short --branch
    git diff --stat
