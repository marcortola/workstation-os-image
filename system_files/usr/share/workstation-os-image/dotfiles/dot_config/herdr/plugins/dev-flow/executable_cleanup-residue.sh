#!/usr/bin/env bash
# The sweep behind the removal popups: everything they cannot reach.
#
# A popup only ever runs on a space you are closing. A checkout removed any
# other way -- /worktree-remove, `git worktree remove`, a herdr worktree.remove
# over the socket -- leaves its branch behind with nothing to trigger the
# cleanup, and once the local branch goes the remote one is invisible to every
# path there is. This is where that accumulates: a first run found fifty-six
# such items across fifteen repositories.
#
# Residue is a directory inside a `*__worktrees` parent that its repository no
# longer lists. For each, this shows what is there, which branch its slug points
# at and what the merge check says, then asks once about the directory, once
# about the local branch and once about the branch on origin. All default to no.
#
# The remote question is asked here on the merged verdict, where the popup wants
# a merged PR: this is a one-off run with the evidence for each branch on screen
# and a human reading it, rather than one keystroke inside a popup.
#
# `--dry-run` prints what it would do and touches nothing.
#
# `--remotes` adds a second pass over branches that still exist on origin -- what
# the first pass leaves behind, since it only ever reaches a branch through a
# residue directory. That pass never offers a long-lived branch, never one with
# an open PR, and never one with a commit that is not in the base.
#
# It used to skip any branch that still had a local branch, on the reasoning that
# a surviving local branch means the remote is not orphaned yet. That is true
# only while something still holds it. A checkout removed cleanly leaves no
# residue, so the first pass never deletes the local branch, so the second pass
# never sees the remote: a whole class reachable by neither, found by a sweep at
# eight branches across seven repositories. The guard is now what it meant --
# skip while the branch is CHECKED OUT, or has work not in the base -- and a
# branch past both is deleted on both sides under one answer, the way the
# prefix+shift+x popup does it.
#
# `--locals` adds a third pass over local branches with no remote at all: merged,
# not checked out, nothing on origin to delete. Neither other pass can see these
# -- the first needs residue, the second needs a remote -- and they are most of
# what makes `git branch` unreadable.
set -uo pipefail

plugin_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=merge-state.sh
. "$plugin_dir/merge-state.sh"

dry_run=false
do_remotes=false
do_locals=false
for arg in "$@"; do
    case $arg in
        --dry-run) dry_run=true ;;
        --remotes) do_remotes=true ;;
        --locals) do_locals=true ;;
        --all) do_remotes=true; do_locals=true ;;
        *) printf 'usage: cleanup-residue.sh [--dry-run] [--remotes] [--locals] [--all]\n' >&2; exit 2 ;;
    esac
done

home=$(realpath -- "$HOME")

ask() {
    local answer
    printf '%s' "$1"
    read -r answer </dev/tty || return 1
    case $answer in
        y | Y | yes) return 0 ;;
        *) return 1 ;;
    esac
}

slugify() {
    printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-//; s/-$//'
}

removed=0
branches=0
remotes=0
touched_repos=()

for wt_dir in "$home"/projects/*/*__worktrees; do
    [ -d "$wt_dir" ] || continue
    repo=${wt_dir%__worktrees}
    [ -d "$repo/.git" ] || continue
    registered=$(git -C "$repo" worktree list --porcelain | awk '/^worktree /{print $2}')

    for checkout in "$wt_dir"/*; do
        [ -d "$checkout" ] || continue
        real=$(realpath -- "$checkout")
        printf '%s\n' "$registered" | grep -qxF "$real" && continue

        # The same guard the popup uses, because this runs the same command.
        parent=$(dirname -- "$real")
        if [ "${real#"$home"/}" = "$real" ] || [ "${parent%__worktrees}" = "$parent" ] ||
            [ "$real" = "$repo" ]; then
            printf '\nskipping %s: fails the checkout guard\n' "$real"
            continue
        fi

        files=$(find "$real" -mindepth 1 2>/dev/null | wc -l)
        foreign=$(find "$real" -mindepth 1 ! -uid "$(id -u)" 2>/dev/null | wc -l)
        slug=$(basename "$real")
        branch=
        while read -r candidate; do
            [ "$(slugify "$candidate")" = "$slug" ] && branch=$candidate && break
        done < <(git -C "$repo" for-each-ref --format='%(refname:short)' refs/heads)

        verdict=none
        base=
        unmerged=
        pr_number=
        pr_state=
        remote=no
        if [ -n "$branch" ]; then
            IFS=$'\t' read -r verdict base unmerged pr_number pr_state remote \
                < <(merge_state "$repo" "$branch")
        fi

        printf '\n=== %s\n' "$real"
        printf '    %s file(s), %s owned by another uid\n' "$files" "$foreign"
        if [ -n "$branch" ]; then
            printf '    branch %s: %s (%s not in %s, PR %s %s)\n' \
                "$branch" "$verdict" "$unmerged" "$base" "${pr_number:-none}" "$pr_state"
            [ "$remote" = yes ] && printf '    origin still has this branch\n'
        else
            printf '    no local branch matches this slug\n'
        fi

        if $dry_run; then
            printf '    would run: sudo rm -rf %s\n' "$real"
            [ "$verdict" = merged ] && printf '    would offer: git -C %s branch -D %s\n' "$repo" "$branch"
            [ "$verdict" = merged ] && [ "$remote" = yes ] &&
                printf '    would offer: git -C %s push origin --delete %s\n' "$repo" "$branch"
            continue
        fi

        ask '    delete this directory? [y/N] ' || continue
        if ! sudo rm -rf -- "$real"; then
            printf '    could not remove it\n'
            continue
        fi
        removed=$((removed + 1))
        touched_repos+=("$repo")
        printf '    removed\n'

        if [ "$verdict" = merged ]; then
            if ask "    delete branch $branch too? it is already in $base [y/N] "; then
                git -C "$repo" branch -D "$branch" | sed 's/^/    /' && branches=$((branches + 1))
            fi
            if [ "$remote" = yes ] &&
                ask "    delete origin/$branch as well? this is the shared remote [y/N] "; then
                if git -C "$repo" push origin --delete "$branch"; then
                    remotes=$((remotes + 1))
                else
                    printf '    origin/%s was not deleted\n' "$branch"
                fi
            fi
        elif [ -n "$branch" ]; then
            printf '    branch %s kept (%s)\n' "$branch" "$verdict"
        fi
    done
done

if ! $dry_run; then
    for repo in $(printf '%s\n' "${touched_repos[@]:-}" | sort -u); do
        [ -n "$repo" ] || continue
        git -C "$repo" worktree prune
    done
    printf '\n%s director(ies) removed, %s local branch(es) deleted, %s on origin\n' \
        "$removed" "$branches" "$remotes"
fi

if ! $do_remotes && ! $do_locals; then
    exit 0
fi

# Hoisted: both later passes need it, and either can run without the other.
protected="main master dev develop trunk staging production"

if $do_remotes; then
    # Second pass: branches on origin that nothing is using any more.
    #
    # The bar is deliberately higher than the popup's, because there is no checkout
    # and no workspace here to tie a branch to a person -- only the repository. A
    # branch is offered only when every one of these holds: it is not the base or
    # any other long-lived branch, no worktree has it checked out, `git cherry`
    # finds nothing in it that is not in the base -- on the remote branch AND on the
    # local one if there is one -- and GitHub does not report an open PR. `dev` in
    # one of these repositories satisfies the merge test and is exactly what the
    # name list exists to stop.
    #
    # Every repository, not only the ones with a `*__worktrees` parent: the first
    # pass needs that directory because residue lives inside it, and these two do
    # not. Scoping them the same way hid nine orphaned remotes across four
    # repositories that have never had a worktree.
    printf '\n\n=== branches on origin nothing is using\n'

    for repo in "$home"/projects/*/*; do
        [ -d "$repo/.git" ] || continue
        git -C "$repo" remote get-url origin >/dev/null 2>&1 || continue

        printf '\nrepo: %s\n' "$repo"
        git -C "$repo" fetch --prune --quiet origin 2>/dev/null || true
        base=$(merge_base_remote "$repo")
        if [ -z "$base" ]; then
            printf '    no base branch on origin, skipping\n'
            continue
        fi

        while read -r branch; do
            [ -n "$branch" ] || continue
            [ "$branch" = "$base" ] && continue
            for keep in $protected; do
                [ "$branch" = "$keep" ] && continue 2
            done
            local_exists=no
            if git -C "$repo" rev-parse --verify --quiet "refs/heads/$branch" >/dev/null; then
                local_exists=yes
                where=$(checked_out_at "$repo" "$branch")
                if [ -n "$where" ]; then
                    printf '    %s: checked out at %s, keeping\n' "$branch" "$where"
                    continue
                fi
                if ! branch_is_spent "$repo" "origin/$base" "$branch"; then
                    printf '    %s: local branch holds work not in %s, keeping\n' "$branch" "$base"
                    continue
                fi
            fi

            branch_is_spent "$repo" "origin/$base" "origin/$branch" || continue

            pr_state=$( (cd "$repo" && gh pr view "$branch" --json state --jq .state 2>/dev/null) || true)
            if [ "$pr_state" = OPEN ]; then
                printf '    %s: open PR, keeping\n' "$branch"
                continue
            fi

            if [ "$local_exists" = yes ]; then
                printf '    %s: in %s, local branch idle, PR %s\n' "$branch" "$base" "${pr_state:-none}"
            else
                printf '    %s: in %s, no local branch, PR %s\n' "$branch" "$base" "${pr_state:-none}"
            fi
            if $dry_run; then
                if [ "$local_exists" = yes ]; then
                    printf '        would offer: git -C %s branch -D %s\n' "$repo" "$branch"
                fi
                printf '        would offer: git -C %s push origin --delete %s\n' "$repo" "$branch"
                continue
            fi

            # One answer for both sides, like the popup: deleting the local branch
            # on its own is what created this category in the first place.
            if [ "$local_exists" = yes ]; then
                prompt="        delete $branch, local and on origin? [y/N] "
            else
                prompt="        delete origin/$branch? [y/N] "
            fi
            if ask "$prompt"; then
                if [ "$local_exists" = yes ]; then
                    if git -C "$repo" branch -D "$branch" | sed 's/^/        /'; then
                        branches=$((branches + 1))
                    else
                        printf '        %s was not deleted locally\n' "$branch"
                    fi
                fi
                if git -C "$repo" push origin --delete "$branch"; then
                    remotes=$((remotes + 1))
                else
                    printf '        origin/%s was not deleted\n' "$branch"
                fi
            fi
        done < <(git -C "$repo" ls-remote --heads origin | awk '{print $2}' | sed 's|refs/heads/||')
    done

    $dry_run || printf '\n%s branch(es) deleted on origin in total\n' "$remotes"
fi

$do_locals || exit 0

# Third pass: local branches with nothing on origin at all.
#
# Neither other pass can see these. The first needs a residue directory, the
# second needs a remote branch to offer -- and a branch that was never pushed,
# or whose remote is already gone, has neither. They are harmless and they are
# most of what makes `git branch` unreadable: thirty-four of them across six
# repositories when this pass was written, fourteen in one.
#
# Same bar as the second pass minus the parts that need a remote: not the base
# or a long-lived name, no worktree holding it, and nothing in it that is not
# already in the base. No PR check, because there is no remote branch for a PR
# to be open against.
printf '\n\n=== local branches with no remote\n'

locals_deleted=0

for repo in "$home"/projects/*/*; do
    [ -d "$repo/.git" ] || continue
    git -C "$repo" remote get-url origin >/dev/null 2>&1 || continue

    base=$(merge_base_remote "$repo")
    [ -n "$base" ] || continue

    printed_repo=false
    while read -r branch; do
        [ -n "$branch" ] || continue
        [ "$branch" = "$base" ] && continue
        for keep in $protected; do
            [ "$branch" = "$keep" ] && continue 2
        done
        git -C "$repo" rev-parse --verify --quiet "refs/remotes/origin/$branch" >/dev/null && continue
        [ -n "$(checked_out_at "$repo" "$branch")" ] && continue
        branch_is_spent "$repo" "origin/$base" "$branch" || continue

        if ! $printed_repo; then
            printf '\nrepo: %s\n' "$repo"
            printed_repo=true
        fi
        printf '    %s: in %s, no remote, not checked out\n' "$branch" "$base"
        if $dry_run; then
            printf '        would offer: git -C %s branch -D %s\n' "$repo" "$branch"
            continue
        fi
        if ask "        delete $branch? [y/N] "; then
            if git -C "$repo" branch -D "$branch" | sed 's/^/        /'; then
                locals_deleted=$((locals_deleted + 1))
            else
                printf '        %s was not deleted\n' "$branch"
            fi
        fi
    done < <(git -C "$repo" for-each-ref --format='%(refname:short)' refs/heads)
done

$dry_run || printf '\n%s local branch(es) deleted\n' "$locals_deleted"
