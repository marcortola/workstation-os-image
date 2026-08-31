# Working with AI Agents

This repository expects to be edited by AI agents, and most durable changes begin
as a live change somewhere else on the machine rather than as an edit here. This
page orients an agent — or the person directing one — and hands off. It stays
thin deliberately: a second copy of the policy would be a second source of truth.

**`AGENTS.md` is canonical. Everything here is a pointer into it.**

---

## The pointer chain

[AGENTS.md](../AGENTS.md) holds the maintenance policy: ownership rules, the
invariants and the failures that produced them, the safety boundary, and how to
report drift. `CLAUDE.md` is a single `@AGENTS.md` import line, so Claude Code
loads that same file rather than a parallel copy.

One redirect points inward from outside the checkout: the global Codex seed at
`system_files/usr/share/workstation-os-image/dotfiles/dot_codex/create_AGENTS.md`
tells an agent to "Read and follow that repository's `AGENTS.md`". No other seed
carries that redirect — a Claude or opencode session reaches the policy only on
entering the checkout.

---

## Making a durable change

1. **Inspect.** `git status` first, preserving unrelated work; then read the live
   setting you are about to change.
2. **Classify its ownership** before writing anything:

   | Change | Where it belongs |
   |---|---|
   | RPMs, daemons, sockets, privileged helpers, presets, factory defaults | the image: `build_files/` and `system_files/` |
   | Deterministic user preferences | one `tooling/data/dotfiles.manifest` entry plus a create-only chezmoi seed |
   | Portable DMS preferences | the DMS overlay, captured with `just dms-capture` |
   | Credentials, tokens, SSH keys, histories, caches, device identifiers, generated DMS state | nowhere in Git |

3. **Audit, capture, validate.** `just audit` for drift, capture the intended
   state, `just sync` to refresh the generated seeds, then `just validate` — and
   `just build` for anything touching the image. Read the resulting diff yourself
   for credentials, machine-specific paths and generated noise.
4. **Branch, open a PR, wait for the image build, merge — then upgrade the
   workstation.** Name the branch for the change, using the same type prefix as
   its commits (`feat/`, `fix/`, `docs/`, `chore/`); Claude Code generates its
   own `claude/*` names and those are left alone. Nothing is published from a
   pull request, so no image carries the change until the merge builds on
   `main`. A change left only on the live machine is one the next reprovision
   deletes.

A prompt that covers all four:

```text
Implement <feature> on this workstation and in workstation-os-image. Follow
AGENTS.md, capture only portable state, validate it, and open a PR. Do not
stage the bootc upgrade until its image build passes and the PR is merged.
```

It names the policy file, bounds what may be captured, demands the validation
run, and fixes the ordering between the merge and the upgrade.

---

## Evidence and safety

Ground claims about live state, or about what a script does, in the file or in a
run of it rather than in inference, and quote the line you relied on. "The unit
probably handles that" is not a finding; reading the unit and pasting the line
is. Drift reports hold to the same standard: enumerate the divergent items,
never the audit's summary counts.

Audit, diff, validate and dry runs are always safe to run. Confirm with the
human before any command that writes live account or cloud state:
`just jetbrains-apply --force` (itself refused unless
`--i-understand-overwrites-cloud` accompanies it), `just ai-reset --replace`,
and `just dms-apply`. Never fix a failing gate by weakening the gate; if an
assertion under `tooling/validate/` or an allowlist in `tooling/scrub/` is
genuinely wrong, say so and stop.

Keep scratch files out of the checkout: `just validate` runs `gitleaks dir .`,
which does not respect `.gitignore`, so anything left in the tree is inside the
secret-scan surface. `just clean` removes the review images and byproducts.

---

## Porting from upstream

The `/port-zirconium` command reviews what changed in Zirconium, the image this
one was forked from, and decides change by change whether it belongs here —
porting is the exception, not the default. `just upstream-accept` advances
`tooling/data/zirconium-watermark`, and only in the same change that did the
review. See [subsystems/upstream-zirconium.md](subsystems/upstream-zirconium.md).

---

## Where to go next

[conventions.md](conventions.md) answers "where does this change belong?" in
full, including why each mechanism exists; read it before adding a file.
[capturing-changes.md](capturing-changes.md) covers the audit-capture-sync-validate
loop, the manifest, and the JetBrains and DMS workflows, and
[validation-and-gates.md](validation-and-gates.md) explains which gate proves
what and where CI's reach stops.
