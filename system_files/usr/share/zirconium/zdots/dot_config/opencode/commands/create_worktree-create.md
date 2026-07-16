---
description: Create a git worktree with its own tmux window via workmux
agent: build
---

Create a new git worktree using workmux. This gives the branch an isolated working
directory and its own tmux window, so parallel branches never collide.

Task/feature name: **$ARGUMENTS**

## Current state

- Existing worktrees:
!`git worktree list --porcelain`
- Repository root: !`git rev-parse --show-toplevel`
- Current branch: !`git rev-parse --abbrev-ref HEAD`
- Workmux project config:
!`cat .workmux.yaml 2>/dev/null || echo "No project config"`

## Steps

1. If the task name above is empty, ask the user for a task/feature name. Then pick a
   branch type and build the branch name as `{feat|fix|refactor|docs|chore}-{task-name}`:
   - `feat` — new feature
   - `fix` — bug fix
   - `refactor` — code refactoring
   - `docs` — documentation
   - `chore` — maintenance

2. Update main first (skip if already on `main`):
   ```bash
   current_branch=$(git rev-parse --abbrev-ref HEAD)
   if [ "$current_branch" = "main" ]; then
     git pull origin main
   else
     git fetch origin main:main
   fi
   ```

3. Create the worktree and tmux window:
   ```bash
   workmux add {feat|fix|refactor|docs|chore}-{task-name}
   ```
   Workmux creates the worktree in `<repo>__worktrees/<branch-name>/`, opens a tmux
   window with the configured pane layout, copies the untracked files listed in the
   repo's `.worktreeinclude` (`.env`, `.idea`, ...) via its `post_create` hook, and
   switches to the new window. (Dependencies like `node_modules`/`vendor` are not
   copied — add an install step or symlink in the repo's `.workmux.yaml` if needed.)

4. Confirm:
   ```
   Worktree created via workmux!

   Branch: <branch-name>
   Window: wm-<branch-name>

   Switch between worktrees: Ctrl-s 1/2/3... or Ctrl-s n/p
   Merge when done:          workmux merge <branch-name>
   Remove without merging:   workmux remove <branch-name>
   ```

## JetBrains / no-tmux flow

If you're working in a JetBrains IDE (no tmux, no nvim), skip `workmux add` — it
opens a tmux window you won't use. Either create the worktree from the IDE's **New
Worktree** UI (the git `post-checkout` hook copies the `.worktreeinclude` files
automatically), or create it here without tmux:

```bash
git fetch origin +refs/heads/main:refs/remotes/origin/main
dir="$(git rev-parse --show-toplevel)__worktrees/<branch-name>"
git worktree add "$dir" -b <branch-name> origin/main
( cd "$dir" && workstation-worktree-sync )   # copy .env, .idea, ... from main
```

Then open `$dir` with the IDE launcher (`webstorm`/`phpstorm`/`idea "$dir"`), or run
Tools → External Tools → **Sync worktree files** if you created it in the IDE.

## Notes

- Workmux creates worktrees in `<repo>__worktrees/` (not as sibling directories).
- Each worktree gets its own tmux window in the current session.
- All worktrees share the same git history.
- List everything with `workmux list` or `git worktree list`.
