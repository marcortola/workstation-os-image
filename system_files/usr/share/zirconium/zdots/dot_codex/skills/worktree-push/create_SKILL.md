---
name: worktree-push
description: Ship a worktree's branch to main by committing, syncing main, opening a PR, merging, and handing off cleanup. Use when the user is inside a workmux worktree and wants to finish and merge the work, or invokes $worktree-push.
---

# Ship Worktree

Ship code from a worktree to main: commit, sync, open a PR, merge, and clean up.

## Workflow

### 1. Validate the environment

```bash
git rev-parse --git-common-dir
```

- If it prints `.git` → you are in the main repo → this skill does not apply.
- If it prints an absolute path → you are in a worktree → proceed.

### 2. Save context

```bash
echo "BRANCH=$(git rev-parse --abbrev-ref HEAD)"
echo "WORKTREE_PATH=$(pwd)"
echo "MAIN_PATH=$(git worktree list --porcelain | head -2 | tail -1 | awk '{print $2}')"
```

### 3. Show a summary and confirm

```
SHIP CODE

Worktree: <worktree_path>
Branch:   <branch> -> main

Steps:
1. Commit outstanding work
2. Sync main into the branch
3. Open a PR
4. Merge the PR
5. Done — close the window manually

Proceed?
```

### 4. Execute

**Step 1 — Commit.** If there are staged or unstaged changes, commit them with a
clear message. If the tree is clean and there are no new commits, skip.

**Step 2 — Sync main.** Worktrees can outlive `main` by days; sync before the PR so
the merge is clean:

```bash
git fetch origin main:main
git merge main
```

- If already up to date, continue.
- If the merge resolves cleanly, commit it (`git commit --no-edit`) and continue.
- If there are conflicts you cannot resolve confidently, **STOP** and let the user
  inspect before resuming.

**Step 3 — Open a PR.**

```bash
git push -u origin "$BRANCH"
gh pr create --fill --base main
```

If a PR already exists, skip. Note the PR number.

**Step 4 — Merge the PR.**

```bash
gh pr merge <PR_NUMBER> --squash --delete-branch
```

After this command the shell's working directory may be removed. **Do not run any
more shell commands** from the worktree — they will fail with "path does not exist".

### 5. Final message

Show this immediately after the merge, without any further shell commands:

```
SHIPPED SUCCESSFULLY

Code merged to main via PR #<N>.

This window stays alive — review or keep talking here.

When you are truly done:
  1. Switch to the main window (Ctrl-s + number).
  2. From there run: workmux remove <branch>

That removes the worktree, the local branch, and this tmux window.
```

## Error handling

- Stop immediately if the commit, sync, PR, or merge step fails, and report which
  step failed and how to resume.
- After a successful merge, never run more shell commands from the worktree (its
  working directory is gone).
