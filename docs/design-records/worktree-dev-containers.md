# Worktrees in Dev Containers

The record for making a linked worktree behave like a repository inside its Dev
Container: why the fix is a git config setting rather than a flag on each
`git worktree add`, why the same flag has to ride on `exec` as well as `up`, and
which cheaper routes lost.

**A worktree's `.git` is a file pointing somewhere the container cannot see, so
every checkout created by the `prefix+shift+w` popup answered `fatal: not a git
repository` inside the container — under a wrapper that had already been failing
to start at all, silently, for days.**

---

## Context

`dev nvim` in a worktree reported one thing:

```
dev: failed to start devcontainer — retry verbosely with:
     devcontainer up --workspace-folder … --mount type=bind,source=…,readonly
```

Running that by hand produced the real answer immediately:

```
Unmatched argument format: mount must match
type=<bind|volume>,source=<source>,target=<target>[,external=<true|false>]
```

The CLI validates every `--mount` against
`/^type=(bind|volume),source=([^,]+),target=([^,]+)(?:,external=(true|false))?$/`
and throws before it does any work. Two of the wrapper's mount strings — the
host lazygit binary and `~/.config/lazygit` — carried a `,readonly` suffix that
grammar has no room for. Read-only is not expressible through `--mount` at all:
the parsed mount is serialised back out as `type`/`src`/`dst` and nothing else.
So `dev` and `dev nvim` were broken for *every* project on the machine, not just
worktrees, and had been since the mounts were added. Nothing said so, because
the wrapper ran `up` under `>/dev/null 2>&1` and printed only its own hint.

With the mounts legal, the second defect surfaced. A linked checkout's `.git` is
a file holding `gitdir: /var/home/marc/projects/<repo>/.git/worktrees/<slug>` —
an absolute host path, outside the workspace and therefore absent from the
container. Bind-mounting the checkout alone yields a directory that is not a
repository:

```
$ dev git status
fatal: not a git repository: (null)
```

That kills every git integration inside, including the lazygit the container
mounts specifically so `<leader>gg` works and the identity forwarding that
exists so commits can be made from in there.

The CLI has an answer, `--mount-git-worktree-common-dir`, and its documented
condition is the whole problem: *"This requires the worktree to be created with
relative paths (`git worktree add --relative-paths`)."* The implementation is
guarded on `!isAbsolute(gitdir)` with no `else` — given an absolute path it
mounts nothing, warns nothing and reports success. The failure mode is silence,
not an error.

---

## Decision

Three parts, all small, none of which works without the others.

**Legal mounts, loud failures.** The `,readonly` suffixes are gone; the two
config mounts were already read-only by convention rather than enforcement,
since the provisioner copies them into the per-project store and never writes
back. `up` now writes to a temp file and prints its last twenty lines on
failure, then the retry hint. The next bug of this class costs one line of
reading instead of a manual re-run.

**Relative worktrees by configuration, not by command.** `worktree.useRelativePaths
= true` in the git config seed
(`system_files/usr/share/workstation-os-image/dotfiles/dot_config/git/create_config`),
so every worktree this machine creates records the main repo relatively,
whichever path created it. Existing checkouts convert with `git worktree repair
--relative-paths`.

**The flag on every call.** `dev` passes `--mount-git-worktree-common-dir` to
`up` *and* to all four `devcontainer exec` invocations. It also folds a git
check into the staleness test that already recreates a container missing the
nvim mounts, so a container created before this heals itself on the next
`dev nvim`.

Two gates in `tooling/validate/sources` hold it: one parses every `--mount`
string in the seed against the CLI's grammar after collapsing fish
interpolation, and one asserts the flag and the git config setting stay
together, and that no `devcontainer up`/`exec` line omits the flag.

---

## The routes that lost

**Keep read-only by moving the mounts into `devcontainer.json`.** A *string*
entry in that file's `mounts` array is handed to docker verbatim, so
`readonly` works there. It loses because those files belong to each project's
team and this is one developer's editor plumbing; the only command-line road to
it, `--override-config`, means synthesising a replacement config for every
project `dev` ever touches.

**Download lazygit into each per-project store instead of mounting the host
binary.** This makes the read-only question moot. It was rejected once already,
for a reason that still holds: lazygit is a static Go binary, so the host copy
runs on any base image, and vendoring a second one means a second version to
pin and a download into every store.

**Put `--relative-paths` on each `git worktree add`.** The three AI
`/worktree-create` recipes spell the command and could take the flag. The popup
does not: `executable_worktree-create.sh` calls `herdr worktree create`, and
herdr shells out to git itself with no such option. Flagging the recipes would
leave the primary creation path — the one behind `prefix+shift+w` — as the only
uncovered one. The git config reaches all of them, including JetBrains' "New
Worktree", which also just shells out.

**Construct the extra bind mount in `dev` instead of using the flag.** Doable:
read the `gitdir:` line, resolve the common directory, add a `--mount`. It loses
because the CLI does not only mount that directory, it also *rewrites the
container workspace path* so the relative offset survives the crossing —
`/workspaces/<slug>` becomes `/workspaces/<repo>__worktrees/<slug>`. Hand-rolling
half of that leaves a mount at an offset the `.git` file does not point to.

**Leave git broken inside and use the host lazygit.** herdr has a lazygit pane
action, so this is survivable. It loses because `dev nvim` mounts a lazygit
binary and forwards four `GIT_*` variables for the express purpose of committing
from inside the container; keeping those while conceding that git does not work
there is paying the cost of a feature and disabling it.

---

## Consequences

Enabling relative worktrees sets `extensions.relativeWorktrees` and repository
format version 1 in each **main repository's local `.git/config`**. That file is
never committed, so no collaborator is affected, but any git older than 2.48
reading one of these repositories will refuse it. Everything on this machine and
in the containers it builds is well past that.

The container workspace path for a worktree is now
`/workspaces/<repo>__worktrees/<slug>`. Anything that hardcodes
`/workspaces/<repo>` breaks, and an `exec` that omits the flag chdirs into a
path that does not exist — which is exactly what happened once during this work,
before the flag was added to `exec`.

Nothing here makes the devcontainer CLI louder. It still ignores the flag in
silence when a checkout is absolute, so a worktree created by some future tool
that bypasses the git config will fail the same way, and the only warning is the
`fatal: not a git repository` that started this.

---

## Where to go next

[../subsystems/dev-environment.md](../subsystems/dev-environment.md) owns the
current behaviour: the mount set, the per-project store, and worktree file
propagation. [README.md](README.md) is the index of records.
