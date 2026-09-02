---
description: Create git worktree for parallel development (via herdr)
---

# Git Worktree

Create a git worktree using herdr. This gives the branch an isolated working
directory and its own herdr workspace, so parallel branches never collide.

## Workflow

### 1. Check Current State

Run in parallel:
- `git worktree list --porcelain` - Existing worktrees
- `git rev-parse --show-toplevel` - Repository root
- `git rev-parse --abbrev-ref HEAD` - Current branch

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

### 3. Create Worktree with herdr

Fetch the remote-tracking ref rather than updating local `main`. Git refuses
`main:main` while `main` is checked out somewhere, which it always is when this
runs from a worktree:

```bash
git fetch origin +refs/heads/main:refs/remotes/origin/main
```

```bash
main_repo=$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")
repo=$(basename "$main_repo")
slug=$(printf '%s' '{branch-name}' | tr '/' '-')
created=$(herdr worktree create --cwd "$main_repo" \
    --branch {branch-name} --base origin/main \
    --path "${main_repo}__worktrees/${slug}" \
    --label "$repo/{branch-name}" --focus)
pane=$(printf '%s\n' "$created" | jq -r '.result.root_pane.pane_id')
herdr agent start {branch-name} --kind claude --pane "$pane"
```

herdr automatically:
- Opens the checkout as its own workspace, grouped under the parent repository,
  and focuses it
- Shells out to `git worktree add`, so the repo's `post-checkout` hook fires and
  `workstation-worktree-sync` copies the untracked files listed in
  `.worktreeinclude` (`.env`, `.idea`, `.claude/settings.local.json`, ...) —
  tracked files are already present

`--path` is not optional. herdr's own default is `~/.herdr/worktrees/<repo>/`,
while the `prefix+shift+w` popup creates checkouts beside the repository at
`<repo>__worktrees/<branch-slug>`. Passing it keeps every checkout on the
machine in one place.

`--label` is not cosmetic: herdr labels a worktree workspace with the branch
alone, and the Agent sidebar's only location token is that workspace name, so
without it every worktree row loses the repository it belongs to.

`herdr agent start` needs an existing pane sitting at a shell prompt; the new
workspace's single default pane is exactly that. Do not split it.

(Dependencies like `node_modules`/`vendor` are not copied — install them in the
new worktree if the branch needs them.)

### 4. Post-Creation: Task Handling

After the worktree exists, handle task migration if needed. The checkout path is
already in the response (`jq -r '.result.worktree.path' <<< "$created"`).

**Case A: Active task exists in main repo**
If there's an active task in `.claude/tasks/` related to the current conversation:
```bash
# shared .claude is in the checkout; check if the task exists
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
Worktree created via herdr!

Branch:    <branch-name>
Path:      <repo>__worktrees/<branch-slug>
Workspace: focused, grouped under <repo>, Claude running in its pane

Switch workspaces: prefix+w        Switch tabs: prefix+1..9 or prefix+n/p
Ship it when done: worktree-push recipe
Discard it:        worktree-remove recipe
```

## Important Notes

- Checkouts live beside the repository at `<repo>__worktrees/<branch-slug>`, the
  same place the `prefix+shift+w` popup puts them
- Each worktree is its own herdr workspace, grouped under the parent repository
- All worktrees share the same git history
- List all: `herdr worktree list` or `git worktree list`
