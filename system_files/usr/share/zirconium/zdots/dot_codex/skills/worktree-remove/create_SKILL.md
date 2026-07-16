---
name: worktree-remove
description: Remove a git worktree, its tmux window, and its local branch via workmux, with squash-merge-aware safety checks. Use when the user wants to delete or clean up a workmux worktree, or invokes $worktree-remove.
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

# Resolve the real default branch — never hardcode "main".
base=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||')
if [ -z "$base" ]; then
  for c in main master trunk; do
    git rev-parse --verify --quiet "$c" >/dev/null && base=$c && break
  done
fi

# Fail CLOSED: if a check cannot run cleanly, mark it "risky" — never let an
# errored command report 0 and greenlight a force-delete.
# 2a. Unmerged commits? `git cherry` lists "+" for commits not in base
#     (patch-equivalents show as "-", so squash merges read as merged).
if [ -z "$base" ] || ! git rev-parse --verify --quiet "$base" >/dev/null; then
  unmerged=risky
elif ! cherry=$(git cherry "$base" "$branch" 2>/dev/null); then
  unmerged=risky
else
  unmerged=$(printf '%s\n' "$cherry" | grep -c '^+')
fi

# 2b. Uncommitted changes in the worktree?
if ! status=$(git -C "$worktree_path" status --porcelain 2>/dev/null); then
  dirty=risky
else
  dirty=$(printf '%s' "$status" | grep -c .)
fi
```

- `unmerged=0` AND `dirty=0` → **safe removal** (even if workmux shows `●`).
- anything else — including a `risky` value from a check that could not
  complete (missing base branch, bad path) → **real risk of data loss**; never
  auto-`--force`, get explicit user confirmation.

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

- **Confirmed-safe case** (`unmerged=0` and `dirty=0`): pipe `yes` so workmux's
  own prompt for unmerged branches does not re-ask:

  ```bash
  yes | workmux remove "$branch"
  ```

- **Risky or unverified case** (any `risky` / non-zero value): run it interactively
  so workmux's own unmerged-branch guard still fires as a last-line defense:

  ```bash
  workmux remove "$branch"
  ```

**If workmux fails** (for a manually created worktree):

```bash
git worktree remove "$worktree_path"   # refuses if the worktree is dirty
git branch -D "$branch"                # force-deletes the (already-merged) branch
```
A `git worktree remove` refusal means the worktree has **uncommitted changes** — do
not reflexively add `--force`, which discards them. Re-run the step-2 merge/dirty
check and get explicit user confirmation before escalating to
`git worktree remove --force`.

### 4b. JetBrains / no-tmux

If you created the worktree from a JetBrains IDE (no tmux window ever existed),
`workmux remove` still removes the worktree and its branch cleanly — it just skips
the absent tmux window. Or use the `git worktree remove` fallback above (then
`git branch -D "$branch"`). Close the worktree's project in the IDE first so it is
not left pointing at a deleted directory; the nvim-session cleanup in step 5 is a
harmless no-op for you.

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
