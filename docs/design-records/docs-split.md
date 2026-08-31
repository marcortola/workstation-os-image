# Documentation Split

The record for the restructure that replaced an 855-line `README.md` with the
`docs/` handbook you are reading: what was decided, why, and what it cost.

**One file served three audiences in one reading order, so two of them read it
wrong.**

---

## Context

`README.md` had reached 855 lines and 45.7K across fourteen top-level blocks —
an unheaded preamble and thirteen `##` sections — for three audiences that want
different things on the same day.

| Audience | Wants | Where the old README put it |
|---|---|---|
| Operator installing or recovering a machine | Rebase, upgrade, roll back, recover | Lines 738-855 |
| Maintainer changing the image | Architecture, conventions, capture, gates | Lines 258-701 |
| Forker reusing the skeleton | What to edit, delete, leave alone | Lines 702-737 |

That order was backwards for the audience under the most time pressure. "Install
a workstation" opened at line 738 of 855 — the last 14 percent, below all of
`Architecture` and `Conventions` — so recovering an unbootable machine meant
scrolling past the ownership model to reach `bootc rollback`.

The single-file rule was deliberate: `AGENTS.md` declared `README.md` "the
only maintained architecture and operations document" and forbade a second
inventory. It was right about the failure it prevented, wrong about the only
cure. One owner per topic needs the owner decided, not the file kept singular.

---

## Decision

Split into a `docs/` handbook, following the convention already used in this
author's other repositories (`mencoro-app-backend`, the `saas/app-backend`
boilerplate): a short root README that links inward and duplicates
nothing, a `docs/README.md` hub numbering the spine in reading order, subsystem
guides under `docs/subsystems/`, audience pages, and `design-records/`.

Three sub-decisions each had a cheaper alternative. The first was scope: four or
five files rather than twenty. Rejected because the material already existed and
was already read — the split makes existing knowledge addressable rather than
creating any. The larger maintained surface is accepted, not denied.

### The gate follows the content

`tooling/validate/sources` proved, for the prose in its `docs=` array —
`AGENTS.md`, `README.md`, and the checked-in slash commands under
`.claude/commands/` — that every `` `just <recipe>` `` is a real recipe and every
repo-root-relative path under `system_files/`, `build_files/` or `tooling/`
exists. Left seeded at `docs=(AGENTS.md README.md)` it would have gone green over
a near-empty landing pad while the handbook went unchecked — passing precisely as
its coverage collapsed.

Two unguarded conditions got checks in the same change: relative links and
anchors, since the old README linked its own headings (`#switch-user`) unproven;
and a line cap on the root README, since nothing else stops it regrowing.

> The deciding argument is the repository's own closing rule, in `AGENTS.md`:
> "Instructions describe policy; scripts provide enforcement. If a rule must be
> guaranteed, add it to validation or CI rather than relying only on this file."

### Two command prefixes, split by audience

`docs/getting-started.md` and `docs/operating.md` use `wjust`: their reader may
not have a checkout, and `/usr/bin/wjust` clones one on demand. Every other page
uses `just`, a rule stated once in `getting-started.md`. The old README switched
without stating one — `just` through line 439, `wjust` from 552, then `just
brew-apply` again at 822, inside the operator-facing "Update" section.

---

## What else changed

Not a pure move: twenty factual defects, found by diffing every checkable claim
against the tree, were corrected in the same change. By class:

- **CI and workflow claims wrong or absent.** Each was off by a count, a trigger
  or a whole file: `lint.yml` runs four checks on three events,
  not three checks on "every push"; the build-skip detector diffs five paths, not
  the three that implied a `build_files/` change skips the image build;
  `workflow_dispatch` moves `:latest` too; and `clean.yml` went undocumented
  though its retention bounds how far back a rollback reaches.
  [../build-and-ci.md](../build-and-ci.md) now owns all four workflows.
- **Inventories that were incomplete.** `tooling/upstream/` was missing from a
  twelve-entry tree; five of fifteen tracked root files were listed; four recipes
  (`flatpak-prune`, `clean`, `ai-bundle`, `intelephense-licence`) went unmentioned.
- **Mechanisms documented at the wrong path.** `xdg-terminals.list` was placed at
  its runtime location, not at
  `system_files/usr/share/factory/etc/xdg/xdg-terminals.list` with the `L+` line
  in `system_files/usr/lib/tmpfiles.d/10-workstation-terminal.conf` materialising
  it, hiding the factory-plus-tmpfiles mechanism a reader needs.
- **A whole subsystem absent.** `tooling/validate/source-images`, which
  cosign-verifies both digest-pinned input images before anything is built on
  them, appeared nowhere.

---

## Consequences

Twenty files rot in twenty places, and a stale path anywhere now fails CI:
renaming a script under `tooling/` turns the build red until the prose citing it
is updated. That friction is the point — a pointer caught by a gate is cheaper
than one caught mid-recovery. The remaining cost is relearning where a topic
lives, blunted by two habits: file-level cross-links only, and exactly one
owning page per topic.

---

## Couplings updated in the same change

Seven pointers referred to the old structure or to a name the repo had left.

| What | Why it had to move |
|---|---|
| `AGENTS.md` | Declared `README.md` the only maintained architecture and operations document |
| `tooling/validate/sources` | Its `docs=` list was seeded with `AGENTS.md` and `README.md`; the handbook was outside it |
| `image.env` | Its header sends a fork to "the fork checklist in README.md" |
| `system_files/usr/bin/run-ui`, `system_files/usr/libexec/workstation-switch-user` | Both comments cite `README "Switch user"` |
| `.github/workflows/build.yml` | `repo-gates`, the job that runs `tooling/validate/sources`, lives here, and the workflow's `paths` filter lists only image and tooling inputs — without `docs/**` and `README.md` in it, a docs-only push never reaches the gate that checks the docs |
| `SECURITY.md` | Linked from nowhere, despite carrying the CVE-triage routing and the in-scope definition |
| `.worktreeinclude` | Unrelated staleness found while auditing the rest: it named `workmux` as a consumer, and the repo migrated to herdr |

---

## Where to go next

[../README.md](../README.md) is the handbook hub and the reading order this
record produced; [../validation-and-gates.md](../validation-and-gates.md) covers
what `tooling/validate/sources` proves and where its reach stops; and
[README.md](README.md) indexes the other records here.
