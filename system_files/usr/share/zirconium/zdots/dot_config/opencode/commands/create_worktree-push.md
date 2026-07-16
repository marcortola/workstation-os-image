---
description: Ship a worktree to main - commit, sync, PR, merge, cleanup via workmux
agent: build
---

Ship code from the current worktree to main: commit, sync, open a PR, merge, and
clean up.

## Current state

- Git common dir (`.git` = main repo, absolute path = worktree):
!`git rev-parse --git-common-dir`
- Branch: !`git rev-parse --abbrev-ref HEAD`
- Worktree path: !`pwd`
- Uncommitted changes:
!`git status --porcelain`

## Steps

1. **Validate.** If the git common dir above is `.git`, you are in the main repo and
   this command does not apply — stop and say so. Otherwise proceed.

2. **Commit.** If there are staged or unstaged changes, commit them with a clear
   message. If the tree is clean and there are no new commits, skip.

3. **Sync main.** Worktrees can outlive `main` by days; sync before the PR so the
   merge is clean:
   ```bash
   git fetch origin main:main
   git merge main
   ```
   If already up to date, continue. If it merges cleanly, commit it
   (`git commit --no-edit`). If there are conflicts you cannot resolve confidently,
   STOP and let the user inspect before resuming.

4. **Open a PR:**
   ```bash
   git push -u origin "$(git rev-parse --abbrev-ref HEAD)"
   gh pr create --fill --base main
   ```
   If a PR already exists, skip. Note the PR number.

5. **Merge the PR:**
   ```bash
   gh pr merge <PR_NUMBER> --squash --delete-branch
   ```
   After this, the shell's working directory may be removed — do not run any more
   shell commands from the worktree.

6. **Report** and stop:
   ```
   SHIPPED SUCCESSFULLY

   Code merged to main via PR #<N>.

   This session stays alive — review or keep working here.
   When you are done, remove the worktree from the main checkout:
     - tmux / workmux: switch to the main window (Ctrl-s + number), then
         `workmux remove <branch>`
     - JetBrains / no-tmux: close the project, then `workmux remove <branch>`
         (or `git worktree remove <path> && git branch -D <branch>`)
   ```

## Error handling

- Stop immediately if commit, sync, PR, or merge fails, and report which step failed.
- After a successful merge, never run more shell commands from the worktree (its
  working directory is gone).
