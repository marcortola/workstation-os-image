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

## Steps

1. If the task name above is empty, ask the user for a task/feature name. Then pick a
   branch type and build the branch name as `{feat|fix|refactor|docs|chore}-{task-name}`:
   - `feat` — new feature
   - `fix` — bug fix
   - `refactor` — code refactoring
   - `docs` — documentation
   - `chore` — maintenance

2. Fetch the remote-tracking ref rather than updating local `main`. Git refuses
   `main:main` while `main` is checked out somewhere, which it always is when
   this runs from a worktree:
   ```bash
   git fetch origin +refs/heads/main:refs/remotes/origin/main
   ```

3. Create the worktree and its workspace:
   ```bash
   main_repo=$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")
   repo=$(basename "$main_repo")
   slug=$(printf '%s' '<branch-name>' | tr '/' '-')
   created=$(herdr worktree create --cwd "$main_repo" \
       --branch <branch-name> --base origin/main \
       --path "${main_repo}__worktrees/${slug}" \
       --label "$repo/<branch-name>" --focus)
   pane=$(printf '%s\n' "$created" | jq -r '.result.root_pane.pane_id')
   herdr agent start <branch-name> --kind opencode --pane "$pane"
   ```
   herdr opens the checkout as its own workspace grouped under the parent
   repository and focuses it, and — because it shells out to `git worktree add`
   — fires the repo's `post-checkout` hook, so `workstation-worktree-sync`
   copies the untracked files listed in `.worktreeinclude` (`.env`, `.idea`,
   `.claude/settings.local.json`, ...).
   `--path` is not optional: herdr's own default is `~/.herdr/worktrees/<repo>/`,
   while the `prefix+shift+w` popup creates checkouts beside the repository at
   `<repo>__worktrees/<branch-slug>`. Passing it keeps every checkout on the
   machine in one place.
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
   Path:      <repo>__worktrees/<branch-slug>
   Workspace: focused, grouped under <repo>, opencode running in its pane

   Switch workspaces: prefix+w        Switch tabs: prefix+1..9 or prefix+n/p
   Ship it when done: worktree-push recipe
   Discard it:        worktree-remove recipe
   ```

## Notes

- Checkouts live beside the repository at `<repo>__worktrees/<branch-slug>`, the
  same place the `prefix+shift+w` popup puts them.
- Each worktree is its own herdr workspace, grouped under the parent repository.
- All worktrees share the same git history.
- List everything with `herdr worktree list` or `git worktree list`.
