---
description: Remove a git worktree, its tmux window, and branch via workmux
agent: build
---

Remove a git worktree, its tmux window, and its local branch, then clean up.

Target branch (optional): **$ARGUMENTS**

## Current state

- Workmux worktrees:
!`workmux list 2>/dev/null || echo "workmux not available"`
- Git worktrees:
!`git worktree list --porcelain`

## Steps

1. **Detect the target.** Use the branch above if given; otherwise ask the user which
   worktree to remove. BLOCK if the target is the main worktree: "Cannot remove the
   main worktree."

2. **Check merge status (squash-merge aware).** `workmux list` flags `●` for any
   branch whose tip is not an ancestor of main, so it gives false positives on squash
   and rebase merges. Verify the real state:
   ```bash
   branch="<branch-name>"
   worktree_path="<absolute-path>"

   # git cherry returns "+" for commits not in main (patch-equivalents show as "-").
   unmerged=$(git cherry main "$branch" | grep -c '^+' || true)
   dirty=$(git -C "$worktree_path" status --porcelain | wc -l | tr -d ' ')
   ```
   - `unmerged=0` AND `dirty=0` → safe removal (even if workmux shows `●`).
   - otherwise → real risk of data loss.

3. **Confirm**, tailoring the message to the actual state (safe vs. unmerged/dirty),
   and wait for an explicit "yes". For the risky case, state clearly that unmerged
   commits and uncommitted changes will be LOST and the action cannot be undone.

4. **Remove via workmux.** Pipe `yes` so workmux's own prompt for unmerged branches
   does not re-ask:
   ```bash
   yes | workmux remove "$branch"
   ```
   If workmux fails (a manually created worktree), fall back to:
   ```bash
   git worktree remove "$worktree_path"    # add --force if needed
   git branch -D "$branch"
   ```

5. **Clean up the nvim session:**
   ```bash
   session_file=$(echo "$worktree_path" | sed 's|/|%|g').vim
   session_path="$HOME/.local/state/nvim/sessions/$session_file"
   [ -f "$session_path" ] && rm "$session_path"
   ```

6. **Verify** with `git worktree list --porcelain` and report the remaining count.

## JetBrains / no-tmux

If you created the worktree from a JetBrains IDE (no tmux window ever existed),
`workmux remove` still removes the worktree and its branch cleanly — it just skips
the absent tmux window. Or use the `git worktree remove` fallback in step 4 (then
`git branch -D "$branch"`). Close the worktree's project in the IDE first so it is
not left pointing at a deleted directory; the nvim-session cleanup in step 5 is a
harmless no-op for you.

## When removing the current working directory

If you are running from inside the worktree being removed, print success immediately
after removal, do not run any more shell commands (the working directory is gone), and
tell the user to close this session.
