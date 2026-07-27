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

   # Resolve the real default branch — never hardcode "main".
   base=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||')
   if [ -z "$base" ]; then
     for c in main master trunk; do
       git rev-parse --verify --quiet "$c" >/dev/null && base=$c && break
     done
   fi

   # Fail CLOSED: a check that cannot run cleanly is "risky", not 0.
   if [ -z "$base" ] || ! git rev-parse --verify --quiet "$base" >/dev/null; then
     unmerged=risky
   elif ! cherry=$(git cherry "$base" "$branch" 2>/dev/null); then
     unmerged=risky
   else
     unmerged=$(printf '%s\n' "$cherry" | grep -c '^+')
   fi
   if ! status=$(git -C "$worktree_path" status --porcelain 2>/dev/null); then
     dirty=risky
   else
     dirty=$(printf '%s' "$status" | grep -c .)
   fi
   ```
   - `unmerged=0` AND `dirty=0` → safe removal (even if workmux shows `●`).
   - anything else (including a `risky` value from a check that could not
     complete) → real risk of data loss; never auto-`--force`.

3. **Confirm**, tailoring the message to the actual state (safe vs. unmerged/dirty),
   and wait for an explicit "yes". For the risky case, state clearly that unmerged
   commits and uncommitted changes will be LOST and the action cannot be undone.

4. **Remove via workmux.** In the confirmed-safe case (`unmerged=0` and `dirty=0`),
   pipe `yes` so workmux's own prompt for unmerged branches does not re-ask:
   ```bash
   yes | workmux remove "$branch"
   ```
   In any risky or unverified case, run it interactively (`workmux remove "$branch"`)
   so workmux's own unmerged-branch guard still fires.
   If workmux fails (a manually created worktree), fall back to:
   ```bash
   git worktree remove "$worktree_path"    # refuses if the worktree is dirty
   git branch -D "$branch"                 # force-deletes the (already-merged) branch
   ```
   A refusal means uncommitted changes exist — do not add `--force` (it discards
   them) without re-checking merge/dirty state and explicit user confirmation.

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
