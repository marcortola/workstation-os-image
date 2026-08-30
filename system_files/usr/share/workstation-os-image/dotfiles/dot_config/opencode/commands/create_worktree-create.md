---
description: Create a git worktree with its own herdr workspace
agent: build
---

Create a new git worktree using herdr. This gives the branch an isolated working
directory and its own herdr workspace, so parallel branches never collide.

Task/feature name: **$ARGUMENTS**

## Current state

- Existing worktrees:
!`git worktree list --porcelain`
- Repository root: !`git rev-parse --show-toplevel`
- Current branch: !`git rev-parse --abbrev-ref HEAD`
- herdr session:
!`printenv HERDR_ENV || echo "no herdr session"`

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

3. Create the worktree and its workspace. Choose this path or the no-herdr flow
   below with a runtime check, not a judgement call: take this one when
   `HERDR_ENV` is set to `1`, and the one below when it is unset.
   ```bash
   repo=$(basename "$(git rev-parse --show-toplevel)")
   created=$(herdr worktree create --cwd "$(git rev-parse --show-toplevel)" \
       --branch {branch-name} --base origin/main \
       --label "$repo/{branch-name}" --focus)
   pane=$(printf '%s\n' "$created" | jq -r '.result.root_pane.pane_id')
   herdr agent start {branch-name} --kind opencode --pane "$pane"
   ```
   herdr creates the checkout at `~/.herdr/worktrees/<repo>/<branch-slug>` (the
   slug is the branch name with `/` replaced by `-`), opens it as its own
   workspace grouped under the parent repository and focuses it, and — because
   it shells out to `git worktree add` — fires the repo's `post-checkout` hook,
   so `workstation-worktree-sync` copies the untracked files listed in
   `.worktreeinclude` (`.env`, `.idea`, `.claude/settings.local.json`, ...).
   `--label` is not cosmetic: herdr labels a worktree workspace with the
   branch alone, and the Agent sidebar's only location token is that workspace
   name, so without it every worktree row loses the repository it belongs to.
   `herdr agent start` needs an existing pane at a shell prompt; the workspace's
   single default pane is exactly that, so do not split it. (Dependencies like
   `node_modules`/`vendor` are not copied — install them in the new worktree if
   the branch needs them.)

4. Confirm:
   ```
   Worktree created via herdr!

   Branch:    <branch-name>
   Path:      ~/.herdr/worktrees/<repo>/<branch-slug>
   Workspace: focused, grouped under <repo>, opencode running in its pane

   Switch workspaces: ctrl+b w        Switch tabs: ctrl+b 1..9 or ctrl+b n/p
   Ship it when done: worktree-push recipe
   Discard it:        worktree-remove recipe
   ```

## JetBrains / no-herdr flow

When `HERDR_ENV` is unset — a JetBrains IDE, a plain terminal, a script — there
is no server to open a workspace in. Either create the worktree from the IDE's
**New Worktree** UI (the git `post-checkout` hook copies the `.worktreeinclude`
files automatically), or create it here:

```bash
git fetch origin +refs/heads/main:refs/remotes/origin/main
dir="$HOME/.herdr/worktrees/$(basename "$(git rev-parse --show-toplevel)")/<branch-name>"
git worktree add "$dir" -b <branch-name> origin/main
( cd "$dir" && workstation-worktree-sync )   # copy .env, .idea, ... from main
```

The explicit `workstation-worktree-sync` call is belt-and-braces for repos whose
`post-checkout` hook is not installed yet.

Then open `$dir` with the IDE launcher (`webstorm`/`phpstorm`/`idea "$dir"`), or run
Tools → External Tools → **Sync worktree files** if you created it in the IDE.
Report the path instead of a workspace:

```
Worktree created at ~/.herdr/worktrees/<repo>/<branch-name> (open it in the IDE)

Branch: <branch-name>
Ship it when done: worktree-push recipe
Discard it:        worktree-remove recipe
```

## Notes

- herdr creates worktrees under `~/.herdr/worktrees/<repo>/` (not as sibling
  directories of the repository).
- Each worktree is its own herdr workspace, grouped under the parent repository.
- All worktrees share the same git history.
- List everything with `herdr worktree list` or `git worktree list`.
