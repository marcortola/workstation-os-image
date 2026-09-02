# One post-checkout slot, two owners

The record for making Git LFS and the worktree-propagation hook share
`.git/hooks/post-checkout`: why the managed hook chains git-lfs rather than the
other way round, why the hook's ownership sentinel had to grow a version number,
why the herdr popup stopped treating a hook's exit status as its own, and which
cheaper routes lost.

**One repository ran `git lfs install` once, in June. That was enough to make the
`prefix+shift+w` popup report `worktree_create_failed` over a checkout git had
already finished, to keep that repository's committed `.worktreeinclude` from
ever being applied, and — once the hook landscape was actually enumerated — to
reveal that `just worktree-init --all` could update none of the 30 repositories
on the machine.**

---

## Context

The popup printed this and stopped:

```
{"error":{"code":"worktree_create_failed","message":"Preparing worktree (new branch 'feat/google-goto')\n\nThis repository is configured for Git LFS but 'git-lfs' was not found on your path. If you no longer wish to use Git LFS, remove this hook by deleting the 'post-checkout' file in the hooks directory (set by 'core.hookspath'; usually '.git/hooks')."},"id":"cli:worktree:create"}
failed (exit 1). press enter to close
```

The obvious reading — the image is missing `git-lfs`, so checkouts fail — is
wrong on both halves, and following it would have shipped a fix that silenced
the message while leaving every real defect in place.

**The checkout did not fail.** `githooks(5)` on `post-checkout`:

> This hook cannot affect the outcome of `git switch` or `git checkout`, other
> than that the hook's exit status becomes the exit status of these two
> commands.

git runs the hook *after* the working tree is written. Reproduced in a scratch
repository: with a `post-checkout` that is just `exit 2`, `git worktree add -b wt
../wt` returns 2 and still leaves `../wt` on disk with the branch created and the
index written. The real checkout was likewise complete — 420 of 420 tracked
files, clean tree, correct relative `.git` — and `git clone` was never affected
at all, since hooks are not cloned and `init.templateDir` gives a fresh clone
ours.

**The repository does not use LFS.** `git log --all -- .gitattributes` is empty:
no `.gitattributes` was ever added on any ref, and no ref contains an LFS
pointer. The only traces are `lfs.repositoryformatversion 0` in `.git/config`,
two hooks dated Jun 7, and four orphan blobs under `.git/lfs/objects`. It is
residue from a single `git lfs install`.

What actually broke, in three layers:

1. **The popup.** `executable_worktree-create.sh` ran under `set -euo pipefail`
   with an unguarded `response=$(herdr_cli worktree create …)`. herdr writes its
   error JSON to stderr and exits 1, so `set -e` killed the script before
   `layout.sh` — leaving a complete checkout with no workspace layout, no
   propagated files and no `node_modules`. `adopt-worktrees.sh` then launders it
   at the next herdr start: the orphan reappears as an ordinary-looking
   workspace, distinguishable only by its tab still being named `1`.
2. **The hook slot.** git-lfs's stock hook occupied `post-checkout`, so the
   primary propagation net never fired. The checkout was missing `.env`,
   `.nvmrc`, `.idea/` and `.claude/settings.local.json`, all of them listed in
   that repository's committed `.worktreeinclude`.
3. **The retrofit.** Enumerating all 30 repositories under `~/projects` showed
   27 still holding the *pre-sentinel* hook — byte-identical to each other,
   comments still naming workmux and the JetBrains "New Worktree" UI — one
   holding the sentinel with comment-only drift, one holding git-lfs's, and one
   holding none. The seed matched zero of them, so every repository took a skip
   branch and `--all` updated nothing. The managed hook was frozen at clone time,
   machine-wide, and had been since the sentinel was introduced.

---

## The constraint

`git lfs install` does not merge. From the git-lfs manual: `--force` "forcibly
overwrite any existing hooks", `--manual` "prints instructions for manually
updating your hooks … useful if `git lfs install` fails due to existing hooks and
you wish to preserve their functionality". There is one `post-checkout` file per
repository — `tooling/worktree/init` resolves it through `--git-common-dir`, so
every linked worktree shares it — and neither hook can host the other as
written.

The contention is asymmetric, and that asymmetry decides the design:

- `init.templateDir` puts **our** hook in first for every repository cloned on
  this machine. In those, `git lfs install` is the one that fails.
- A repository that arrives with git-lfs's hook already in place keeps it
  forever, because `tooling/worktree/init` refuses to clobber a hook it does not
  recognise.

So on this machine, new clones break LFS and imported clones break propagation.
Whichever hook we make subordinate, the other one has to carry it — and only one
of the two is ours to edit.

---

## The decision

**The managed hook carries Git LFS, and `git lfs install` is never run here.**

Three files hold the one mechanism, and `tooling/validate/sources` gates that
they agree:

- the hook chains `git lfs post-checkout "$@"` when `git-lfs` is on `PATH`,
  before it `exec`s `workstation-worktree-sync`;
- the git config seed declares the `[filter "lfs"]` block that `git lfs install`
  would otherwise have written, which is the half that actually resolves LFS
  content;
- `build_files/packages/dev.list` ships `git-lfs`, and `99-check-build.sh` asserts
  it is present.

**The chain never propagates a failure.** git-lfs's stock hook exits 2 when the
binary is missing; ours swallows a non-zero `git lfs post-checkout`. This is the
same invariant `workstation-worktree-sync` already states about itself — "it must
never abort the surrounding worktree or checkout operation" — and this incident
is why it exists. Since the hook runs after git has finished, a non-zero exit
undoes nothing; it only misinforms the caller.

**The ownership sentinel carries a version.** `tooling/worktree/init` now
replaces any installed hook whose version is older than the seed's, reporting
`hook: upgraded (v0 -> v3)`. A hook with no sentinel that still calls
the delegate loop *verbatim* reads as version 0, which covers all 27
pre-sentinel copies. Matching on the loop rather than on a mention of the
helper's name is deliberate: a substring probe would also swallow a third party's
hook that merely names it in a comment. A pre-sentinel hook is backed up beside
itself before it is replaced, because it carries no version to diff a
composition against. Same version with different bytes still means "something
composed onto it" and is still preserved; a strictly newer version is refused and
reported as newer, never as a local edit; a genuinely foreign hook is still never
touched.

Without this, every line of the LFS chain above would have been dead code in 29
of 30 repositories. The lever proved itself immediately: review turned up two
more defects in the hook body — the LFS chain sat *below* the branch-checkout
gate, making it a subset of the stock hook it replaces, and the `exec` on the
delegate handed the delegate's exit status to the caller as the checkout's — and
fixing both meant bumping the sentinel to v3 and re-running `--all`, which
carried the new body into all 30 repositories in one pass.

**The popup adopts rather than abandons.** On a non-zero `herdr worktree create`
it now probes `$worktree_path`; if git produced it, the popup opens it under the
active workspace, runs the `worktree.created` handler that herdr never fired, and
continues to `layout.sh`. Only a checkout that does not exist is a failure.

---

## The trap the build caught

Adding `git-lfs` to `dev.list` is not inert. Its RPM `%post` runs
`git lfs install --system`, which writes `/etc/gitconfig` — a file `base-main`
does not ship at all, verified by running the base image directly. `/etc` is a
three-way ostree merge, so a file a build leaves there becomes machine-local
forever and stops tracking the image, and `bootc container lint` passed the layer
without comment (13 checks, 1 skipped).

`20-packages.sh` therefore undoes the scriptlet's half after the install loop,
in the same file that caused it. `git lfs uninstall --system` removes only the
keys it added and leaves the file zero-length rather than absent, so the file is
dropped only when nothing else is in it — a future base that ships its own
`/etc/gitconfig` survives. `99-check-build.sh` then asserts `/etc/gitconfig` does
not exist, because the next package with a config-writing scriptlet will not
announce itself either.

This is the reason the LFS filter is declared in the chezmoi git config seed
rather than left to the system file: one declaration, in the layer this
repository actually owns.

---

## What lost

**Ship `git-lfs` and stop there.** The first plausible fix, and the one the error
message points at. It makes the stock hook exit 0, so the popup goes green — while
the primary propagation net stays permanently dead in that repository, silently
downgraded to the machine-local backstop that this handbook explicitly ranks
second. It is the charter's own "dead code, silently" failure shape. `git-lfs` is
still shipped, because a clone of a repository that genuinely uses LFS would
otherwise yield pointer files; it is just not the fix.

**Make the popup tolerate a failing hook by ignoring the exit code.** It cannot:
the popup never sees the hook's exit status, only herdr's. And leniency is the
wrong shape anyway — the probe asks whether the checkout exists, which is the
question that actually matters.

**Roll the checkout back when creation fails.** Rejected outright. The checkout
in this incident was perfectly good; an automatic `rm` would have destroyed it.
It would also be a third deletion path, against the standing rule that ship and
close-workspace are the only two and that both end in the shared
`checkout-remove.sh`.

**Delete the hook from the one repository and call it done.** Necessary but not
sufficient — it was done, and it is what restores that repository — yet it fixes
one repository by hand while leaving the popup fragile, the retrofit frozen, and
the next `git lfs install` free to do it again.

**Teach `tooling/worktree/init` to adopt and wrap a foreign hook.** Rejected as
too clever: wrapping someone else's hook means owning its semantics, and the
common case (stale residue from an `install` that tracked nothing) deserves
deletion, not preservation. `init` reports the foreign hook and the handbook says
how to clear it.

**A hash allowlist of known-good previous hooks, instead of a version number.**
Brittle — every whitespace change needs a new hash — and it answers "have I seen
this file" when the question is "is this older than mine".

---

## What is asserted

`tooling/validate/sources` greps the seed for a versioned sentinel, for
`git lfs post-checkout`, the git config seed for `[filter "lfs"]`, and `dev.list`
for `git-lfs`. `tooling/worktree/test-init` had never executed the hook — it
compared bytes and grepped — so it now runs it against a closed `PATH` and
asserts: git-lfs absent exits 0 and still reaches the delegate; a git-lfs that
exits 3 still exits 0 and still reaches the delegate, and was invoked with the
hook's three arguments; a file checkout does nothing; a pre-sentinel hook is
upgraded; a foreign hook is not.

Nothing asserts that the version was incremented when the body changed. That is a
gate that would have to compare against a previous revision of the same file, and
it is left out deliberately — the sentinel's own comment carries the instruction
instead.

Nothing in `tooling/audit/` looks at hooks at all, so a repository whose slot is
hijacked after onboarding is still invisible to `just audit`. `just worktree-init
--all` is the manual sweep.

Two limits are accepted rather than engineered around:

**The `[filter "lfs"]` block reaches new accounts only.** The git config seed is a
chezmoi `create_` entry, so it writes only where no `~/.config/git/config`
exists — verified by applying the seed against a scratch HOME holding a
pre-existing config, which came back unchanged. That is the charter's rule
working as intended ("`create_` entries for personal defaults so existing user
edits win"), and it is equally true of `templateDir` and
`worktree.useRelativePaths`, both of which are load-bearing. The consequence is
narrower than the validate gate's wording suggests: the gate proves the three
files agree in the *repository*, not that all three reached an already-provisioned
account. This account got the block by hand, live, before `just sync` captured
it. Any other existing account needs the same.

**A Dev Container sees the smudged file, not the pointer.** With the host now
resolving LFS content, an LFS-tracked file is real bytes in the working tree.
`dev` bind-mounts that tree into a container that has neither the filter nor the
binary, so a commit made inside the container would store the content rather than
a pointer. No repository on this machine tracks anything in LFS today — zero
`.gitattributes` with `filter=lfs` across all 30 — so this is a hazard to know
about rather than one to fix now; the fix, when a repository needs it, is
git-lfs inside the devcontainer image, not a change here.
