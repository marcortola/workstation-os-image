#!/usr/bin/env bash
# prefix+shift+m popup: ship the branch in this checkout to its base branch.
#
# Mechanical only, deliberately. Writing a commit message and resolving a merge
# both need judgement, and they stay with the /worktree-push agent command; this
# covers the tail that needs none -- push, open the PR, and let GitHub merge it
# when the checks pass. It refuses on a dirty tree rather than inventing a
# commit, and it never deletes a branch.
set -euo pipefail

herdr_cli() {
    "${HERDR_BIN_PATH:-herdr}" "$@"
}

# The popup dies with the script, so anything that failed has to hold the window
# open long enough to be read. 130 is the interrupt path and closes silently.
work=$(mktemp -d)
on_exit() {
    local status=$?
    rm -rf "$work"
    if [ "$status" -ne 0 ] && [ "$status" -ne 130 ]; then
        printf '\nfailed (exit %s). press enter to close\n' "$status"
        read -r _ </dev/tty || true
    fi
}
trap on_exit EXIT
trap 'exit 0' INT TERM

die() {
    printf '%s\n' "$1" >&2
    exit 1
}

ask() {
    local answer
    read -r -n 1 -s answer </dev/tty || return 1
    printf '%s' "$answer"
}

start_cwd=${HERDR_ACTIVE_PANE_CWD:-$PWD}
repo=$(git -C "$start_cwd" rev-parse --show-toplevel 2>/dev/null) || die 'not a git checkout'
branch=$(git -C "$repo" symbolic-ref --quiet --short HEAD) || die 'detached HEAD, nothing to ship'

# Never hardcode main: the base is whatever origin points its HEAD at.
base=$(git -C "$repo" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||')
if [ -z "$base" ]; then
    for candidate in main master trunk; do
        if git -C "$repo" rev-parse --verify --quiet "refs/remotes/origin/$candidate" >/dev/null; then
            base=$candidate
            break
        fi
    done
fi
[ -n "$base" ] || die 'no base branch on origin'
[ "$branch" != "$base" ] || die "already on $base, nothing to ship"

# The three network probes cost more than everything local put together, so they
# run while the local ones do.
gh_account_of() {
    gh auth status --active 2>/dev/null |
        sed -n 's/.*account \([^ ]*\).*/\1/p' | head -1
}
gh_account_of >"$work/account" &
git -C "$repo" fetch --quiet origin "$base" 2>/dev/null &
(cd "$repo" && gh pr view "$branch" --json number,state,url 2>/dev/null) >"$work/pr" &
wait

dirty=$(git -C "$repo" status --porcelain)
ahead=$(git -C "$repo" rev-list --count "origin/$base..$branch" 2>/dev/null || echo 0)
behind=$(git -C "$repo" rev-list --count "$branch..origin/$base" 2>/dev/null || echo 0)

if git -C "$repo" rev-parse --verify --quiet "refs/remotes/origin/$branch" >/dev/null &&
    [ -z "$(git -C "$repo" rev-list "origin/$branch..$branch")" ]; then
    pushed=pushed
else
    pushed=unpushed
fi

pr_number=$(jq -r '.number // empty' <"$work/pr" 2>/dev/null || true)
pr_url=$(jq -r '.url // empty' <"$work/pr" 2>/dev/null || true)
pr_state=$(jq -r '.state // empty' <"$work/pr" 2>/dev/null || true)

printf 'ship: %s [%s]\n' "$(basename "$repo")" "$branch"
printf 'branch %s -> %s\n\n' "$branch" "$base"
if [ -n "$dirty" ]; then
    printf '  tree      %s file(s) uncommitted\n' "$(printf '%s\n' "$dirty" | wc -l | tr -d ' ')"
else
    printf '  tree      clean\n'
fi
printf '  ahead     %s commits, %s\n' "$ahead" "$pushed"
if [ "$behind" -gt 0 ]; then
    printf '  base      %s behind origin/%s\n' "$behind" "$base"
else
    printf '  base      up to date with origin/%s\n' "$base"
fi
if [ -n "$pr_number" ]; then
    printf '  PR        #%s %s\n' "$pr_number" "$pr_state"
else
    printf '  PR        none\n'
fi
printf '  gh acct   %s\n\n' "$(cat "$work/account")"

if [ -n "$dirty" ]; then
    printf '%s\n' "$dirty" | head -10
    printf '\ncommit first. this popup never writes a commit; /worktree-push does.\n'
    printf '\n[q] close '
    ask >/dev/null
    exit 0
fi

if [ "$ahead" -eq 0 ] && [ -z "$pr_number" ]; then
    printf 'nothing to ship: no commits on top of %s\n\n[q] close ' "$base"
    ask >/dev/null
    exit 0
fi

if [ -n "$pr_number" ]; then
    printf '[p] push + auto-merge   [q] cancel '
else
    printf '[p] push + open PR   [q] cancel '
fi
case $(ask) in
    p | P) printf 'p\n\n' ;;
    *) exit 0 ;;
esac

# A push goes out as gh's active account, not as the repository's owner, and a
# mismatch fails with a 403 that says nothing about which account was used.
if ! git -C "$repo" push -u origin "$branch"; then
    printf '\npush failed. pushes go out as the gh account above; `gh auth switch` changes it.\n'
    exit 1
fi

if [ -z "$pr_number" ]; then
    (cd "$repo" && gh pr create --fill --base "$base") || exit 1
    pr_url=$(cd "$repo" && gh pr view "$branch" --json url --jq .url)
fi

printf '\n'
if (cd "$repo" && gh pr merge "$branch" --auto --squash) 2>"$work/merge.err"; then
    printf 'auto-merge armed; GitHub squashes it when the checks pass\n'
else
    cat "$work/merge.err"
    printf '\nauto-merge is off for this repository.\n'
    printf 'enable it once with: gh api -X PATCH repos/{owner}/{repo} -f allow_auto_merge=true\n'
    printf '\n[m] merge now   [q] leave the PR open '
    case $(ask) in
        m | M)
            printf 'm\n\n'
            (cd "$repo" && gh pr merge "$branch" --squash) || exit 1
            ;;
        *)
            printf '\n%s\n' "$pr_url"
            exit 0
            ;;
    esac
fi

printf '%s\n' "$pr_url"

# Only a linked checkout can be removed, and only herdr knows which space holds
# it. The branch is never deleted here: /worktree-remove owns that, because it
# is the one that checks whether the merge actually landed.
common_dir=$(git -C "$repo" rev-parse --path-format=absolute --git-common-dir)
workspace=${HERDR_ACTIVE_WORKSPACE_ID:-${HERDR_WORKSPACE_ID:-}}
if [ "$common_dir" = "$repo/.git" ] || [ -z "$workspace" ]; then
    exit 0
fi

printf '\ndelete this checkout from disk? the branch is kept [y/N] '
read -r answer </dev/tty || exit 0
case $answer in
    y | Y | yes) ;;
    *) exit 0 ;;
esac
herdr_cli worktree remove --workspace "$workspace" --force >/dev/null
