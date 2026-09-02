---
description: Remove a git worktree via herdr
---

# Remove Git Worktree

Remove a git worktree, its herdr workspace, and its local branch, then clean up.

## Workflow

### 1. List Worktrees and Detect Target

```bash
main=$(git worktree list --porcelain | awk '/^worktree /{print $2; exit}')
herdr worktree list --cwd "$main"
git worktree list --porcelain
```

If no argument provided, ask user which worktree to remove.

**BLOCK** if target is the main worktree: "Cannot remove the main worktree."

The checkout lives beside the repository at `<repo>__worktrees/<branch-slug>`,
where the slug is the branch name with `/` replaced by `-`.

### 2. Check Merge Status (Squash-Merge Aware)

`git cherry` is how merge state is determined: it lists `+` for commits not in
base and `-` for patch-equivalents, so squash and rebase merges read as merged.
Establish the real state before warning the user:

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

- `unmerged=0` AND `dirty=0` → **safe removal**
- anything else — including a `risky` value from a check that could not
  complete (missing base branch, bad path) → **real risk of data loss**; never
  auto-`--force`, get explicit user confirmation

### 3. Show Info and Confirm

Tailor the confirmation to the actual state:

**Safe case (merged, clean):**
```
Worktree: <branch-name>
Status: merged into main, no uncommitted changes

This will remove the herdr workspace, worktree directory, and local branch.
Proceed? (yes/no)
```

**Risky case (unmerged or dirty):**
```
Worktree: <branch-name>
WARNING:
  - <N> unmerged commits (not in main)
  - <M> uncommitted changes

This will DELETE the herdr workspace, worktree, and local branch.
Work will be LOST. This action CANNOT be undone.
Proceed? (yes/no)
```

**CRITICAL:** Wait for explicit "yes" confirmation.

### 4. Remove the Worktree

Look up the herdr workspace holding the branch, then remove it:

```bash
ws=$(herdr worktree list --cwd "$main" | jq -r --arg b "$branch" \
    '.result.worktrees[] | select(.branch==$b) | .open_workspace_id // empty')
```

- **`$ws` non-empty:**

  ```bash
  herdr worktree remove --workspace "$ws"
  ```

- **`$ws` empty** — the jq filter reads `.open_workspace_id`, so this is any
  checkout whose workspace is not currently open. Fall back to git directly.

  ```bash
  git worktree remove "$worktree_path"
  ```

Both paths run `git worktree remove` underneath, so both refuse on a dirty
checkout. A refusal means the worktree has **uncommitted changes** — do not
reflexively add `--force`, which discards them. Re-run the step-2 merge/dirty
check and get explicit user confirmation before escalating to
`herdr worktree remove --workspace "$ws" --force` or
`git worktree remove --force "$worktree_path"`. Pass `--force` **only** in the
risky case the user has explicitly approved.


### 5. Delete the Local Branch

herdr never deletes a branch, so this step is mandatory — skip it and the
machine silently accumulates dead local branches. Run it from the main checkout,
after the worktree is gone:

```bash
git branch -D "$branch"
```

`-D` rather than `-d`: a squash-merged branch is not an ancestor of the base, so
`-d` would refuse it. Step 2 already established whether the work is safe to
discard.

### 6. Clean Up nvim Session

```bash
session_file=$(echo "$worktree_path" | sed 's|/|%|g').vim
session_path="$HOME/.local/state/nvim/sessions/$session_file"
[ -f "$session_path" ] && rm "$session_path"
```

### 7. Verify

```bash
git worktree list --porcelain
```

Report: worktree removed, branch deleted, remaining count.

## CRITICAL: When Removing Current Working Directory

If executing from inside the worktree being removed:

1. Print success immediately after removal.
2. **DO NOT execute any more bash commands** — cwd is gone.
3. Tell the user to close this Claude session.
