# Build and CI

How this image is assembled — the Containerfile's four stages, the nine numbered
build scripts, the build context that feeds them — and what GitHub Actions does
with the result: which jobs run, which pushes actually rebuild, and what ends up
published under which tag.

**Everything the build reads travels in a throwaway `scratch` stage and is
bind-mounted, so no script, package list or repo file reaches a layer; only what
the image ships is ever copied in.**

---

## The build context

`.containerignore` excludes everything and then re-admits four paths, each as a
pair — the bare entry admits the directory, the `/**` entry admits its contents:

```text
**
!Containerfile
!image.env
!system_files/
!system_files/**
!build_files/
!build_files/**
```

`tooling/`, `.github/`, `docs/` and the Justfile are therefore not in the context
at all. That is the structural half of the build-skip logic further down: a
change to host-side tooling cannot alter the image, because the builder never
sees it.

`image.env` is in the context because it is both a build input and a runtime one.
`COPY image.env /usr/share/workstation-os-image/image.env` runs before the second
`RUN` chain, so `40-signing.sh` and `60-metadata.sh` source the baked copy — the
same file, at the same path, the machine reads later. One value, one place.

---

## The four stages

The Containerfile has four `FROM` lines but pulls only two distinct images, and
both are pinned by digest: the brew payload, and `${BASE_IMAGE}`, which the
`toolchain` and final stages share.

| Stage | `FROM` | Produces |
| --- | --- | --- |
| `brew` | `ghcr.io/ublue-os/brew:latest@sha256:bed0568…` | The Homebrew payload: the tarball, the `brew-setup`/`update`/`upgrade` units and their preset |
| `ctx` | `scratch` | Nothing shippable — it exists only to carry `build_files/` for the bind mounts |
| `toolchain` | `${BASE_IMAGE}` | `/staging`, holding everything compiled or fetched rather than packaged |
| final | `${BASE_IMAGE}` | The published image |

`${BASE_IMAGE}` defaults to a digest-pinned ublue base:

```dockerfile
ARG BASE_IMAGE=ghcr.io/ublue-os/base-main:latest@sha256:9b43dba…
```

The digest is the pin that matters. It fixes the kernel, systemd, mesa and the
whole negativo17 codec stack in one value — the overwhelming majority of the
image by bytes. The desktop stack cannot be pinned the same way, because the
COPRs it comes from prune superseded builds, so versionlocking to an older NEVRA
is impossible there. The NEVRA manifest baked by `90-cleanup.sh` is the
substitute; see [subsystems/packages.md](subsystems/packages.md).

Both pinned digests are cosign-verified against `build_files/keys/ublue-os.pub`
by `tooling/validate/source-images` before any build runs — see
[supply-chain.md](supply-chain.md).

### The two cross-stage copies

```dockerfile
COPY --from=brew /system_files/ /
COPY --from=toolchain /staging/ /
```

The brew payload lands *before* `COPY system_files/ /`, so our own files win any
collision. brew itself is never run during the build; `brew-setup.service`
unpacks it on first boot.

Homebrew arriving as a digest-pinned image layer rather than an installer script
is why `.github/dependabot.yml` exists at all, and why the stage is *named*
instead of being written as `COPY --from=ghcr.io/ublue-os/brew:…`. The
Containerfile says so:

```text
# A named stage rather than `COPY --from=<image>`: dependabot updates FROM
# lines and cannot see an image reference buried in a COPY.
```

### The toolchain stage

One builder stage, not three, and no cleanup inside it:

```text
# Everything that is not packaged, compiled once into /staging. One builder
# stage rather than three: the compiler is pulled in once and the layer is
# discarded wholesale, so uninstalling build deps afterwards is wasted time.
```

It carries four `ARG`s — `KEYD_VERSION`, `KEYD_SHA256`, `FIRACODE_VERSION`,
`FIRACODE_SHA256` — and `tooling/validate/image-build` asserts the two checksum
`ARG`s are present, so the fetches here cannot quietly become unverified.

### Identity `ARG`s on the final stage

The final stage declares `IMAGE_NAME`, `REPO_ORGANIZATION` and `IMAGE_DESC` and
turns them into OCI labels. Their defaults must match `image.env`, and
`tooling/validate/image-build` proves it by pattern rather than by line number:

```bash
arg="$(sed -n "s/^ARG ${key}=//p" Containerfile)"
[ "$arg" = "$value" ] \
    || fail "Containerfile ARG ${key}=${arg} does not match image.env ${key}=${value}"
```

---

## Layer ordering

The build is arranged around one cache invariant: **the slow, stable
runtime-package transaction stays ahead of the volatile `system_files/` copy.**
`10-repos.sh` and `20-packages.sh` run in a single `RUN`; `COPY system_files/ /`
comes after it. Editing a unit file therefore rebuilds a copy layer, not a
several-hundred-package dnf transaction.

This is not left to good intentions. `tooling/validate/image-build` compares the
two line numbers directly:

```bash
package_layer=$(line_of Containerfile '/ctx/build_files/10-repos.sh')
config_layer=$(line_of Containerfile 'COPY system_files/ /')
(( package_layer < config_layer )) || \
    fail "runtime packages must be installed before copying volatile configuration"
```

### Why `build_files/` is bind-mounted and `system_files/` is not

Every `RUN` that executes a build script mounts the `ctx` stage at `/ctx`:

```dockerfile
RUN --mount=type=bind,from=ctx,src=/,dst=/ctx \
    --mount=type=cache,target=/var/cache/libdnf5,sharing=locked \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build_files/10-repos.sh && /ctx/build_files/20-packages.sh
```

so the scripts, package lists, repo files and keys are readable during the build
and present in no layer of the result. The gate that keeps it that way:

```bash
if grep -Eq '^COPY build_files/' Containerfile; then
    fail "build inputs must reach the final stage via the ctx bind mount, not COPY"
fi
```

`system_files/` deliberately does not travel that way. It has a single source and
needs no merge, so it is copied straight to `/`. Putting it in `ctx` would also
cost the cache invariant above, because a bind mount from a stage keys on the
stage result rather than on the files actually read — one overlay edit would
re-key the package layer.

### `--network=none`

The second `RUN` chain (`30-` through `99-`) is declared `--network=none`. Every
script in it works from the overlay and the `ctx` mount, and making the cut
structural means the day someone adds a fetch there it fails in the build rather
than becoming an unpinned input nobody notices.

---

## The nine build scripts

The `NN-` prefix *is* the execution order, and the gaps are intentional: a step
can be inserted without renumbering the ones after it.

| Script | Stage | What it does |
| --- | --- | --- |
| `00-toolchain.sh` | `toolchain` | Installs gcc, make, curl, tar and the libX11/libXfixes headers, then fills `/staging`: compiles `workstation-x11-clipsync` from `build_files/src/`, builds keyd from a checksummed release tarball (daemon, unit and sysusers file only), and unpacks the checksummed FiraCode Nerd Font release under `/staging/usr/share/fonts`. |
| `10-repos.sh` | final | Installs the vendored RPM signing keys into `/etc/pki/rpm-gpg` and `rpm --import`s them *before* dropping the vendored `.repo` files into `/etc/yum.repos.d`, then enables `fedora-multimedia`. Keys first, because every repo file references its key by `file://`. |
| `20-packages.sh` | final | One dnf5 transaction per `packages/*.list`, so a failure names the group it came from instead of dumping one 200-package error; `exclude.list` is applied to every transaction. Also removes `ublue-os-update-services`, whose presets would otherwise re-schedule paths uupd already covers. |
| `30-desktop.sh` | final | Session wiring: strips the leading `-` off the `pam_gnome_keyring` lines in `/etc/pam.d/greetd`, points `default.target` at `graphical.target`, deletes three RPM-owned desktop entries that are not startable applications (`btop`, `foot-server`, `fcitx5`), and rebuilds the font cache so the FiraCode drop is visible to fontconfig. |
| `40-signing.sh` | final | Merges an owner-scoped `sigstoreSigned` entry into the base's `/etc/containers/policy.json` (merge, not replace — dropping ublue's entry would leave the machine unable to pull its own base) and generates `registries.d/workstation-signing.yaml`. |
| `50-services.sh` | final | Explicitly disables `rpm-ostreed-automatic.timer`, `brew-update.timer`, `brew-upgrade.timer` and `dnf-makecache.timer`, then runs `systemctl preset` and `systemctl --global preset` on the unit names read out of the two preset files. |
| `60-metadata.sh` | final | Writes `VARIANT_ID`, `NAME` and `PRETTY_NAME` into `/usr/lib/os-release` from `image.env`. `PRETTY_NAME` is rebuilt as `"$OS_NAME $VERSION"` so the brand is added without discarding the base's per-deployment version. `ID` stays `fedora` (load-bearing) and `LOGO` stays `fedora-logo-icon` (it keeps a Zirconium branch in DMS dead). |
| `90-cleanup.sh` | final | Deletes every repo the build added, bakes the sorted NEVRA `package-manifest.txt`, relocates build-created accounts out of `/etc/passwd` and `/etc/group` into `/usr/lib`, relinks the rpm-ostree base rpmdb, and clears the dnf caches. |
| `99-check-build.sh` | final | 29 gate sections that assert the build's *decisions* took effect — which repo a package came from, whether a preset actually enabled a unit, whether a `sed` matched anything. Mutates nothing. |

`50-services.sh` derives its preset arguments rather than repeating them,
reading the `enable` lines out of
`system_files/usr/lib/systemd/system-preset/10-workstation-os-image.preset` and
`system_files/usr/lib/systemd/user-preset/10-workstation-os-image.preset`. The
explicit `systemctl disable` calls are separate because a preset file cannot undo
an enablement symlink another layer already wrote into `/etc`. See
[conventions.md](conventions.md).

### Why `99-check-build.sh` runs last

It is the only script that reads the *finished* filesystem, so everything it
asserts has to already be in place: packages installed, presets applied, repos
removed, accounts relocated. It is also the reason the `bootc container lint`
call lives in its own `RUN` afterwards rather than at the end of `90-cleanup.sh`:

```dockerfile
RUN --network=none rm -rf /run/systemd && \
    bootc container lint --fatal-warnings
```

`99-check-build.sh` runs `systemd-analyze`, which recreates `/run/systemd`, so
the last write to `/run` has to happen in the layer the lint actually reads.

Because these gates run *inside* the build, `just build` reaches them too. CI
adds only what a build cannot prove about itself — see
[validation-and-gates.md](validation-and-gates.md).

---

## What `build_files/` carries

Four subdirectories beside the scripts, none of which reaches a layer.

| Directory | Contents |
| --- | --- |
| `build_files/packages/` | One `.list` per group — `copr.list`, `desktop.list`, `dev.list`, `docker.list`, `fonts.list`, `input-method.list`, `insync.list`, `media.list`, `qt-style.list`, `terra.list` — plus `exclude.list`, which `20-packages.sh` turns into `--exclude=` arguments on every transaction. |
| `build_files/repos/` | Six vendored `.repo` files: the three COPRs (`copr-yalter-niri`, `copr-avengemedia-dms`, `copr-avengemedia-danklinux`), `docker-ce`, `insync` and `terra`. Installed by `10-repos.sh` and deleted again by `90-cleanup.sh`, which keeps only `fedora*.repo` and `negativo17*.repo`. |
| `build_files/keys/` | `ublue-os.pub` (the cosign key `tooling/validate/source-images` verifies the two pinned input images against), `rpm/` with the six RPM signing keys, and `rpm-key-sources.json`, the manifest `tooling/validate/rpm-keys` re-fetches each key against to prove the vendored copy still matches upstream. |
| `build_files/src/` | `workstation-x11-clipsync.c`, compiled in the `toolchain` stage. |

Repos are vendored rather than fetched because a remote repofile's `baseurl` and
`gpgkey` silently become the build's trust anchors on whatever day it runs. A
vendored file puts both under `git diff` and gitleaks, and removes a class of
transient build failure. Where a package is declared, and the four-part rule
every vendored repo must satisfy, belong to
[subsystems/packages.md](subsystems/packages.md) and
[supply-chain.md](supply-chain.md).

---

## Building locally

```bash
just build
```

The Justfile loads `image.env` (`set dotenv-filename := "image.env"`,
`set dotenv-load`) and runs:

```bash
podman build --pull=always \
    --build-arg "IMAGE_NAME=$IMAGE_NAME" \
    --build-arg "REPO_ORGANIZATION=$REPO_ORGANIZATION" \
    --build-arg "IMAGE_DESC=$IMAGE_DESC" \
    --tag "$IMAGE_NAME:review-$(git branch --show-current | tr / -)" \
    -f Containerfile .
```

No `BASE_IMAGE` is passed, so the local build uses the Containerfile's own pinned
`ARG` — the same reference CI resolves, since the workflow's "Resolve the pinned
base" step reads it back out of the file with `sed` unless the `BASE_IMAGE`
repository variable overrides it. `--pull=always` matters: without it podman
happily reuses a days-old cached copy of the base and a build failure gets
misattributed. The result is tagged `<image>:review-<branch>` and never pushed.
`just clean` removes those review images along with the other untracked
byproducts.

---

## The build workflow

`.github/workflows/build.yml` runs four jobs.

| Job | What it runs |
| --- | --- |
| `image-inputs` | A single `git diff` that decides whether the image needs rebuilding, exported as the `changed` output. |
| `repo-gates` | `tooling/validate/repo`, `tooling/validate/image-build`, `tooling/validate/sources`, `just --fmt --check --unstable` and `just --list`; an assertion that the workflow's `IMAGE_REF` and `image.env` have not drifted; `tooling/validate/source-images`; `tooling/validate/rpm-keys`; and shellcheck over every executable and `*.sh` under `tooling`, `build_files`, `system_files/usr/bin` and `system_files/usr/libexec`. |
| `dms-settings-tests` | `tooling/dms/test`, with `DMS_SETTINGS_SPEC` pointed at `tooling/fixtures/dms-settings-spec.js` so the DMS overlay lifecycle can be exercised on a runner with no DMS installed. |
| `build` | `needs: [image-inputs, dms-settings-tests, repo-gates]` and `if: needs.image-inputs.outputs.changed == 'true'`. Builds, diffs the package manifest, smoke-tests, then publishes. |

The shellcheck container is pinned (`docker.io/koalaman/shellcheck:v0.9.0`) for
the same reason the lint workflow's tools are: a silent version rollover presents
as a new finding on an unchanged tree.

### Why CI cannot run every gate

`repo-gates` runs the gates that need nothing but the checkout. Even
`tooling/validate/repo` stops short of its own end there: its chezmoi-apply and
`niri validate` assertions need both binaries, neither of which is on a runner,
so it announces the skip and exits — `99-check-build.sh` re-runs those parses
inside the built image, which ships both.
`tooling/validate/all` is not among them, and cannot be. `tooling/validate/repo`
was split out of it precisely so CI could run something, and its header says why
the parent stayed behind: validate "ends in audit-workstation and a live
`chezmoi managed`, which need the machine to be booted into this image, so it can
only ever run locally." Two checks that were still stranded inside it were lifted
out into the workflow for the same reason:

```text
# Formatting and parse of the Justfile. These live in
# tooling/validate/all, which needs the live workstation, so CI never
# reached them -- and just is already on PATH here for the recipe gate.
```

Which gate proves what, and where the image/machine boundary sits, is
[validation-and-gates.md](validation-and-gates.md).

---

## Deciding whether to build

Two independent filters, and they do not agree — deliberately.

**Layer one, the workflow trigger.** `on.push.paths` and
`on.pull_request.paths` both list ten entries: `Containerfile`, `image.env`,
`system_files/**`, `build_files/**`, `tooling/**`, `Justfile`, `docs/**`,
`README.md`, `AGENTS.md` and `.github/workflows/build.yml`.

**Layer two, the `image-inputs` detector.** It diffs five:

```bash
elif git diff --quiet "$BASE_SHA" "$HEAD_SHA" -- \
    Containerfile image.env system_files build_files \
    .github/workflows/build.yml; then
  echo "changed=false" >> "$GITHUB_OUTPUT"
```

`tooling/**`, `Justfile`, `docs/**`, `README.md` and `AGENTS.md` are in the
trigger and not in the diff. A push that touches only host-side tooling, or only
prose, therefore *starts* the workflow — so `repo-gates` and
`dms-settings-tests` run against it, and `repo-gates` is where the docs gate
lives — and the detector then reports `changed=false`, so `build` is skipped.
That is the intended shape: tooling and documentation are checked, but neither is
in the build context and neither can change the image.

A change under `build_files/` does rebuild the image. It is in both lists.

`schedule` and `workflow_dispatch` short-circuit to `changed=true` before the
diff is reached, since there is no meaningful base commit to diff against.

> A green "Build bootc image" run is not evidence that an image was published.
> On a tooling-only push the `build` job is skipped and the workflow is still
> green. Check the job list, not the tick.

---

## Publishing

`buildah bud` applies two tags:

- `:$GITHUB_SHA` — the commit tag.
- `:$BUILD_TAG`, where `BUILD_TAG="$(date -u +%Y%m%d).${GITHUB_RUN_NUMBER}"` — a
  `YYYYMMDD.<run>` tag, unique per run.

The commit tag is not durable. The nightly cron rebuilds `main`'s HEAD and
overwrites it, and those two images genuinely differ, because the desktop stack
floats on COPR HEAD and the scheduled build skips the cache. **The run tag is
what stays addressable**, which is what a rollback needs — see
[operating.md](operating.md).

`:latest` is deliberately not pushed alongside them. The order is push both tags,
sign the resulting digest, verify the signature against the in-repo `cosign.pub`,
and only then move the tag with a registry-to-registry `skopeo copy` from the
digest that was just verified, followed by an assertion that `:latest` resolves
to it. `policy.json` on the machine requires a signature for this scope, so a
`:latest` published before signing would be one the machine refuses to pull. The
signing machinery itself is [supply-chain.md](supply-chain.md).

Before any of that, the `build` job diffs the baked NEVRA manifest against the
published `:latest` (read by digest, and `continue-on-error`, so it reports into
the step summary without gating), and then smoke-tests the image: it must start,
and `/usr/libexec/workstation-configure-user-groups` must actually join a freshly
created uid-1000 account to `docker` and `input`. The smoke test runs *before*
the push, because a gate that runs after publication can only report a fact
already shipped.

> All three publishing steps gate on `if: github.event_name != 'pull_request'`
> and nothing narrower. A `workflow_dispatch` run therefore pushes, signs and
> **moves `:latest`** — including one dispatched from a branch. Pull requests
> build and smoke-test but never push.

---

## The layer cache

Builds share a companion GHCR package, `ghcr.io/<owner>/workstation-os-image-cache`.
Two independent predicates decide which half of it a given run uses:

```bash
cache_args=(--layers)
if [[ "$EVENT_NAME" != schedule ]]; then
  cache_args+=(--cache-from "$CACHE_IMAGE" --cache-ttl 25h)
fi
if [[ "$EVENT_NAME" != pull_request ]]; then
  cache_args+=(--cache-to "$CACHE_IMAGE")
fi
```

| Event | Reads cache | Writes cache |
| --- | --- | --- |
| `push` to `main` | Yes | Yes |
| `pull_request` | Yes | No |
| `schedule` | No | Yes |
| `workflow_dispatch` | Yes | Yes |

The daily build at `17 4 * * *` skips `--cache-from` on purpose: reusing the
package layer would reuse stale DNF metadata and stale packages, which is the one
thing a nightly rebuild exists to avoid. It then replaces the remote cache with
what it just built, so the next ordinary push starts from refreshed layers.
`--cache-ttl 25h` refuses any entry older than one nightly cycle, so an ordinary
push can only ever reuse layers the last scheduled rebuild produced.

This policy is itself gated. `tooling/validate/image-build` pins the literal
`--cache-from`, `--cache-to` and `!= schedule` lines, so the cache behaviour
cannot be edited away without failing CI.

---

## Lint, Renovate and Dependabot

`.github/workflows/lint.yml` triggers on push to `main`, on `pull_request` and on
`workflow_dispatch` — not on every push to every branch. It runs four checks,
each pinned:

| Check | Pin | Target |
| --- | --- | --- |
| hadolint | `ghcr.io/hadolint/hadolint:v2.14.0` | `Containerfile`, with `.hadolint.yaml` |
| `renovate-config-validator --strict` | `renovate@44.52.0` via `npx` | `.github/renovate.json5` |
| actionlint | `rhysd/actionlint:1.7.12` | every workflow |
| gitleaks | `ghcr.io/gitleaks/gitleaks:v8.30.1` | `dir . --no-banner --redact` |

Shellcheck is not here; it runs in `build.yml`'s `repo-gates` job, over the same
four trees `tooling/validate/all` scans — `tooling`, `build_files`,
`system_files/usr/bin` and `system_files/usr/libexec` — so the two cannot report
different findings on a shared file.

The Renovate check looks redundant until you consider its failure mode:

```text
# A malformed renovate.json5 fails nothing on its own: Renovate simply
# stops opening PRs, which is how the base digest pin stayed frozen.
```

Nothing goes red when the bot stops working; the pin just quietly stops moving.
The validator version is pinned by hand for a related reason — an unpinned
`--package renovate` resolved to 37.440.7 and rejected `managerFilePatterns`, a
key current Renovate requires, so a floating validator reports failures that are
its own age rather than the config's.

### Which bot bumps what

The two are partitioned so they can never touch the same line.

| Bot | Owns | Mechanism |
| --- | --- | --- |
| Renovate | `ARG BASE_IMAGE=` in the Containerfile, and nothing else | A `customManagers` regex scoped to `/^Containerfile$/`; the built-in `dockerfile` manager is explicitly `{ "enabled": false }`. Scheduled "before 6am on monday", `automerge: false`. |
| Dependabot | Literal `FROM` lines (currently the `brew` stage) and the pinned GitHub Actions SHAs | The `docker` and `github-actions` ecosystems, both weekly. |

The split exists because Dependabot's docker parser is a regex over literal
`FROM` lines. It bumps the brew stage and silently skips the base, which lives in
an `ARG` — and leaving the base to Dependabot froze it permanently. The base
digest is never automerged: `tooling/validate/source-images` cosign-verifies it,
and the NEVRA manifest diff is the only place a base change is visible before it
reaches the machine.

---

## Retention

`.github/workflows/clean.yml` runs weekly (`15 0 * * 0`) plus on demand, and
prunes both GHCR packages with `dataaxiom/ghcr-cleanup-action`:

| Package | `older-than` | `keep-n-tagged` | `keep-n-untagged` |
| --- | --- | --- | --- |
| `workstation-os-image` | 90 days | 10 | 5 |
| `workstation-os-image-cache` | 14 days | 2 | 2 |

Both also set `delete-orphaned-images: true`. The cache gets a far tighter rule
because it is regenerated on every non-PR build and referenced by nothing once
superseded.

The `keep-n` floors are the load-bearing part, not the age rule:

```text
# keep-n floors matter more than the age rule here. This repository publishes
# for one machine, so a quiet fortnight is normal -- an age-only policy would
# happily delete the only images left to roll back to.
```

This is the workflow that bounds how far back a rollback can reach: whatever
survives here is what `skopeo list-tags` returns when you go looking for a digest
to publish, and ten tagged images is the floor. Rolling back — both on the
machine and server-side via `.github/workflows/rollback.yml` — is
[operating.md](operating.md).

---

## Where to go next

[validation-and-gates.md](validation-and-gates.md) is the companion to this page:
it maps each gate named here to the thing it actually proves, and draws the line
between what a build can assert about the image and what only a live machine can
assert about itself. [supply-chain.md](supply-chain.md) picks up where the
publishing section stops — cosign, `policy.json`, key rotation and the vendored
RPM keys. For where a given change belongs before it ever reaches a build, read
[conventions.md](conventions.md), and for how a package gets declared in the
first place, [subsystems/packages.md](subsystems/packages.md).
