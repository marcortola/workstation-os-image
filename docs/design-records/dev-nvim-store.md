# The dev-nvim Store

The record for why `dev nvim`'s per-project store reached 2.8 GB, why the fix is
a garbage collector and one fewer container round-trip rather than the shared
store it looked like it needed, and which sharing designs lost on measurement.

**Half the store tree belonged to git worktrees that no longer existed, three
quarters of its bytes were byte-identical duplicates, and the language scoping
everyone assumed was the cost driver was worth one millisecond.**

---

## Context

The question that started it was whether the per-project Neovim language scoping
earns its keep — `dev nvim` detects a project's languages host-side and passes
them as `NVIM_MASON_LANGS`, and `lua/config/lazy.lua` imports only those LazyVim
language extras. The proposal was to drop the gate, install everything
everywhere, and adopt a reviewed reference configuration wholesale. The stated
goals were a faster Neovim start, "also in the initial load", and a centralised
configuration.

Nothing in `docs/` had ever attached a number to the scoping. `cf31b5d`
introduced it against a real failure, stated in prose:

> `dev nvim` was letting LazyVim install every configured language server (~13)
> in every container: a Python repo pulled basedpyright into a PHP container,
> astro's ts-plugin warned everywhere, cold installs stalled, and the host failed
> to install python/php servers it could never use.

So the first move was to measure rather than argue.

### The gate costs one millisecond

Host Neovim startup, ten interleaved pairs in one process, scoped against all
seven languages forced on:

| | mean |
|---|---|
| `NVIM_MASON_LANGS` unset | 21.71 ms |
| all seven forced | 22.71 ms |

Plugin count 62 → 68, `mason.ensure_installed` 5 → 12, declared LSP servers
7 → 23, treesitter parsers 28 → 35. The import gate changes what is *declared*;
it barely changes what is *loaded* at startup, because LazyVim lazy-loads by
filetype. Startup was never the cost.

### Neovim is 1.8% of a launch

A warm `dev nvim`, measured against already-running containers:

| stage | measured |
|---|---|
| three `devcontainer exec` round-trips | 1127 ms (370/374/383 mencoro; 484/404/419 growwer) |
| host-side shell — detector, git, realpath, sha256 | 29 ms |
| in-container config copy | 3-7 ms |
| Neovim's own startup | 21 ms |

Plus a fourth CLI invocation, `devcontainer up`, deliberately left untimed
because timing it means starting a container. Its floor, via
`devcontainer read-configuration`, is 117-127 ms.

Bare `devcontainer --version` costs 67-73 ms of Node process start, and
`create_dev.fish` invokes the CLI four times per launch: `up` at line 90, the
`ready` probe at 114, `boot` at 186, the launch at 234. The orchestration is the
expense. Neovim is a rounding error inside it.

### Half the disk is garbage

`~/.local/share/dev-nvim` held 2,834,627,961 B across 23 directories. Content
addressing every one of its 100,523 files:

| | bytes |
|---|---|
| byte-identical duplicates | 2,064,977,717 (72.9%) |
| unique | 769,059,644 |

The store key is `sha256($root)[0:12]` (`create_dev.fish:54`), and `$root` is
the nearest `.devcontainer` bounded by `git rev-parse --show-toplevel`
(`create_dev.fish:10-30`). For a linked worktree that toplevel is the worktree,
so **every checkout under `<repo>__worktrees/<branch>` gets its own cold store**.
Thirteen of the twenty-two mapped stores were worktrees, totalling
1,410,771,791 B, and the worktrees behind 1,203,958,354 B of that had already
been deleted — `fix-rgpd`, `fix-stripe-ux`, `fix-logout-issues`,
`feat-guess-business-user` and the rest. Add `_spike`, a dead 2026-07-28
experiment at 190,413,155 B, and 1,394,371,509 B — 49.2% of the tree — was
garbage from checkouts that no longer existed.

Nothing collects it. `create_dev.fish` creates stores and never removes one.

### The fingerprint protects nothing

Each store carries `.builtfor`, `sha256(/etc/os-release + ldd --version + uname -m)`,
and resets the store when it changes (`create_dev.fish:134-139`). Across the
whole tree exactly two values existed — `4086acdcad32a649` on ten stores,
`da3158d12b5b7021` on three.

The split turned out to separate nothing measurable. The Neovim binary is
byte-identical in all fourteen copies (`caf8f91f51241216`), `fd` in all thirteen
(`eea818be74986760`), `rg` in all thirteen (`f401154e2393f900`) — and the
treesitter parsers the reset exists to protect are identical *across* the two
groups (`bash.so bcd87024136ae12e`, `lua.so 9f3aaa1c4e2bd0ea`,
`json.so 747edeb9822aee54`).

The key is also wrong in the other direction: it omits `ver=0.12.4`
(`create_dev.fish:141`), the container's actual Node, and the presence of `cc` —
every input that decides whether a shared artifact would actually run.

One incidental finding: no store has a `node/` directory. The 53 MB Node
download at `create_dev.fish:156` has never fired, because `command -v node`
succeeds in every base image in use here.

---

## Decision

Three changes, in payoff order, and none of them is the one the question
proposed.

**Collect the garbage.** A `just dev-nvim-gc` that removes stores whose project
root no longer exists. Recovers 1,394,371,509 B without touching the store key,
and carries no shared-state risk at all. It defaults to a dry run and deletes
only under `--force`, per the destructive-recipe rule in
[../conventions.md](../conventions.md).

**Merge the `ready` probe into `boot`.** `create_dev.fish:104` is a bare `test`;
prepending it to the `$boot` script removes one whole `devcontainer exec` from
every launch — 370-484 ms measured. The merged script exits 2 for "mount
missing" so the recreate path at `create_dev.fish:117` stays reachable, and
non-zero otherwise for a genuine provisioning failure.

**Share the toolchain, and only the toolchain.** The Neovim binary, `fd` and
`rg` move to `~/.local/share/dev-nvim/toolchain/<fp>`, mounted alongside the
per-project store. Worth 549 MB, and it skips 15,600,086 B of download plus
extract on every newly created worktree store — which, given ten dead worktree
stores accumulated on disk, is the norm rather than the exception.

That last one needs one thing the current code does not do. All three install
guards are pure existence tests (`create_dev.fish:142`, `:153`, `:161`) whose
bodies extract straight into the destination, and `grep -n 'flock\|lock'` over
the file finds only a comment. Test-then-act on a non-atomic `tar xzf` is
correct only while writer and reader are the same container; sharing decouples
them. So the shared toolchain extracts to a temporary directory and renames into
place, which makes the race a lost download rather than a corrupt binary.

The language gate stays. It is worth one millisecond and zero bytes of the
duplication, and removing it would reinstate the `composer: ENOENT` failure
`7a8282b` fixed unless the curated Mason eager set came back with it.

---

## What Lost

**Sharing the store by base-image fingerprint.** The largest number on paper —
1,789,595,485 B — and the design the evidence appeared to point at. It loses on
`create_dev.fish:179-180`:

```sh
rm -rf /nvimdata/config/nvim
cp -a /nvimconf-src /nvimdata/config/nvim
```

Unconditional, every launch. Under one shared store, `dev nvim` in one worktree
deletes the configuration directory another worktree's running Neovim is loaded
from. Worktrees running in parallel is the entire point of the dev-flow layout,
so this is not a corner case here. It also makes the `.builtfor` reset at
`create_dev.fish:137` unreachable, removing the only reclaim path in the script
from a tree that already had no garbage collection.

**Keying the store on the main repo, so worktrees share.** 1,452,408,008 B, and
the worst risk of the three: it shares precisely the stores most likely to be
live simultaneously, and it re-arms the `.builtfor` reset — which fires whenever
two worktrees carry different devcontainer definitions. That is exactly what a
branch that changes the devcontainer does.

**Removing the language gate.** Worth 1.0 ms of startup and none of the
duplication, while adding seven eager Mason tools and seven treesitter parsers to
every store. Four of those seven need `composer`. It was proposed as the fix for
both goals and addresses neither.

**Adopting the reference configuration wholesale.** Its `lua/config/lazy.lua` is
the stock LazyVim starter: no `NVIM_IN_CONTAINER` branch, so every container
would bootstrap its own lazy.nvim and re-clone plugins instead of using the
`/nvim-plugins` mount; no lockfile redirect, so the in-container lock lands in
the directory `create_dev.fish:179` deletes on every launch; and its thirteen
extras are a strict subset of ours, missing php, twig, sql and toml. `2f3eb17`
had already merged what applied, feature by feature, and recorded what it
declined.

**Replacing the per-launch config copy with a read-only bind mount.** Tempting,
and it is the copy that blocks store sharing — but it buys 3-7 ms and takes on a
silent loss. LazyVim writes `lazyvim.json` into `stdpath("config")`
(`lazyvim/util/json.lua:48`), and `if f then` swallows a nil handle, so a
read-only mount discards the write with no error. Both auto-writers are inert
today — the NEWS hash matches at 11866, the config version matches at 8 — and
stop being inert the moment LazyVim updates on the host without host Neovim
having run.

---

## Shipping

The garbage collector ships as `tooling/dev/nvim-store-gc`, reached by
`just dev-nvim-gc`, dry run by default. It resolves each store name back to a
project root by hashing candidate paths, and removes only stores whose root is
gone — never a store it cannot explain, which is why `_spike` is reported rather
than deleted and needs a hand.

`create_dev.fish` loses one `devcontainer exec` and gains a shared toolchain
mount. Both halves of the toolchain change have to agree about where the shared
directory lives, so `tooling/validate/sources` gates that the mount target in
`create_dev.fish` and the path the GC script prunes are the same string.

---

## Where to go next

**Answered, 2026-09-14.** The warm cost of `devcontainer up` is **375-404 ms**,
measured against an already-running container which it did not recreate. It does
*not* outrank collapsing the exec round-trips — a `devcontainer exec` against an
up container measures 514-610 ms against 39-50 ms for the `docker exec` it
performs, and `dev nvim` pays it twice — but it was the largest term left once
those were collapsed, so both shortcuts shipped. The CLI has no cheaper mode:
`--expect-existing-container` only changes what happens when the container is
absent, and `--skip-post-create` measured inside the noise (384/372/369 ms
against 498/394/377 ms) while silently dropping `postStartCommand` and
`postAttachCommand`.

The liveness guard turned out to be free after all, because the probe that makes
`docker exec` possible is the same probe: one `docker ps --filter
label=devcontainer.local_folder=…` at 23-30 ms. `up` is skipped when that probe
hits and the Dev Container definition hashes to what it hashed to when the
container was built. It hashes **content**, not mtime, because git rewrites mtimes on
checkout and mtime therefore does not track content: growwer's
`.devcontainer/Dockerfile` carried a mtime three days newer than its last commit
against a clean tree. An mtime test would call every project changed and never
skip anything. `-newermt` is how such a test gets written, and it is gated
against in code. `dev nvim` on a settled project went from ~1.5 s to ~215 ms.

Two of this record's own premises have since expired, both found by re-measuring
rather than by reasoning. **Node is no longer absent from the stores**: five of
them carried a byte-identical 181,811,945 B copy, 925 MB in total, which the
`command -v node` guard had been missing — almost certainly the same
login-shell PATH problem that now forces `bash -lc` on every fast exec. Node
moved into the shared toolchain alongside nvim, `fd` and `rg`. And the tree had
grown to **6.8 GB across 58 entries** because the collector this record shipped
had never been run with `--force`; running it took it to 3.0 GB across 18.

Mason, at 1.8 GB, was the bulk of what was left. Sharing its install root is
**rejected on evidence**, not deferred: `mason.nvim`'s cross-process lock at
`mason-core/installer/InstallRunner.lua:178-187` is test-then-act rather than
atomic, and the PID it writes is taken from inside one container's PID namespace,
which is meaningless to any other container reading it. That failure is already
in the logs here, in store `a24be7fa4406`, naming a `pid: 310` that never existed
in the reader. The upstream knobs are real — mason's `install_root_dir`,
nvim-treesitter's `install_dir` — but they relocate one Neovim's directory; they
do not make one directory safe for several.

**Hardlink-seeding shipped instead**, and it is the shape that keeps one writer
per tree. A brand-new store is populated from a same-fingerprint donor with
`cp -al`, so the bytes are shared but each store still owns its own directory.
What makes it safe is that neither tool edits an installed file in place: Mason
promotes a package by renaming its staging directory into `packages/`
(`context/init.lua:95`), and nvim-treesitter renames an in-use parser *out of the
way* rather than overwriting it (`install.lua:328`). A shared inode is therefore
replaced, never mutated. `staging/` is excluded because it carries the lockfiles
that caused the `pid: 310` failure above. Measured on a real donor: 16 Mason
packages and 29 parsers seeded, same inode, link count 2, zero new disk.

[worktree-dev-containers.md](worktree-dev-containers.md) covers why a linked
worktree needed a relative common dir to work inside its container at all;
[../subsystems/dev-environment.md](../subsystems/dev-environment.md) is the page
that owns how `dev nvim` works now.
