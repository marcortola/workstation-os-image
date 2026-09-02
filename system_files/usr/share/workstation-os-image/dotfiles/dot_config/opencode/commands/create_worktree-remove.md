---
description: Remove a git worktree, its herdr workspace, and branch
agent: build
---

Remove a git worktree, its herdr workspace, and its local branch, then clean up.

Target branch (optional): **$ARGUMENTS**

## Current state

- herdr worktrees:
!`herdr worktree list 2>/dev/null || echo "no herdr worktrees for this directory"`
- Git worktrees:
!`git worktree list --porcelain`

## Steps

1. **Detect the target.** Use the branch above if given; otherwise ask the user which
   worktree to remove. BLOCK if the target is the main worktree: "Cannot remove the
   main worktree." The checkout lives beside the repository at
   `<repo>__worktrees/<branch-slug>`, where the slug is the branch name with `/`
   replaced by `-`.

2. **Check merge status (squash-merge aware).** `git cherry` is how merge state is
   determined: it lists `+` for commits not in base and `-` for patch-equivalents, so
   squash and rebase merges read as merged. Establish the real state:
   ```bash
   main=$(git worktree list --porcelain | awk '/^worktree /{print $2; exit}')
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
   - `unmerged=0` AND `dirty=0` → safe removal.
   - anything else (including a `risky` value from a check that could not
     complete) → real risk of data loss; never auto-`--force`.

3. **Confirm**, tailoring the message to the actual state (safe vs. unmerged/dirty),
   and wait for an explicit "yes". For the risky case, state clearly that unmerged
   commits and uncommitted changes will be LOST and the action cannot be undone.

4. **Remove the worktree.** Look up the herdr workspace holding the branch:
   ```bash
   ws=$(herdr worktree list --cwd "$main" | jq -r --arg b "$branch" \
       '.result.worktrees[] | select(.branch==$b) | .open_workspace_id // empty')
   ```
   If `$ws` is non-empty, run `herdr worktree remove --workspace "$ws"`. If `$ws` is
   empty — the jq filter reads `.open_workspace_id`, so this is any checkout whose
   workspace is not currently open — fall back to
   `git worktree remove "$worktree_path"`. Both paths run `git worktree remove`
   underneath, so both refuse on a dirty checkout. A refusal means uncommitted changes
   exist — do not add `--force` (it discards them) without re-checking merge/dirty
   state and explicit user confirmation. Pass `--force` only in the risky case the
   user has explicitly approved.

5. **Delete the local branch.** herdr never deletes a branch, so this is mandatory —
   skip it and the machine silently accumulates dead local branches. From the main
   checkout, once the worktree is gone:
   ```bash
   git branch -D "$branch"
   ```
   `-D` rather than `-d`: a squash-merged branch is not an ancestor of the base, so
   `-d` would refuse it. Step 2 already established whether the work is safe to
   discard.

6. **Clean up the nvim session:**
   ```bash
   session_file=$(echo "$worktree_path" | sed 's|/|%|g').vim
   session_path="$HOME/.local/state/nvim/sessions/$session_file"
   [ -f "$session_path" ] && rm "$session_path"
   ```

7. **Verify** with `git worktree list --porcelain` and report the remaining count.


## When removing the current working directory

If you are running from inside the worktree being removed, print success immediately
after removal, do not run any more shell commands (the working directory is gone), and
tell the user to close this session.
