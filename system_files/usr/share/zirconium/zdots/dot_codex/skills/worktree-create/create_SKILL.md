---
name: worktree-create
description: Create an isolated git worktree with its own tmux window using workmux, for parallel development. Use when the user wants to start a new task or feature on a fresh branch in a separate worktree, run agents in parallel without switching branches, or invokes $worktree-create.
---

# Git Worktree

Create a git worktree using workmux. This gives the branch an isolated working
directory and its own tmux window, so parallel branches never collide.

## Workflow

### 1. Check current state

Inspect the repository before creating anything:

```bash
git worktree list --porcelain          # existing worktrees
git rev-parse --show-toplevel          # repository root
git rev-parse --abbrev-ref HEAD        # current branch
cat .workmux.yaml 2>/dev/null || echo "No project config"  # workmux project config
```

### 2. Ask the user for details

Collect a task/feature name and a branch type:

```
Task/feature name: <user input>

Branch type:
1. feat     - New feature
2. fix      - Bug fix
3. refactor - Code refactoring
4. docs     - Documentation
5. chore    - Maintenance tasks
```

**Branch naming convention:** `{feat|fix|refactor|docs|chore}-{task-name}`.

### 3. Create the worktree with workmux

```bash
# Update main first (skip if already on main)
current_branch=$(git rev-parse --abbrev-ref HEAD)
if [ "$current_branch" = "main" ]; then
  git pull origin main
else
  git fetch origin main:main
fi

# Create worktree + tmux window via workmux
workmux add {feat|fix|refactor|docs|chore}-{task-name}
```

Workmux automatically:
- Creates the git worktree in `<repo>__worktrees/<branch-name>/`.
- Creates a tmux window with the configured pane layout (agent | editor | shell).
- Copies the files configured in `.workmux.yaml` (for example `.env`, `.env.local`,
  and agent configuration).
- Symlinks `node_modules` and runs the post-create install command.
- Switches to the new window.

### 4. Confirm

```
Worktree created via workmux!

Branch: <branch-name>
Window: wm-<branch-name>

Switch between worktrees: Ctrl-s 1/2/3... or Ctrl-s n/p
Merge when done:          workmux merge <branch-name>
Remove without merging:   workmux remove <branch-name>
```

## Notes

- Workmux creates worktrees in `<repo>__worktrees/` (not as sibling directories).
- Each worktree gets its own tmux window in the current session.
- All worktrees share the same git history.
- List everything with `workmux list` or `git worktree list`.
