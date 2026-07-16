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
- Copies the untracked files listed in the repo's `.worktreeinclude` (`.env`,
  `.idea`, ...) via its `post_create` hook; tracked files are already present.
- Switches to the new window.

Dependencies (`node_modules`, `vendor`) are not copied — add an install step or a
symlink in the repo's `.workmux.yaml` if the branch needs them.

### 3b. JetBrains / no-tmux flow

If you're working in a JetBrains IDE (no tmux, no nvim), skip `workmux add` — it
opens a tmux window you won't use. Either create the worktree from the IDE's
**New Worktree** UI (the git `post-checkout` hook copies the `.worktreeinclude`
files automatically), or create it here without tmux and open it in the IDE:

```bash
git fetch origin main:main 2>/dev/null || true
dir="$(git rev-parse --show-toplevel)__worktrees/{branch-name}"
git worktree add "$dir" -b {branch-name} main
( cd "$dir" && workstation-worktree-sync )   # copy .env, .idea, ... from main
```

Open `$dir` with the IDE launcher (`webstorm`/`phpstorm`/`idea "$dir"`), or if you
created it in the IDE, run Tools → External Tools → **Sync worktree files**.

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
