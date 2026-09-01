#!/usr/bin/env bash
# worktree.created event hook: populate a fresh checkout, then install deps.
#
# This is a SECOND propagation net, deliberately. The first is each repository's
# committed `.worktreeinclude`, applied by the post-checkout hook through
# `git-worktreeinclude`; that one is per repo, shared with the team, and fires
# for every client that shells out to `git worktree add`. This one is
# machine-local and fires only for herdr-created worktrees.
#
# The list below is the union of every `.worktreeinclude` in ~/projects at the
# time it was written. It is intentionally NOT a gitignore engine: patterns
# expand at the checkout root only, plus the handful of explicit nested paths
# that repositories actually use. Anything deeper is the `.worktreeinclude`
# net's job. A file is copied only when git already ignores it in the source
# checkout, so a tracked file is never duplicated.
set -euo pipefail

INCLUDE_PATTERNS=(
    # Local environment and secrets
    .env
    .env.local
    .env.*.local
    .env.production
    .env.e2e
    e2e/.env.e2e
    # IDE and editor local config
    .idea/
    .vscode/
    # Agent local (machine-specific) settings
    .claude/settings.local.json
    CLAUDE.local.md
    # Toolchain pins and local compose overrides
    .nvmrc
    docker-compose.override.yml
    # Infrastructure keys and variable files
    .ssh/
    secrets/
    '*.pem'
    '*.key'
    '*.tfvars'
    '*.tfvars.json'
    '*.auto.tfvars'
    # Repository-specific one-offs
    docs/showcase-video-generation/.eleven_key
)

record_event_payload() {
    [ -n "${HERDR_PLUGIN_STATE_DIR:-}" ] || return 0
    mkdir -p "$HERDR_PLUGIN_STATE_DIR"
    printf '%s\n' "${HERDR_PLUGIN_EVENT_JSON:-}" >>"$HERDR_PLUGIN_STATE_DIR/last-worktree-event.json"
}

first_path_in_json() {
    printf '%s' "$1" | jq -r '.data.worktree.path // .data.workspace.worktree.checkout_path // ([.. | objects | (.checkout_path? // .path?) | select(type == "string")] | first) // empty' 2>/dev/null || true
}

resolve_worktree_path() {
    if [ -n "${1:-}" ]; then
        printf '%s\n' "$1"
        return 0
    fi
    local json path
    for json in "${HERDR_PLUGIN_EVENT_JSON:-}" "${HERDR_PLUGIN_CONTEXT_JSON:-}"; do
        [ -n "$json" ] || continue
        path=$(first_path_in_json "$json")
        if [ -n "$path" ]; then
            printf '%s\n' "$path"
            return 0
        fi
    done
}

main_repo_of() {
    dirname "$(git -C "$1" rev-parse --path-format=absolute --git-common-dir)"
}

copy_missing_includes() {
    local from=$1 to=$2 pattern match relative
    for pattern in "${INCLUDE_PATTERNS[@]}"; do
        # A trailing slash is a directory in gitignore syntax; the glob below
        # matches it either way, so strip it before expanding.
        for match in "$from"/${pattern%/}; do
            [ -e "$match" ] || continue
            relative=${match#"$from/"}
            [ -e "$to/$relative" ] && continue
            # Never duplicate a tracked file: only what git already ignores.
            git -C "$from" check-ignore -q -- "$relative" || continue
            mkdir -p "$(dirname "$to/$relative")"
            cp -R "$match" "$to/$relative"
        done
    done
}

# Node only, matching upstream. A PHP or Python worktree gets its files but not
# its vendor tree; those installs are slow enough to want to start by hand.
install_dependencies() {
    local dir=$1
    [ -f "$dir/package.json" ] || return 0
    [ -d "$dir/node_modules" ] && return 0
    if [ -f "$dir/pnpm-lock.yaml" ]; then
        (cd "$dir" && CI=true pnpm install)
    elif [ -f "$dir/yarn.lock" ]; then
        (cd "$dir" && CI=true yarn install --frozen-lockfile)
    elif [ -f "$dir/package-lock.json" ]; then
        (cd "$dir" && CI=true npm ci)
    else
        (cd "$dir" && CI=true npm install)
    fi
}

record_event_payload

worktree=$(resolve_worktree_path "${1:-}")
if [ -z "$worktree" ] || [ ! -d "$worktree" ]; then
    echo "worktree path not resolved" >&2
    exit 1
fi

copy_missing_includes "$(main_repo_of "$worktree")" "$worktree"
install_dependencies "$worktree"
