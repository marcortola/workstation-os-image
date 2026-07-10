set shell := ["bash", "-euo", "pipefail", "-c"]

default:
    @just --list

# Report personal and Zirconium-managed configuration drift.
audit:
    ./scripts/audit-workstation

# Show complete diffs for informational Zirconium/DMS drift.
audit-diff:
    ./scripts/audit-workstation --diff

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
