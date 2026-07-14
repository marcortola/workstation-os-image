---
description: Create git worktree for parallel development (via workmux)
---

# Git Worktree

Create a git worktree using workmux. This creates an isolated branch with its own tmux window.

## Workflow

### 1. Check Current State

Run in parallel:
- `git worktree list --porcelain` - Existing worktrees
- `git rev-parse --show-toplevel` - Repository root
- `git rev-parse --abbrev-ref HEAD` - Current branch
- `cat .workmux.yaml 2>/dev/null || echo "No project config"` - Workmux project config

### 2. Ask User for Details

```
Task/feature name: <user input>

Branch type:
1. feat - New feature
2. fix - Bug fix
3. refactor - Code refactoring
4. docs - Documentation
5. chore - Maintenance tasks

Branch type: <user selects>
```

**Branch naming convention:** `{feat|fix|refactor|docs|chore}-{task-name}`

### 3. Create Worktree with Workmux

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
- Creates git worktree in `<repo>__worktrees/<branch-name>/`
- Creates tmux window with configured pane layout (claude | nvim | terminal)
- Copies `.env`, `.env.local`, `.claude` directory
- Symlinks `node_modules`
- Runs `npm install`
- Switches to the new window

### 4. Post-Creation: Task Handling

After workmux finishes, handle task migration if needed:

**Case A: Active task exists in main repo**
If there's an active task in `.claude/tasks/` related to the current conversation:
```bash
# .claude was already copied by workmux, check if task exists
worktree_path=$(git worktree list --porcelain | grep "worktree.*{branch-name}" | awk '{print $2}')
ls "$worktree_path/.claude/tasks/" 2>/dev/null
```

**Case B: User requests task creation**
Create task directly in the worktree:
```bash
worktree_path=$(git worktree list --porcelain | grep "worktree.*{branch-name}" | awk '{print $2}')
mkdir -p "$worktree_path/.claude/tasks/<task-name>/research"
# Then create task-plan.md in the worktree
```

### 5. Confirm

```
Worktree created via workmux!

Branch: <branch-name>
Window: wm-<branch-name>

Switch between worktrees: Ctrl-s 1/2/3... or Ctrl-s n/p
Merge when done: wm merge <branch-name>
Remove without merge: wm remove <branch-name>
```

## Important Notes

- Workmux creates worktrees in `<repo>__worktrees/` (not as sibling directories)
- Each worktree gets its own tmux window in the current session
- All worktrees share the same git history
- List all: `wm list` or `git worktree list`
