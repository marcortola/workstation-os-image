# The DMS Greeter Split

The record for why every image build failed for four days against a gate that
was correct when it was written, why the fix changes the check rather than the
input, and which four routes lost.

**`dms-greeter` left DankMaterialShell for an upstream project of its own five
days after a build gate was added asserting that the two ship together. The gate
then failed every build with advice — "re-run once both have caught up" — naming
a state that could never occur.**

---

## Context

`build_files/99-check-build.sh` asserted one exact version across `dms`,
`dms-cli` and `dms-greeter`, under a comment that explained why:

> dms and dms-cli come from copr:avengemedia/dms; dms-greeter comes from
> copr:avengemedia/danklinux. They are released together but published to two
> separate COPRs, so a half-finished publish hands us dms at N and dms-greeter
> at N-1.

Every build from 2026-09-10 onwards failed:

```
check-build: DMS stack version skew: dms-greeter is 1.6.2, expected 1.6.1.
This usually means copr:avengemedia/dms and copr:avengemedia/danklinux are
mid-publish. Re-run the build once both have caught up.
```

The advice was followed. The re-run failed identically, because the premise had
stopped being true.

### The greeter has its own upstream now

```
AvengeMedia/dank-greeter        created 2026-07-19
  v1.6.0  2026-09-03    v1.6.1  2026-09-08    v1.6.2  2026-09-10
AvengeMedia/DankMaterialShell   latest tag v1.6.1, no greeter path at repo root
copr avengemedia/dms            dms 1.6.1-1          -- no 1.6.2 exists anywhere
copr avengemedia/danklinux      dms-greeter 1:1.6.2-1
```

So the greeter is at N+1, permanently, from a different project with a different
release cadence and its own `Epoch: 1` — the epoch exists because "versions
restarted at 1.0.0 when the greeter moved to its own repo", in the spec's own
words. There was no half-finished publish. There was a split.

### The gate was right when it was written

The cohort block arrived in `1e3ccc2`, *Post-cutover fixes: audit scope and DMS
version cohesion (#36)*, on 2026-08-29. `dank-greeter`'s first stable release is
2026-09-03. The premise held for five days and was then invalidated by an
upstream decision, silently, with nothing in this repository to notice.

That ordering is the whole argument for changing the check. This is not an input
that drifted out of spec; it is a model of upstream that expired.

### What four days cost

`99-check-build.sh` runs *inside* the build, so a red gate publishes nothing.

```
GHCR :latest   digest sha256:f2c1258f0dff...  created 2026-09-10T09:05:24Z
booted         same digest, Version 44.20260830
uupd           "No changes in: ostree-image-signed:docker://ghcr.io/..."
```

The registry tag froze for four days and uupd's system module became a silent
no-op — brew and Flatpak kept updating, nothing else did. No kernel, no systemd,
no mesa, and none of the `system_files/` work merged during the window. The base
digest pinned in `Containerfile` fell fifteen days behind `base-main:latest`, and
the dependency automation could not close that gap either: auto-merge waits on
checks that could not go green. Eleven commits landed on a red `main`, which is
the second cost — a genuine regression introduced in that window would have been
indistinguishable from the standing failure.

---

## Decision

Compare **major.minor** rather than the exact version, and say plainly in the
comment that this is a tolerance rather than a restored coupling.

```sh
v="$(rpm -q --qf '%{VERSION}' "$p" | cut -d. -f1,2)"
```

`cut -d. -f1,2` rather than `${v%.*}`, which reduces a two-component `1.6` to
`1`. `%{VERSION}` only, so the greeter's epoch never enters the comparison.

This tolerates the patch divergence that is now normal between two independent
trains, and still catches a greeter from a different feature series than the
shell it must agree with about settings keys — which is the coupling that can
actually break at runtime, since nothing in the RPM metadata asserts a version
relationship in either direction.

**It will fire again.** When `dank-greeter` reaches 1.7 while DMS is still on
1.6, this check fails, and that is the expected case rather than a defect. The
comment and the failure message both say so, and both point here. The durable
answer at that moment is to decide what the greeter should be reviewed against —
not to widen the check a second time.

This was chosen over the option the evidence favoured. A **declared greeter
version** — a reviewed value under `build_files/`, asserted against
`rpm -q dms-greeter`, in the shape of `tooling/data/zirconium-watermark` — models
an independent train exactly, never expires, and makes every greeter release a
deliberate review point. It costs one tracked file and a bump per release. The
author took the smaller diff knowingly; this paragraph is here so the next
failure is read as the anticipated one and that option is still on the table.

Note that `build_files/` is the only thing in the build context — `Containerfile`
has `FROM scratch AS ctx` / `COPY build_files /build_files` — so a declared
version cannot live in `tooling/data/` where the other reviewed values do.

---

## What Lost

**Pinning the greeter to 1.6.1.** Verified to work:
`includepkgs=dms-greeter-1.6.1*` in the vendored repo file installs `1:1.6.1-1`
and passes. It is also the purest "fix the input, not the check". It loses on a
date: COPR prunes superseded builds on a fourteen-day window, and 1.6.1 was built
2026-09-08, so around 2026-09-22 the pin expires into `Argument 'dms-greeter'
matches only excluded packages` — a worse error than the one it replaced, with
nothing in the repository to explain it. Pinning in these COPRs is not
impossible, it is *undurable*, and the three comments that called it impossible
are corrected in the same change.

**Sourcing all three from one COPR**, so the cohort is structural rather than
asserted. This is the right shape and it is unimplementable: `avengemedia/dms`
contains only `dms` (with `dms-cli` as its subpackage) and `avengemedia/danklinux`
contains no `dms` at all. Any workable variant needs upstream to rebuild the
greeter into the other project, and no issue requesting that exists.

**Dropping `dms-greeter` from the loop with no replacement.** Presented as
narrowing the cohort, but it is a deletion: the residual `dms`/`dms-cli`
comparison is a tautology dnf already enforces through `dms.spec`'s
`Requires: dms-cli = %{version}-%{release}`. Nothing would watch the greeter
afterwards, and the gate's own comment calls that the most likely silent
breakage in the image.

**Waiting for upstream.** There is no event to wait for — no dms 1.6.2 was ever
going to be published, and a greeter-only patch release re-breaks any
reconvergence. Meanwhile the wait had already stopped the machine's only OS
delivery path.

**Warning instead of failing** restores precisely the silent-breakage mode the
gate was written to end. A warning in the log of a nightly scheduled build is not
read by anyone.

---

## Consequences

The check now passes a case it would previously have failed: `dms` 1.6.1 against
`dms-greeter` 1.6.2. That is deliberate, and it means a genuine patch-level
incompatibility between the shell and the greeter would no longer be caught here.
Nothing else in the image would catch it either — `assert_vendor` only checks
where a package came from — so the exposure is real and accepted rather than
covered elsewhere.

`docs/subsystems/` is not updated, because none of it described this rule.

---

## Where to go next

The greeter reaching 1.7 ahead of DMS is the trigger to revisit, and it is a
matter of weeks rather than months on the cadence above. At that point the choice
is the declared-version file described under Decision, or a deliberate pin
accepting its fourteen-day expiry, or dropping the assertion and accepting that
nothing watches the greeter. This record exists so that decision is made once,
with the history in front of it, rather than rediscovered from a failing build.

[../subsystems/dev-environment.md](../subsystems/dev-environment.md) is unrelated;
[README.md](README.md) is the index of records.
