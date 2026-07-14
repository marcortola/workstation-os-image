---
description: Ship code from worktree to main - commit, PR, merge, cleanup via workmux
allowed-tools: Bash(git:*), Bash(gh:*), Bash(tmux:*), Bash(workmux:*), Bash(rm:*), Bash(mv:*), Bash(ls:*), Bash(cd:*), Bash(echo:*), Bash(pwd:*), TodoWrite, Read, Glob, Grep, Edit, Write
---

# Ship Worktree

Ship code from a worktree to main: commit, PR, merge, and clean up.

## Workflow

### 1. Validate Environment

```bash
git rev-parse --git-common-dir
```

- If `.git` → main repo → this command doesn't apply
- If absolute path → worktree → proceed

### 2. Save Context

```bash
echo "BRANCH=$(git rev-parse --abbrev-ref HEAD)"
echo "WORKTREE_PATH=$(pwd)"
echo "MAIN_PATH=$(git worktree list --porcelain | head -2 | tail -1 | awk '{print $2}')"
```

### 3. Show Summary and Confirm

```
SHIP CODE

Worktree: <worktree_path>
Branch: <branch> -> main

Steps:
1. /git:commit
2. /git:pull-main
3. /git:pr
4. Migrate tasks
5. Merge PR
6. Done — close window manually

Proceed?
```

### 4. Execute

**Step 1:** Invoke `/git:commit`
- If no staged changes and no new commits, skip

**Step 2:** Invoke `/git:pull-main`
- Worktrees can outlive `main` by days — sync before the PR so the merge is clean
- If already up to date, continue
- If the merge resolved conflicts cleanly, commit the merge (`git commit --no-edit`) and continue
- If any conflict was flagged as "needs review", **STOP** and let the user inspect before resuming

**Step 3:** Invoke `/git:pr`
- If PR already exists, skip
- Note the PR number

**Step 4:** Migrate Tasks (while CWD is still valid)

```bash
ls -d .claude/tasks/*/ 2>/dev/null | grep -v "DONE-"
```

If tasks exist, move to main:
```bash
mv .claude/tasks/<task> "<MAIN_PATH>/.claude/tasks/DONE-<task>"
```

**Step 5:** Merge PR

```bash
gh pr merge <PR_NUMBER> --squash --delete-branch
```

After this command, the Bash CWD will be broken (known Claude Code limitation). **Do NOT run any more Bash commands.** Any attempt will fail with "Path does not exist".

### 5. Final Message

After the merge, show this message immediately. Do NOT attempt any more Bash calls.

```
SHIPPED SUCCESSFULLY

Code merged to main via PR #<N>
Issue: #<N> closed (if applicable)

This window stays alive — feel free to review or continue the conversation.

When you're truly done:
  1. Switch to the main window (ctrl-s + number)
  2. From there, run: /git:rm-worktree <branch>
     (or directly: workmux remove <branch>)

That removes the worktree, the local branch, and this tmux window.
```

**STOP HERE.** Do not attempt cleanup, window management, or any further Bash commands.

## Error Handling

- Stop immediately if commit, pull-main, PR, or merge fails
- If merge fails, show which step failed and how to resume
- After successful merge: NEVER run more Bash commands (CWD is dead)
