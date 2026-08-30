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
- `printenv HERDR_ENV || echo "no herdr session"` - Which creation path applies

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

```bash
# Update main first (skip if already on main)
current_branch=$(git rev-parse --abbrev-ref HEAD)
if [ "$current_branch" = "main" ]; then
  git pull origin main
else
  git fetch origin main:main
fi
```

Pick the creation path with a runtime check, not a judgement call: use this
step when `HERDR_ENV` is set to `1`, and step 3b when it is unset.

```bash
repo=$(basename "$(git rev-parse --show-toplevel)")
created=$(herdr worktree create --cwd "$(git rev-parse --show-toplevel)" \
    --branch {branch-name} --base origin/main \
    --label "$repo/{branch-name}" --focus)
pane=$(printf '%s\n' "$created" | jq -r '.result.root_pane.pane_id')
herdr agent start {branch-name} --kind claude --pane "$pane"
```

herdr automatically:
- Creates the checkout in `~/.herdr/worktrees/<repo>/<branch-slug>/` (the slug
  is the branch name with `/` replaced by `-`)
- Opens it as its own workspace, grouped under the parent repository, and
  focuses it
- Shells out to `git worktree add`, so the repo's `post-checkout` hook fires and
  `workstation-worktree-sync` copies the untracked files listed in
  `.worktreeinclude` (`.env`, `.idea`, `.claude/settings.local.json`, ...) —
  tracked files are already present

`--label` is not cosmetic: herdr labels a worktree workspace with the branch
alone, and the Agent sidebar's only location token is that workspace name, so
without it every worktree row loses the repository it belongs to.

`herdr agent start` needs an existing pane sitting at a shell prompt; the new
workspace's single default pane is exactly that. Do not split it.

(Dependencies like `node_modules`/`vendor` are not copied — install them in the
new worktree if the branch needs them.)

### 3b. No herdr session (JetBrains, plain terminal, script)

When `HERDR_ENV` is unset there is no server to open a workspace in. Either
create the worktree from the IDE's **New Worktree** UI (the git `post-checkout`
hook copies the `.worktreeinclude` files automatically), or create it here and
open it in the IDE:

```bash
git fetch origin +refs/heads/main:refs/remotes/origin/main
dir="$HOME/.herdr/worktrees/$(basename "$(git rev-parse --show-toplevel)")/{branch-name}"
git worktree add "$dir" -b {branch-name} origin/main
( cd "$dir" && workstation-worktree-sync )   # copy .env, .idea, ... from main
```

The explicit `workstation-worktree-sync` call is belt-and-braces for repos whose
`post-checkout` hook is not installed yet.

Then open `$dir` in the IDE (`webstorm`/`phpstorm`/`idea "$dir"`). If you created
it from the IDE and the files did not copy, run Tools → External Tools → **Sync
worktree files**.

### 4. Post-Creation: Task Handling

After the worktree exists, handle task migration if needed. On the herdr path
the checkout path is already in the response
(`jq -r '.result.worktree.path' <<< "$created"`); otherwise derive it from git.

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

**If you used the herdr path (3):**
```
Worktree created via herdr!

Branch:    <branch-name>
Path:      ~/.herdr/worktrees/<repo>/<branch-slug>
Workspace: focused, grouped under <repo>, Claude running in its pane

Switch workspaces: ctrl+b w        Switch tabs: ctrl+b 1..9 or ctrl+b n/p
Ship it when done: worktree-push recipe
Discard it:        worktree-remove recipe
```

**If you used the no-herdr flow (3b):** there is no workspace — report the path
instead:
```
Worktree created at ~/.herdr/worktrees/<repo>/<branch-name> (open it in the IDE)

Branch: <branch-name>
Ship it when done: worktree-push recipe
Discard it:        worktree-remove recipe
```

## Important Notes

- herdr creates worktrees under `~/.herdr/worktrees/<repo>/` (not as sibling
  directories of the repository)
- Each worktree is its own herdr workspace, grouped under the parent repository
- All worktrees share the same git history
- List all: `herdr worktree list` or `git worktree list`
