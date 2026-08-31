# Upstream Zirconium

This image used to be built on [Zirconium](https://github.com/zirconium-dev/zirconium)
and no longer is. What survives the split is a directory of vendored niri
configuration, an Apache-2.0 attribution notice that must ship with it, and a
deliberate habit of reading upstream's commits. This page covers what was
carried over, what is legally owed for it, and the watermark-and-review loop
that keeps the reading honest.

**Nothing arrives from Zirconium automatically any more, so the only thing that
keeps this image current with it is a person reading its diff on purpose.**

---

## What was carried over

The image derived from Zirconium until 2026-08-29. It now builds on
`ghcr.io/ublue-os/base-main`, digest-pinned in the Containerfile's `BASE_IMAGE`
argument. The niri system configuration was the one piece carried over rather
than rewritten, taken from
[zirconium-dev/zdots](https://github.com/zirconium-dev/zdots).

Seven files live in
`system_files/usr/share/workstation-os-image/niri/includes/`, assembled by
`workstation.kdl` in the directory above them:

| Include | Provenance |
|---|---|
| `dms-base.kdl` | Copied verbatim from zdots |
| `input.kdl` | Copied verbatim from zdots |
| `layout.kdl` | Copied verbatim from zdots |
| `misc.kdl` | Copied verbatim from zdots |
| `shadow.kdl` | Copied verbatim from zdots |
| `window-rules.kdl` | Copied verbatim from zdots |
| `binds.kdl` | Substantially rewritten; originally derived from the same source |

The split between the six and the one is not cosmetic. The NOTICE records that
as of 2026-08-31 the six are byte-identical to upstream commit `ba17a3ae`,
while `binds.kdl` "differs by 336 lines, which is the deliberate fork its own
header documents" — that file opens by declaring itself a "Workstation fork of
the Zirconium/DMS niri binds and hotkey overlay" and then explains why niri's
hotkey overlay order is not the file's own order.

These files are **image-owned scaffolding**: hand-edited in this repository,
shipped read-only inside the image, and never captured back from live state —
unlike the chezmoi seeds next door under
`system_files/usr/share/workstation-os-image/dotfiles/`, which `just sync`
regenerates wholesale from the live account. The account reaches the includes
indirectly: the `scaffold` entry for `.config/niri/config.kdl` in
`tooling/data/dotfiles.manifest` deploys a user config whose first include is
`include "/usr/share/workstation-os-image/niri/workstation.kdl"`. How the
includes are ordered, how DMS reclaims binds from them, and what each bind does
belong to [desktop-session.md](desktop-session.md); this page is only concerned
with where they came from.

---

## What is owed: Apache-2.0 inside an MIT repository

The vendored work is licensed under the Apache License, Version 2.0. This
repository's own code is MIT. That mismatch is exactly why the NOTICE exists and
why it is not optional.

`system_files/usr/share/workstation-os-image/niri/NOTICE` names the upstream
project, its copyright holder and its licence, lists the seven files, and
reproduces the Apache disclaimer. Because `system_files/` is copied verbatim
into `/` by the Containerfile's `COPY system_files/ /`, the NOTICE ships inside
the image at `/usr/share/workstation-os-image/niri/NOTICE` rather than sitting
in the source tree only. `workstation.kdl` points readers at it in its own
header:

```kdl
// Portions vendored from zirconium-dev/zdots under the Apache License 2.0.
// See NOTICE in this directory.
```

> Deleting or emptying that NOTICE breaks the licence terms. Apache-2.0's
> redistribution clause requires the attribution to travel with every
> distribution of the derived work, and the image is a distribution.
> `tooling/validate/repo` asserts the file with
> `[[ -f system_files/usr/share/workstation-os-image/niri/NOTICE ]]`, so
> removing it fails validation — but treat the gate as a backstop, not as the
> reason.

The de-Zirconium rename has its own gates, and they are written to spare the
attribution deliberately. `tooling/validate/repo` fails on a path into the
removed `/usr/share/zirconium` tree surviving anywhere in `system_files` or the
`Justfile`; `build_files/99-check-build.sh` fails on one surviving into the
image-owned directories of the built image. Both write the carve-out into their
own comments: "Prose about Zirconium is history and attribution, and is meant to
stay" in the first, "Attribution prose is fine" in the second. The rule is that
no image path may point at a tree that no longer exists; the history and the
credit stay.

Upstream does not feed these files. They are changed here, reviewed here, and
gated here. A zdots submodule bump appearing in an upstream diff is
informational — read it for fixes, never merge it.

---

## Why the tracking continues

Zirconium still runs the same stack this image runs: niri as the compositor,
DankMaterialShell as the shell, greetd as the greeter, uupd as the update
daemon. It therefore keeps solving problems this image has, and its solutions
are worth reading even though none of them arrive on their own.

The cost of not reading is measurable. `tooling/upstream/zirconium-diff` states
it in its own header: "the base swap alone left nine of its decisions
unported". One of the nine was that the machine ended up with no SSH agent at
all, closed by `feat(desktop): restore the session services the base swap left
disabled`, which is what enables `gcr-ssh-agent.service` and its socket in
`system_files/usr/lib/systemd/user-preset/10-workstation-os-image.preset`. Nine
gaps opened by a single deliberate change, none of them announced by anything,
is the shape this whole mechanism exists to catch.

---

## The watermark and `just upstream-diff`

`tooling/data/zirconium-watermark` is a small JSON file recording the last
upstream commit whose changes were reviewed against this image — the upstream
repository URL, a full 40-character `reviewed_commit`, the date, and who or what
did the review. Its own comment block states the rule: "Never bump it to silence
the diff."

`just upstream-diff` runs `tooling/upstream/zirconium-diff`, which is the
mechanical half of noticing:

```bash
just upstream-diff             # what changed since the watermark
just upstream-diff --patch     # the same, with the full diff appended
```

It clones or fetches Zirconium into
`${XDG_CACHE_HOME:-$HOME/.cache}/workstation-os-image/zirconium` — **outside the
checkout, on purpose**, because `just audit` and gitleaks scan the working tree
and a second repository sitting inside it would be scanned as if it were ours.
It then diffs the watermark commit against `origin/HEAD`, prints the commit log,
and maps every changed path onto the file here it would land in.

### Filtering, and counting what was filtered

The filter is a default-allow list with named exclusions, never an allowlist.
The script says why: an allowlist "skips anything upstream invents after it was
written, and does so silently -- which is precisely the failure this script
exists to prevent."

| Excluded | Why |
|---|---|
| `mkosi.profiles/jackrabbit/*`, `mkosi.profiles/*nvidia*/*`, `mkosi.profiles/liveiso-bootc-ostree/*`, `mkosi.profiles/sysupdate/*` | Profiles the standard bootc image does not build |
| `assets/*`, `docs/*`, `*.md`, `.editorconfig`, `.gitignore`, `.gitmodules` | Upstream's own documentation and repository furniture |
| `.github/*`, except `.github/workflows/reusable-build-bootc.yaml` and `.github/workflows/build-standard-bootc.yaml` | Their CI is not ours; those two are kept because the profile list they pass to mkosi is what makes the rest of the comparison valid |

Excluded paths are counted, not discarded silently. The summary line reads
`files N to review, M excluded as out of scope`, so a skipped path is visible
rather than assumed — if `M` is surprisingly large, that is a signal to read the
exclusion list rather than trust it.

### Where each change would land

Every in-scope path is printed with a class and a target, because the class is
what the review actually turns on: a preset line is a one-line decision, an
overlay file is a diff, a package list needs a build, and a chroot script is a
build step.

| Class | Target here |
|---|---|
| `preset-system` | `system_files/usr/lib/systemd/system-preset/10-workstation-os-image.preset` |
| `preset-user` | `system_files/usr/lib/systemd/user-preset/10-workstation-os-image.preset` |
| `repo` | `build_files/repos/` |
| `packages` | `build_files/packages/` |
| `overlay` | The matching path under `system_files/`, annotated `[we ship this path]` or `[no counterpart here]` |
| `zdots-fork` | The vendored niri directory — forked; read, do not merge |
| `build-step` | `build_files/` |
| `build-inputs` | The mkosi profile list this comparison assumes |
| `other` | Classify by hand |

### Exit codes

They are written to be read by a caller, not by a human alone.

| Exit | Meaning |
|---|---|
| `0` | The watermark equals upstream `HEAD` — "Up to date; nothing to review." A successful `--accept` also exits 0 |
| `2` | Usage or environment error: an unrecognised argument, `git` or `jq` missing, the watermark file missing, `reviewed_commit` not a full 40-hex SHA, or that commit absent from upstream |
| `3` | There are commits since the watermark, whether or not any in-scope file changed |

Exit 3 covers both outcomes deliberately. When only excluded paths moved, the
script still says so — "No in-scope file changed; advance the watermark with
--accept" — and still exits 3, so the watermark advance stays an explicit act
rather than something that happens because a script returned success.

---

## The review: `/port-zirconium`

The judgement half lives in `.claude/commands/port-zirconium.md`, a Claude Code
command. It runs the diff with `--patch` and then requires every in-scope change
to be classified into exactly one bucket, with porting as the exception rather
than the default:

- **Port it** — it fixes something broken here, adds a capability wanted here,
  or tracks a Fedora, systemd or DMS change this image will hit too. Package
  additions backing a DMS feature are called out as the highest-yield class,
  because `tuned-ppd` was missing for months and DMS's power widget simply had
  no backend.
- **Already covered** — and the review must say by what. Three shapes recur:
  `base-main` provides it (bootc, dracut, ostree, resolved, brew, uupd,
  journald persistence, the Flathub `remote-add`); the image holds it under its
  own name (`workstation-chezmoi-*` for upstream's `chezmoi-init`/`-update`,
  `10-workstation-os-image.preset` for `01-zirconium.preset`, `wjust` for
  `zjust`, `workstation-ocr` for `zocr`, `dotfiles/` for `zdots`); or the same
  job is done here by a better mechanism and keeping that mechanism is the
  point.
- **Declined** — with the reason in the commit message. The command carries a
  list of standing declines that are not to be re-litigated: Zirconium branding
  (`zfetch`, `zmotd`, `zprompt`, `zfunny`, `glorpfetch`, `fastfetch.jsonc`,
  logos, wallpapers), `taidan`, kmscon, `rechunker-group-fix`, `cardwire`,
  `ntpd-rs` (base-main's `chronyd` is used instead), `flatpak-preinstall` (the
  Brewfile owns Flatpaks and the preinstall unit is marker-gated, so it runs
  once ever), the `greetd-spawn` PAM stack, and the four unbuilt profiles.

It also refuses to treat upstream as an authority. Three of its files were
wrong when audited — a `99-` preset that never fires because it sorts after
systemd's `90-`, a bootc install default one directory above the
`/usr/lib/bootc/install/` that bootc documents, and an `xdg-terminals.list` that
overwrites the package's own file and discards the `execarg_default` table with
it. Copying upstream's shape without checking it is how those arrive here.

### The verification standard

This is the part of the command that matters most, and the part it says was
broken most recently: **verify in the built image, never by reading the source
tree.** A gate that checks the adjacent thing is worse than no gate, because it
reports success — a terminal-launcher check using `--print-id` reported which
desktop entry resolved and said nothing about which arguments survived, so
`--app-id` and `--title` were being discarded while the check passed.

So for anything ported: run `just build`, exercise the effect inside the
resulting `review-<branch>` image with `podman run`, and add an assertion to
`build_files/99-check-build.sh` that would fail if the port regressed. Assert
the effect, not that a file exists. See
[../validation-and-gates.md](../validation-and-gates.md) for how that gate sits
against the rest, and [../build-and-ci.md](../build-and-ci.md) for the build
itself.

---

## Advancing the watermark

`just upstream-accept` rewrites `reviewed_commit` and `reviewed_date` in
`tooling/data/zirconium-watermark` and prints "Commit it with the review that
justified it." Bare, it resolves `HEAD` inside the cached clone; a specific
commit uses the `--accept=REF` form, so the argument parser never has to guess
whether the next word is a ref or another option:

```bash
just upstream-accept                     # accept the clone's HEAD (see gotchas)
just upstream-accept --accept=<sha>      # accept a specific commit
```

The recipe already passes `--accept`; the explicit `--accept=<sha>` is parsed
afterwards and overrides it, which is why both forms work.

The discipline around it is the whole point of the file. Advance the watermark
only in the same change as the review that justified it. A bumped watermark with
nothing ported is a claim that every commit in the range was examined and
declined — and a false claim of that kind is worse than no watermark, because the
next reader has no way to tell it apart from a real review. For the same reason,
`/port-zirconium` requires the declines to be reported explicitly: a review that
lists only what it ported is indistinguishable from one that stopped reading
halfway.

---

## For a fork

This machinery is specific to this repository's relationship with Zirconium. A
fork inherits `tooling/data/zirconium-watermark`, `tooling/upstream/` and
`.claude/commands/port-zirconium.md`, and the watermark it inherits means
nothing to it — it records a review this repository did, against this
repository's files. Either take over the tracking deliberately, resetting the
watermark to a commit the fork has actually reviewed, or delete the three of
them together. [../forking.md](../forking.md) has the full edit / delete /
do-not-touch checklist.

The NOTICE is a different matter and is not on that list. It travels with the
vendored files under the Apache licence regardless of who is forking whom.

---

## Gotchas and tech debt

> Three SHAs pin this relationship — the watermark's `reviewed_commit`, and the
> two the NOTICE records — and all three can go stale in ways nothing catches at
> build time. Check them when a diff run or a comparison looks wrong, before
> assuming the tooling is at fault.

- **The bare `--accept` can record a stale commit.** The diff compares the
  watermark against `origin/HEAD`, but `--accept` with no ref resolves plain
  `HEAD` in the cached clone, and `git fetch` never moves a clone's
  checked-out branch. The two agree until upstream moves; from the first fetch
  that brings in new commits they diverge, and the bare form then records the
  tip the clone was created at rather than the tip just reviewed — so the next
  diff re-reports commits already read. Pass the SHA the run printed as
  `upstream`: `just upstream-accept --accept=<sha>`.
- **The exclusion comment names a profile that does not exist.** The comment
  above `is_excluded` in `tooling/upstream/zirconium-diff` reads "jackrabbit
  (handhelds), nvidia, liveiso, sysupdate and hawaii are profiles the standard
  bootc image does not build", and the `case` patterns below it name only the
  first four. The code is the correct half: at the reviewed commit upstream has
  four such profiles and no `mkosi.profiles/hawaii` — `hawaii` there is a
  container-signing key, `mkosi.extra/usr/share/pki/containers/hawaii.pub`,
  referenced from the `zirconium-bootc-ostree` profile's `policy.json`. Nothing
  is being missed today, but the comment invites the next reader to trust an
  exclusion that is not there.
- **The watermark commit can disappear from upstream.** If Zirconium rewrites
  history, `git cat-file -e` on the recorded SHA fails and the script exits 2
  with "watermark commit ... is not in ...; upstream may have rewritten
  history". That is not a broken script; it needs a human to find the equivalent
  commit and repoint the watermark.
- **The NOTICE pins a commit in *this* repository too.** It names "commit
  d3e0a15 here" as the point at which the image stopped deriving from the
  Zirconium base. A history rewrite in this repository dangles that pin — it
  already happened once, fixed by `docs(niri): repoint the NOTICE commit pin
  after the history rewrite`, which could not be folded into the rewrite itself
  because the new hash did not exist until the rewrite had run.
- **The byte-identical claim is a snapshot, not an invariant.** The NOTICE
  records that six of the seven includes matched upstream `ba17a3ae` on
  2026-08-31. Nothing re-checks that automatically. If those files are edited
  here, the NOTICE's comparison line becomes stale even though its licensing
  statement stays correct, and it should be updated in the same change.
- **The cache is never pruned.** `zirconium-diff` does a full clone into
  `~/.cache/workstation-os-image/zirconium` and thereafter only fetches. Nothing
  removes it; `just clean` does not touch it, and it should not, since it lives
  outside the checkout by design.

---

## Where to go next

[desktop-session.md](desktop-session.md) owns everything about how the vendored
niri includes actually behave — include order, which binds DMS takes over, and
how `local.kdl` reclaims a key — and is the page to read before editing any of
the seven files. [../validation-and-gates.md](../validation-and-gates.md)
explains why a port is only finished once `build_files/99-check-build.sh`
asserts its effect in the built image rather than in the source tree. If you are
adapting this repository rather than maintaining it, [../forking.md](../forking.md)
covers which parts of the upstream-tracking set to keep and which to delete.
