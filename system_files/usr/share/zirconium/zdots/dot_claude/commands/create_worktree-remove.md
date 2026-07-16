---
description: Remove a git worktree via workmux
---

# Remove Git Worktree

Remove a git worktree, its tmux window, and clean up.

## Workflow

### 1. List Worktrees and Detect Target

```bash
workmux list
git worktree list --porcelain
```

If no argument provided, ask user which worktree to remove.

**BLOCK** if target is the main worktree: "Cannot remove the main worktree."

### 2. Check Merge Status (Squash-Merge Aware)

`workmux list` flags `●` for *any* branch whose tip isn't an ancestor of main, so it gives false positives on squash and rebase merges. Verify the real state before warning the user:

```bash
branch="<branch-name>"
worktree_path="<absolute-path>"

# 2a. Unmerged commits? `git cherry` returns "+" for commits not in main
#     (including patch-equivalent detection, so squash merges show as "-").
unmerged=$(git cherry main "$branch" | grep -c '^+' || true)

# 2b. Uncommitted changes in the worktree?
dirty=$(git -C "$worktree_path" status --porcelain | wc -l | tr -d ' ')
```

- `unmerged=0` AND `dirty=0` → **safe removal** (even if workmux shows `●`)
- otherwise → **real risk of data loss**

### 3. Show Info and Confirm

Tailor the confirmation to the actual state:

**Safe case (merged, clean):**
```
Worktree: <branch-name>
Status: merged into main, no uncommitted changes

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

**CRITICAL:** Wait for explicit "yes" confirmation.

### 4. Remove via Workmux

Once the user has confirmed, pipe `yes` so workmux's own interactive prompt for unmerged branches doesn't re-ask:

```bash
yes | workmux remove "$branch"
```

**If workmux fails** (worktree was created manually):
```bash
git worktree remove "$worktree_path"
# If needed:
git worktree remove --force "$worktree_path"
git branch -D "$branch"
```

### 5. Clean Up nvim Session

```bash
session_file=$(echo "$worktree_path" | sed 's|/|%|g').vim
session_path="$HOME/.local/state/nvim/sessions/$session_file"
[ -f "$session_path" ] && rm "$session_path"
```

### 6. Verify

```bash
git worktree list --porcelain
```

Report: worktree removed, remaining count.

## CRITICAL: When Removing Current Working Directory

If executing from inside the worktree being removed:

1. Print success immediately after removal.
2. **DO NOT execute any more bash commands** — cwd is gone.
3. Tell the user to close this Claude session.
