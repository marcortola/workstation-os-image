#!/usr/bin/env bash
# What a repository's base branch is, and whether a branch is already in it.
#
# Sourced, not run. Callers: checkout-remove.sh, worktree-ship.sh.
#
# One resolver, because the answer has to be the same in both popups and across
# every repository here: some default to `main`, some to `dev`, and a hardcoded
# name is wrong for one of them whichever it picks. `origin/HEAD` is the real
# answer; the candidate list is only what to try when the remote never published
# one.
#
# `git cherry` rather than `git branch --merged`: GitHub squashes, so a shipped
# branch is not an ancestor of its base and `--merged` never lists it. cherry
# compares patch ids and marks `+` only for commits whose change is absent from
# the base, which reads a squash and a rebase as merged. The PR is the second
# signal, for the branch whose commits landed under a patch id git cannot match.
#
# Every failure answers `unknown`, never `merged`. The caller deletes a branch on
# a merged verdict, so a check that could not run must never produce one.

# The base as it exists on the remote. Shipping needs this one: a PR cannot be
# opened against a branch origin does not have.
merge_base_remote() {
    local repo=$1 base candidate
    base=$(git -C "$repo" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||')
    if [ -z "$base" ]; then
        for candidate in main master trunk dev; do
            if git -C "$repo" rev-parse --verify --quiet "refs/remotes/origin/$candidate" >/dev/null; then
                base=$candidate
                break
            fi
        done
    fi
    printf '%s' "$base"
}

# The same base, falling back to a local branch for a repository with no origin.
# The merge check still works there; shipping does not, which is why the two
# callers ask different questions.
merge_base() {
    local repo=$1 base candidate
    base=$(merge_base_remote "$repo")
    if [ -z "$base" ]; then
        for candidate in main master trunk dev; do
            if git -C "$repo" rev-parse --verify --quiet "refs/heads/$candidate" >/dev/null; then
                base=$candidate
                break
            fi
        done
    fi
    printf '%s' "$base"
}

# Writes one TSV line: verdict, base, unmerged count, PR number, PR state,
# whether origin still has the branch. verdict is merged, unmerged or unknown;
# the count is `unknown` when the comparison could not run at all; an absent PR
# is `-` in both its fields, never empty, because a caller reading this with
# `read` would otherwise lose the field boundaries.
merge_state() {
    local repo=$1 branch=$2
    local base ref cherry unmerged verdict work pr_number pr_state remote

    base=$(merge_base "$repo")

    # The two probes that touch the network, run together rather than in turn.
    # A stale base is the failure that matters: without the fetch, a branch
    # merged an hour ago on GitHub reads as unmerged and the popup keeps a dead
    # branch. Bare `wait` reports success whatever the jobs did, which is what
    # this wants -- offline, both simply contribute nothing.
    #
    # The third asks origin whether it still has the branch at all: a repository
    # with delete-on-merge has already removed most of them, and a caller must
    # not offer to delete what is not there. It is a live question, never the
    # `origin/<branch>` tracking ref, which survives locally until someone
    # prunes and would answer yes for a branch deleted months ago.
    work=$(mktemp -d)
    if [ -n "$base" ]; then
        git -C "$repo" fetch --quiet origin "$base" 2>/dev/null &
    fi
    (cd "$repo" && gh pr view "$branch" --json number,state 2>/dev/null) >"$work/pr" &
    git -C "$repo" ls-remote --heads origin "$branch" >"$work/remote" 2>/dev/null &
    wait
    # `-` rather than empty, and it is not cosmetic: tab is IFS whitespace, so
    # `read` collapses a run of tabs into one delimiter and every field after an
    # empty one shifts left. A branch with no PR reported its own remote flag as
    # the PR number until this was written down.
    pr_number=$(jq -r '.number // "-"' <"$work/pr" 2>/dev/null || printf -- '-')
    pr_state=$(jq -r '.state // "-"' <"$work/pr" 2>/dev/null || printf -- '-')
    [ -n "$pr_number" ] || pr_number=-
    [ -n "$pr_state" ] || pr_state=-
    if [ -s "$work/remote" ]; then
        remote=yes
    else
        remote=no
    fi
    rm -rf "$work"

    # Compare against the remote base when there is one: the local branch of the
    # same name can be behind by days and would call a merged branch unmerged.
    ref=
    if [ -n "$base" ]; then
        if git -C "$repo" rev-parse --verify --quiet "refs/remotes/origin/$base" >/dev/null; then
            ref=origin/$base
        elif git -C "$repo" rev-parse --verify --quiet "refs/heads/$base" >/dev/null; then
            ref=$base
        fi
    fi

    if [ -z "$ref" ] || ! cherry=$(git -C "$repo" cherry "$ref" "$branch" 2>/dev/null); then
        unmerged=unknown
    else
        # grep -c exits 1 on no matches, which is the answer 0, not a failure.
        unmerged=$(printf '%s\n' "$cherry" | grep -c '^+' || true)
    fi

    if [ "$pr_state" = MERGED ] || [ "$unmerged" = 0 ]; then
        verdict=merged
    elif [ "$unmerged" = unknown ]; then
        verdict=unknown
    else
        verdict=unmerged
    fi

    printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$verdict" "$base" "$unmerged" "$pr_number" "$pr_state" "$remote"
}
