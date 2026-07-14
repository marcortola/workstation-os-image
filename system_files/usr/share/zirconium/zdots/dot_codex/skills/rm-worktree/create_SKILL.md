---
name: rm-worktree
description: Remove a git worktree, its tmux window, and its local branch via workmux, with squash-merge-aware safety checks. Use when the user wants to delete or clean up a workmux worktree, or invokes $rm-worktree.
---

# Remove Git Worktree

Remove a git worktree, its tmux window, and its local branch, then clean up.

## Workflow

### 1. List worktrees and detect the target

```bash
workmux list
git worktree list --porcelain
```

If no target was given, ask the user which worktree to remove.

**BLOCK** if the target is the main worktree: "Cannot remove the main worktree."

### 2. Check merge status (squash-merge aware)

`workmux list` flags `●` for *any* branch whose tip is not an ancestor of main, so
it gives false positives on squash and rebase merges. Verify the real state before
warning the user:

```bash
branch="<branch-name>"
worktree_path="<absolute-path>"

# 2a. Unmerged commits? `git cherry` returns "+" for commits not in main
#     (it detects patch-equivalents, so squash merges show as "-").
unmerged=$(git cherry main "$branch" | grep -c '^+' || true)

# 2b. Uncommitted changes in the worktree?
dirty=$(git -C "$worktree_path" status --porcelain | wc -l | tr -d ' ')
```

- `unmerged=0` AND `dirty=0` → **safe removal** (even if workmux shows `●`).
- otherwise → **real risk of data loss**.

### 3. Show info and confirm

Tailor the confirmation to the actual state.

**Safe case (merged, clean):**
```
Worktree: <branch-name>
Status:   merged into main, no uncommitted changes

This will remove the tmux window, worktree directory, and local branch.
Proceed? (yes/no)
```

**Risky case (unmerged or dirty):**
```
Worktree: <branch-name>
WARNING:
  - <N> unmerged commits (not in main)
  - <M> uncommitted changes

This will DELETE the tmux window, worktree, and local branch.
Work will be LOST. This action CANNOT be undone.
Proceed? (yes/no)
```

**CRITICAL:** wait for an explicit "yes" before continuing.

### 4. Remove via workmux

Once the user confirms, pipe `yes` so workmux's own prompt for unmerged branches
does not re-ask:

```bash
yes | workmux remove "$branch"
```

**If workmux fails** (for a manually created worktree):

```bash
git worktree remove "$worktree_path"
# If needed:
git worktree remove --force "$worktree_path"
git branch -D "$branch"
```

### 5. Clean up the nvim session

```bash
session_file=$(echo "$worktree_path" | sed 's|/|%|g').vim
session_path="$HOME/.local/state/nvim/sessions/$session_file"
[ -f "$session_path" ] && rm "$session_path"
```

### 6. Verify

```bash
git worktree list --porcelain
```

Report that the worktree was removed and how many remain.

## When removing the current working directory

If you are running from inside the worktree being removed:

1. Print success immediately after removal.
2. **Do not run any more shell commands** — the working directory is gone.
3. Tell the user to close this session.
