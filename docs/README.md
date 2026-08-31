# workstation-os-image — Workstation Handbook

Welcome. This handbook is the guide to the machine this repository builds. It
assumes you know Linux, containers and systemd, but **not** this image, its
conventions, or the workstation it produces. Read it in order and you will
understand *what* the image is, *how* the repository is organised, and *how to
change the machine so the change survives the next update.

> **Golden rule of this repository:** before you change anything, work out which
> layer owns it. `/etc` is a three-way ostree merge, chezmoi seeds are
> create-only, and the DMS UI owns its settings after a single seed — so a
> change made in the wrong layer is not rejected, it is silently kept forever or
> silently lost. You find out one update later, which is the worst possible
> moment.

---

## What is workstation-os-image?

A personal, reproducible Fedora **bootc** workstation built on Universal Blue's
[base-main](https://github.com/ublue-os/main). OS packages, services, desktop
defaults and selected user preferences all become one reviewable Git workflow: a
machine switches to the published image, the owner signs in, and the account
converges on the same working environment.

The published reference is derived from `image.env`, the only file in which this
image's identity is written (`IMAGE_NAME`, `REPO_ORGANIZATION`):

```text
ghcr.io/marcortola/workstation-os-image:latest
```

What it provides, at the level of capabilities rather than a feature list:

- **A graphical session that is installed, not assembled** — greetd, niri and
  DankMaterialShell arrive together with their configuration, their keybinds and
  their default terminal, and are replaced wholesale on every update.
- **A development host with no language runtimes on it** — project-scoped Dev
  Containers, a Neovim that runs inside them, and rootful Docker usable without
  `sudo` from the first session.
- **Personal configuration that is reproducible without being imposed** —
  portable dotfiles ship as create-only chezmoi seeds, so a fresh account gets
  the image's default and an account that has edited the file keeps its edit.
- **A capture loop** that turns a change you made live on the machine into a
  reviewed commit, so the repository never falls behind the workstation.
- **A supply chain verified in both directions** — digest-pinned, cosign-verified
  input images going in; a signed digest going out, which the machine's
  `policy.json` requires before it will pull.
- **Gates instead of tests** — there is no application code here, so correctness
  is asserted by scripts that run in the build, in CI and against the live
  machine. Almost every one exists because its absence let a real regression
  ship.

The split is the thing to learn first: `system_files/` becomes the image,
`build_files/` is read only while the image is built and never reaches a layer,
`tooling/` never leaves your checkout — and on the running machine the image
owns `/usr`, chezmoi seeds own first-write personal defaults, and the DMS UI
owns its own settings. [architecture.md](architecture.md) has the full picture.

---

## Reading order

Read these top to bottom. This hub is the eleventh page of the spine; the other
ten are below, in order.

| # | Document | What you'll learn |
|---|----------|-------------------|
| 1 | [getting-started.md](getting-started.md) | Rebase an existing bootc machine onto this image, what the first graphical login converges on its own, the `wjust` launcher, and the three day-one steps that are deliberately not automatic. |
| 2 | [operating.md](operating.md) | Day-two operation: take an update in the right order, verify a published digest, roll back one deployment or further, read the per-unit journal when a first-boot unit fails, and the housekeeping nothing automatic does. |
| 3 | [architecture.md](architecture.md) | The map: the three top-level trees, what lives inside `tooling/`, the fifteen load-bearing root files, how a change travels from checkout to booted machine, and the ownership table every later page rests on. |
| 4 | [conventions.md](conventions.md) | **The most important document.** Where a change belongs and what to call it, plus the mechanisms worth reaching for — the `/etc` merge, factory-plus-tmpfiles, `ConditionUser`, `ExecCondition`, seed hashing, preset derivation — each with the failure that produced it. |
| 5 | [build-and-ci.md](build-and-ci.md) | The Containerfile's four stages, the nine numbered build scripts, why `build_files/` is bind-mounted while `system_files/` is copied, the four workflows, the build-skip detector, the tag scheme, cache and retention. |
| 6 | [supply-chain.md](supply-chain.md) | Trust in both directions: the two pinned inputs and their cosign verification, RPM signing keys, vendored-repo fencing, signing the published digest, `policy.json`, key rotation, and the scrub filters that keep secrets out of git. |
| 7 | [capturing-changes.md](capturing-changes.md) | The audit → capture → sync → validate loop, the dotfile manifest and its capture kinds, the JetBrains settings machinery, the DMS preference overlay, and how to answer "is there drift?" honestly. |
| 8 | [validation-and-gates.md](validation-and-gates.md) | Which gate proves what and where it runs: image gates in the build, repository gates in CI, machine audits against the live workstation — plus why CI cannot reach every gate and why you fix the input, never the check. |
| 9 | [cookbooks.md](cookbooks.md) | Copy-paste recipes for the changes people actually make: an RPM, a third-party repo and key, a Homebrew or Flatpak entry, a dotfile, a systemd unit, an image-owned `/etc` file, a niri keybind, a DMS default, a Neovim language, a key rotation. |
| 10 | [glossary.md](glossary.md) | Every term this handbook uses that is not plain Linux vocabulary, defined once and in alphabetical order. Keep it open in a tab. |

---

## Subsystem guides

Then read the guide for whichever part of the machine you are working on.

| Subsystem | Guide | Owns |
|-----------|-------|------|
| Desktop session | [subsystems/desktop-session.md](subsystems/desktop-session.md) | greetd, niri, DankMaterialShell: the three-way config ownership and niri's include order, keybinds and the hotkey overlay, the default terminal, switch user, session environment, XWayland interop, power profiles, and what "DMS owns its settings" means. |
| Development environment | [subsystems/dev-environment.md](subsystems/dev-environment.md) | No global runtimes; the `dev` wrapper and the `pro` project picker; `dev nvim` running Neovim inside the container, its per-project store and language scoping; Vim bindings across every editor; worktree file propagation; herdr. |
| AI coding CLIs | [subsystems/ai-clis.md](subsystems/ai-clis.md) | Claude Code, codex and opencode: which configuration is captured versus which tools are installed, the config seeds and their scrub filters, the default MCP servers, browser automation as a CLI rather than an MCP, the four token-cutting tools, and the portable bundle. |
| Packages | [subsystems/packages.md](subsystems/packages.md) | The decision table for where software is declared: RPM lists, compiled and pinned inputs, vendored repositories, the floating COPRs and the NEVRA manifest, codecs, Homebrew (image-provided shadows, trust, updates), Flatpaks, and what is deliberately not installed. |
| Upstream Zirconium | [subsystems/upstream-zirconium.md](subsystems/upstream-zirconium.md) | What was carried over when this image left Zirconium, the Apache-2.0 attribution owed for it inside an MIT repository, the watermark and `just upstream-diff`, the `/port-zirconium` review and its verification standard, and when the watermark may be advanced. |

---

## "I want to..." — quick map

| Goal | Start here |
|------|-----------|
| Install this image on a machine | [getting-started.md](getting-started.md) |
| Take an update, and know it actually landed | [operating.md](operating.md) |
| Roll back to a working deployment | [operating.md](operating.md) |
| Work out why a first-boot user unit failed | [operating.md](operating.md) |
| Understand the layering and what ships where | [architecture.md](architecture.md) |
| Decide which layer a change belongs in | [conventions.md](conventions.md) |
| Turn a change I made live into a commit | [capturing-changes.md](capturing-changes.md) → [cookbooks.md](cookbooks.md) |
| Find out why my merge published no new image | [build-and-ci.md](build-and-ci.md) |
| Verify a published image, or rotate the signing key | [supply-chain.md](supply-chain.md) |
| Add a package, a repository or a Flatpak | [subsystems/packages.md](subsystems/packages.md) → [cookbooks.md](cookbooks.md) |
| Add or reclaim a keybind | [subsystems/desktop-session.md](subsystems/desktop-session.md) → [cookbooks.md](cookbooks.md) |
| Set up my editor, or add a language to it | [subsystems/dev-environment.md](subsystems/dev-environment.md) |
| Work on the AI CLIs and their configuration | [subsystems/ai-clis.md](subsystems/ai-clis.md) |
| Understand a gate that just failed | [validation-and-gates.md](validation-and-gates.md) |
| Review what changed upstream in Zirconium | [subsystems/upstream-zirconium.md](subsystems/upstream-zirconium.md) |
| Look up a term I do not recognise | [glossary.md](glossary.md) |

---

## Audience pages

Two pages serve a reader who is not maintaining this machine.

| Page | For |
|------|-----|
| [forking.md](forking.md) | Building your own workstation from this one: what a fork edits, what it can delete, what it must leave standing, and the order to do it in. |
| [working-with-agents.md](working-with-agents.md) | Directing an AI agent at this repository. Deliberately thin — [AGENTS.md](../AGENTS.md) is canonical, and this page is the pointer chain into it plus the durable-change procedure. |

---

## Design records

Design records are deep dives, not onboarding. They live in
**[design-records/](design-records/README.md)**, and each one is a snapshot of a
durable decision and its rationale as it stood on the day it was written: the
constraint that forced a mechanism's shape, the alternatives that lost, the
failure that motivated the work. A record is never edited to stay accurate —
that would destroy the one thing it is for — so it goes stale by design. The
current code always wins over a record, and the handbook page that owns a topic
always wins over one too.

---

## How to keep this handbook honest

Docs rot. When you change a convention, a mechanism or a published shape, update
the page that owns it in the same pull request. Every example on these pages was
taken from a real file in this repository, so renaming or moving that file means
fixing the example.

Some of that is mechanically enforced, and it is worth knowing the reach.
`tooling/validate/sources` reads `AGENTS.md`, `README.md`, every page under
`docs/` and the agent commands under `.claude/commands/`. Across all four it
fails the build if a cited `` `just <recipe>` `` is not in `just --summary`, if
a cited path under `system_files/`, `build_files/`, `tooling/` or `docs/` does
not exist, or if a relative link resolves nowhere. Cross-file anchors are
rejected outright — a fragment into another page keeps looking valid long after
the heading it names is renamed, so one file is one address.

What the gate cannot check is whether a sentence is still true. Reasoning,
rationale and every claim about behaviour stay the author's problem —
[validation-and-gates.md](validation-and-gates.md) is precise about that line.

If you find something in this handbook that no longer matches the tree, treat it
as a bug and fix it, or flag it in review. A wrong doc is worse than no doc,
because the next reader will trust it.

---

## Where to go next

If you have no machine running this image yet, start at
[getting-started.md](getting-started.md) — it is the only page that assumes no
checkout. If you have one and want to understand what you are standing on, read
[architecture.md](architecture.md) for the layers and who owns what. Then read
[conventions.md](conventions.md) before you change anything: it is the page that
decides where a change belongs, and every rule in it exists because its absence
produced a real failure here.
