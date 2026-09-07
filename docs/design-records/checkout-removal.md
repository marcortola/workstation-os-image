# Removing a Checkout

The record for teaching the removal popups to finish the job: why
`git worktree remove` fails half way and leaves a directory nothing will ever
clean up, why the retry that was there could not work, and why the popup now
deletes a merged branch that it previously always kept.

**Six checkouts were sitting in one repository's `__worktrees` directory,
holding 24,000 files, with git no longer aware that any of them existed — and
every one of them had been removed through the popup, which reported nothing
wrong beyond a single failure the user had already dismissed.**

---

## Context

`prefix+shift+x` closes a space and, when it holds a linked worktree, offers to
delete the checkout. `prefix+shift+m` ships a branch and then offers the same.
Both end in `dev-flow/checkout-remove.sh`, which asks, and then calls
`herdr worktree remove --workspace`. Underneath, that is `git worktree remove`.

Docker on this machine is rootful, deliberately — see
[../subsystems/packages.md](../subsystems/packages.md). A project whose compose
services declare no `user:` therefore writes into the bind-mounted checkout as
root: `vendor/`, `var/cache`, `.phpunit.result.cache`. All of it is gitignored,
so `git status --porcelain` — the probe the popup used to decide whether the
tree was clean — reports nothing at all.

`git worktree remove` then does two things in order, and the second one
unconditionally:

```
	ret = delete_git_work_tree(wt);
	/*
	 * continue on even if ret is non-zero, there's no going back
	 * from here.
	 */
	ret |= delete_git_dir(wt->id);
```

The work-tree deletion stops at the first `EACCES` — a user cannot unlink
entries inside a root-owned directory — and the admin dir under
`.git/worktrees/` is deleted anyway. The checkout is now a directory git does
not list, holding files the user cannot delete, with a herdr workspace still
pointing at it.

What the popup did next was retry with `--force`, under a prompt that read
"git status showed nothing, so this is state the probe cannot see". Against this
refusal that retry cannot succeed and never could: there is no worktree left to
force. The observed second error was `fatal: '<path>' is not a working tree`.

Six directories accumulated that way, along with five local branches whose
checkouts were gone, because the popup has never deleted a branch.

---

## Decision

Probe for foreign ownership before removing anything, and answer the two
refusals differently. Then, and only for a branch that is already in its base,
offer the branch too.

### The probe runs first

`find "$checkout" -mindepth 1 ! -uid "$(id -u)"` is the question `git status`
structurally cannot answer, because everything it finds is ignored. It runs
alongside the status probe, before the first prompt, and its result is on screen
with the checkout:

```
root-owned: var vendor .phpunit.result.cache (8339 file(s))
            written by a rootful container. git can neither see nor
            delete them, so removing this checkout needs sudo.
```

When it finds something, git is never asked to remove the checkout at all —
being asked is what breaks it. The removal is `sudo rm -rf` followed by
`git worktree prune`, which is also exactly what recovers a checkout that an
earlier removal already half-deleted.

### The guard on the only irreversible command

`sudo rm -rf` is pointed at a path only after it is proved to be a checkout:
resolved with `realpath`, still a directory, under `$HOME`, not the repository
root, and sitting directly inside a `*__worktrees` parent — the layout
[../subsystems/dev-environment.md](../subsystems/dev-environment.md) pins every
checkout to. Anything else prints the command and refuses to run it.

`$HOME` is `/home/marc` while every real path is `/var/home/marc`, so the
comparison is between resolved paths. Written the obvious way, the guard refuses
every checkout on the machine.

### The `--force` retry still exists, for the refusal it fits

git refusing while nothing foreign is present is a different failure — a
modified submodule is the usual one — and `--force` is the right answer to it.
So the escalation is now chosen by re-probing rather than assumed: foreign
owners take the root path, everything else keeps the FORCE prompt that was
already there.

### The branch, but only when it has landed

`merge-state.sh` answers `merged`, `unmerged` or `unknown` from two signals run
in parallel: `git cherry` against the base after a `git fetch origin <base>`,
and `gh pr view --json state`. `git cherry` compares patch ids, so a squash
merge — which is how everything here lands — reads as merged, where
`git branch --merged` would not list it at all. The base is `origin/HEAD`,
falling back to the first of `main`, `master`, `trunk`, `dev` that exists,
because the repositories on this machine do not agree on one.

A `merged` verdict earns a second, separate prompt. Anything else keeps the
branch and prints the `git branch -D` line. A check that could not run answers
`unknown`, never `merged`: the popup deletes on a merged verdict, so a failed
check must never produce one.

The branch is deleted **before** the checkout, with a detach in front of it. A
branch cannot be deleted while a worktree has it checked out, and the removal
that would free it closes the workspace — which may take the popup's window with
it. Detaching writes no files, `git branch -D` prints the sha it deleted, and
that sha is the whole recovery if the removal then fails.

### The branch on origin, in the same answer

`origin/<branch>` is not a third question. A branch deleted here is deleted in
both places or in neither, under the one answer the merged verdict earns.

It was a third question, and it needed `gh` reporting the PR as `MERGED` --
`git cherry` agreeing proves the patch reached the base, not that a branch other
people can see is finished with. The reasoning is still true and the design was
still wrong, because it is not the only thing that has to hold. Deleting the
local branch is what makes the remote one invisible: no popup can reach a branch
whose checkout is gone, and the sweep that covers what popups miss keyed on
"does a local branch exist" for exactly the same reason. A branch that lost its
local half and kept its remote half fell between all of them. That is not a
hypothesis -- a sweep across fifteen repositories found eight of them, none
reachable by any existing path.

So the strictness moved rather than disappeared. The verdict still has to be
`merged`; what is gone is the second, higher bar for the half that goes last.
The prompt names both places when origin has the branch, so the keystroke never
does more than the question it answered.

The evidence for keeping the question at all is that GitHub does not close the
gap by itself. `viralitymedia/growwer` has `deleteBranchOnMerge: true`, which is
why four of the six residue branches had no remote ref left — but
`fix/errors-in-rollbar` and `feature/improve-auto-media-revie` were merged
without a PR, so their remote branches survived and nothing was ever going to
remove them.

Whether origin still has the branch is asked of origin, with `ls-remote`, in the
same parallel block as the fetch and the PR probe. The `origin/<branch>`
tracking ref is not an answer: it survives locally until someone prunes, so it
reports a branch deleted months ago as present.

One protocol detail is load-bearing enough to write down. `merge_state` emits
`-` for an absent PR rather than an empty field, because tab is IFS whitespace
and `read` collapses a run of tabs into one delimiter — with empty PR fields,
every field after them shifted left, and the popup displayed its own remote flag
as the PR number.

This reverses a rule this repository stated explicitly: *never teach it to
delete a branch: that needs the merge check, which is `/worktree-remove`'s.* The
merge check is now a shared script rather than a thing only an agent can do, and
the cost of the old rule was measured in the five branches it left behind.
`/worktree-remove` remains the command for an unmerged branch, a checkout with
no open workspace, and the nvim session file — none of which the popup touches.

---

## Routes That Lost

**Fix the containers instead.** A compose `user: "${UID}:${GID}"`, or a userns
remap on the daemon. It addresses the cause, and it is not ours: the compose
files belong to other repositories and other people, and one of them is enough
to reproduce this. The popup has to cope with any repository it is pointed at.

**Refuse, and print the sudo command.** Honest, and it is what produced the six
directories: the popup already knows the path, the ownership and the answer, and
handing that back as homework is how the residue is created rather than removed.

**Keep retrying with `--force`.** What was there. It answers a refusal that is
not the one being hit, and the second error message says so.

**Call `/worktree-remove` from the popup.** It is an agent command, not a
script; a popup cannot invoke it. Reimplementing its shell half is what
`merge-state.sh` is, minus the judgement calls that stayed with the command.

**Delete the branch after the checkout.** The natural order, and it races the
workspace close that ends the popup. Detach-then-delete-then-remove has no such
window.

**Offer to force-delete an unmerged branch.** Rejected on purpose. Losing a
merged branch costs nothing; losing an unmerged one costs the work, and deciding
that needs a conversation the popup cannot have.

**Check merge state locally only.** No network, instant, and wrong for the case
it exists for: a branch merged an hour ago reads as unmerged against a base that
was last fetched yesterday, and the popup keeps a dead branch.

**Require a merged PR for the remote branch, on top of the merged verdict.**
This shipped first, and the argument for it is sound as far as it goes: "the
patch is in the base" and "nobody else needs this branch" are different claims,
and only one of them is about a repository other people share. What it missed is
that the branches it declines to delete do not stay declined and visible -- they
lose their local half to the very same popup and become unreachable. It cost
eight orphaned remote branches across seven repositories before that was
measured, which is more than it saved.

**Add `--delete-branch` to the ship popup's `gh pr merge` instead.** It would
cover the branch this machine just pushed, which is the common case, and leave
every branch merged by another route untouched — including both of the two that
were actually lingering. The removal tail sees all of them.

---

## What Is Gated

`tooling/validate/sources` asserts that `merge-state.sh` has a manifest entry —
it is sourced, not run, so a missing entry ships two popups that die at their
first line — that both popups source it, and that the dev-flow directory holds
exactly one base resolver, one `branch -D`, one `push origin --delete` and one
`sudo rm -rf`, with the guard clauses present in the script that owns them, the
merged-verdict test present beside the remote deletion, and `delete_remote`
assigned in exactly one place so no second, weaker path to that push can appear.

Nothing gates that the merge check is *right*. It is two commands against
GitHub and git, and the failure mode of both is `unknown`, which keeps the
branch.
