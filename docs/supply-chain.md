# Supply Chain and Signing

This page covers everything that decides what content is allowed to become this
image, and what a machine is allowed to install from it. Read it before you bump
a base digest, add a third-party repository, rotate a key, or capture a config
file that might contain a credential.

**Trust runs in two directions — nothing enters the build without a verified
signature, and nothing reaches a machine without one — plus a third gate that
keeps secrets from leaving the workstation into git.**

---

## Inbound: What May Become the Image

### The two pinned inputs

Every image this build consumes is pinned by digest and verified before the
build runs. There are exactly two, and they are maintained by two different
bots:

| Input | Pinned at | Bumped by |
|---|---|---|
| `ghcr.io/ublue-os/base-main` | `ARG BASE_IMAGE=` in `Containerfile` | Renovate, via a `customManagers` regex in `.github/renovate.json5` |
| `ghcr.io/ublue-os/brew` | the literal `FROM ... AS brew` line | Dependabot, via `.github/dependabot.yml` |

The split is not redundancy. Dependabot's Docker parser is a regex over literal
`FROM` lines, so it maintains the brew stage and cannot see the base, which
lives in an `ARG`. Renovate exists here for that one job, and its built-in
`dockerfile` manager is disabled so the two bots never contend for the same
line. The base pin carries the kernel, systemd, mesa and the negativo17 codec
stack, so leaving it to Dependabot froze it permanently. See
[build-and-ci.md](build-and-ci.md) for the stages themselves and how the
workflows consume them.

### cosign verification of the inputs

`tooling/validate/source-images` is the gate. Its own header states why:

```text
Both inputs are pinned by digest in the Containerfile and both are signed by
ublue. Without this gate a compromised GHCR account or a bad push lands on the
machine unremarked, and no historical build is reproducible. It is also the
only pin that holds: the desktop stack floats because COPR prunes superseded
builds, so there is nothing to versionlock there.
```

It verifies against `build_files/keys/ublue-os.pub`, the vendored ublue public
key, with `cosign verify --new-bundle-format=false`.

The gate is **default-deny**, and that shape was earned. It greps *every*
digest-pinned reference out of the `Containerfile`, then maps each registry
prefix to a vendored key through a `case` with no default branch — an unknown
prefix fails rather than being skipped. The previous version scoped its grep to
`ghcr.io/ublue-os`, so a pinned input from any other registry went unverified
while the script still printed `All source images verified.` and exited 0. That
is the assert-coverage-not-success rule in [conventions.md](conventions.md),
applied to the one gate the whole inbound chain rests on.

Each verified reference is then checked for existence with `skopeo inspect`,
because a pin to a pruned image fails the build later and more confusingly than
it fails here.

That check distinguishes *"the registry says this digest is gone"* from *"the
registry did not answer"*, and only the first is a pruned pin. It used to run as
`skopeo inspect ... >/dev/null 2>&1` and report **any** non-zero exit as
`DIGEST NO LONGER FETCHABLE -- bump the pin`, so a rate limit, a 5xx or a DNS
blip on a CI runner all read as a dead pin — with the actual error already
discarded. That fired on 2026-09-01 against a pin that was perfectly live, and
the advice it printed would have destroyed the signal the gate exists to give.

The classifier matches on the message, not the exit code, against strings
measured rather than guessed:

| skopeo says | means |
| --- | --- |
| `manifest unknown` (exit 2) | the digest is genuinely gone — fail, bump the pin |
| `bearer token: ... 403 Forbidden` (exit 1) | the repository is missing or private |
| `dial tcp: lookup ...: no such host` (exit 1) | DNS |
| `connect: connection refused` (exit 1) | the host is down |
| anything unrecognised | unanswered |

Only the first fails. Everything else is reported with its real error and
counted as unanswered, and `skopeo --retry-times 3` absorbs the blips before it
comes to that. The two ways to be wrong are not symmetric: calling a live pin
pruned invites bumping a good pin, while calling a dead pin unanswered only
defers the failure to the build — which is exactly where it landed before this
check existed.

Note what this means about the old message: `cosign verify` runs first on the
same reference and `continue`s past the skopeo check when it fails, and cosign
cannot verify a digest it cannot resolve (it exits 10 on a pruned one). The
"bump the pin" branch was therefore only ever reachable when cosign had just
resolved that digest — so it was nearly always wrong by construction.

A run with unanswered checks does not print `All source images verified.`; it
says how many went unanswered, because a check that did not run is not a check
that passed.

It runs in CI's `repo-gates` job as *Verify every input image before building on
it*, and locally from `just validate` — though only conditionally there:
`tooling/validate/all` guards it with `command -v cosign >/dev/null`, so a
workstation without cosign installed skips it silently and CI is the backstop.

### RPM signing keys

Six third-party repositories are vendored under `build_files/repos/` rather than
fetched at build time, so the package source and the `gpgkey` line are
reviewable in git: Terra, three COPRs (yalter/niri, avengemedia/dms,
avengemedia/danklinux), Docker CE and Insync.

Vendoring the repo file alone covers only half of that. If `gpgkey=` points at a
URL, the trust anchor that authenticates every package is still fetched on build
day, and the repository could hand the build whatever key it liked. So the keys
are vendored too, under `build_files/keys/rpm/`, referenced as
`gpgkey=file:///etc/pki/rpm-gpg/<name>.asc`, with provenance — upstream URL, uid
and pinned fingerprint — recorded in `build_files/keys/rpm-key-sources.json`.

`tooling/validate/image-build` fences every vendored `.repo` file four ways —
`gpgcheck=1`, a `file://` key, an `https` `baseurl` or `metalink`, and an
`includepkgs` allowlist — and refuses `config-manager addrepo --from-repofile`
anywhere in `build_files/*.sh` or the `Containerfile`.
[conventions.md](conventions.md) explains what each part of that fence prevents;
[subsystems/packages.md](subsystems/packages.md) covers which repository each
package comes from.

`tooling/validate/rpm-keys` keeps the vendored copies honest by re-fetching each
upstream key and comparing:

| Upstream state | Result |
|---|---|
| vendored fingerprint differs from the manifest | fail, `FINGERPRINT MISMATCH` |
| bytes identical to upstream | pass |
| bytes differ, fingerprint unchanged | pass, noted as re-armoured |
| fingerprint changed upstream | fail, `UPSTREAM KEY ROTATED` — review it, then update the key and the manifest |
| upstream unreachable | the drift check is skipped, so an offline build still works |

A key rotating upstream therefore becomes a failure to review rather than a
silent change in what the build trusts. On the built image,
`build_files/99-check-build.sh` separately asserts that all six vendored keys
actually shipped to `/etc/pki/rpm-gpg/`.

### The Terra release footgun

Terra signs per Fedora release, and that is the one thing a fingerprint check
cannot catch. `build_files/repos/terra.repo` follows the release automatically
through its metalink:

```ini
metalink=https://tetsudou.fyralabs.com/metalink?repo=terra$releasever&arch=$basearch
```

The key does not follow. `build_files/keys/rpm/terra.asc` is pinned to **Fedora
44** twice over — by its source URL, `https://repos.fyralabs.com/terra44/key.asc`,
and by its own uid, `Terra 44 <security@fyralabs.com>`. The base is tagged
`:latest`, so the day base-main moves to F45 the repository follows and the key
does not. Nothing else in the tree would notice: Renovate only manages the
`Containerfile`, and the fingerprint check compares the key against the
manifest, which would still agree with itself.

So `99-check-build.sh` reads the release number out of the shipped key's uid and
asserts it equals the image's `VERSION_ID` from `/usr/lib/os-release`. Moving the
base to Fedora N means re-vendoring the key from
`https://repos.fyralabs.com/terra<N>/key.asc` and updating
`build_files/keys/rpm-key-sources.json` in the same change.

### The one stated gap

negativo17's repository file comes from base-main and still fetches its key over
the network. That file is not ours to rewrite — doing so would collide with
future base updates — so `build_files/90-cleanup.sh` exempts it by name when it
deletes every repository the build added, then disables it again in the shipped
image. The chain still has a defined root: base-main is digest-pinned and
cosign-verified before anything is built on it, so that key is trusted
transitively rather than unconditionally.

---

## Outbound: What a Machine May Install

Published images are signed with cosign and the machine is configured to require
that signature. Three pieces have to line up on the machine — a trusted key, a
`policy.json` entry that names it, and a `registries.d` entry telling
containers/image to fetch the signature at all — and the third is the one whose
absence looks like success.

### CI signs the digest, then verifies it

`cosign.pub` at the repository root is the public half.
`system_files/etc/pki/containers/workstation-signing.pub` is the same key shipped
into the image, and `tooling/validate/image-build` runs `cmp -s` on the pair — a
half-finished rotation that updates one file keeps CI green while locking every
machine out of its own updates.

The build workflow pushes `:$GITHUB_SHA` and the dated build tag but
deliberately not `:latest`. It then resolves the pushed digest with `skopeo`,
signs **the digest rather than the tag** (a tag can move; a digest cannot) with
`cosign sign -y --new-bundle-format=false --use-signing-config=false`, and
immediately verifies the result against the in-repo public key:

```bash
cosign verify --new-bundle-format=false --key cosign.pub "$IMAGE_REF@$digest"
```

A key or format mismatch therefore fails the job rather than publishing
something the machine will refuse to pull. `--new-bundle-format=false` is
required because bootc and rpm-ostree read the legacy simple-signing
attachment, not the new bundle format.

Only then is `:latest` moved, by `skopeo copy` from the signed digest — not by a
second push, which would produce the same digest by construction rather than by
definition — and the workflow re-reads `:latest` afterwards to prove it resolves
to the digest that was signed. Signing before moving the tag is the point: the
machine's policy requires a signature for this scope, so a failure between push
and sign would otherwise leave a published `:latest` that the updater refuses to
pull, and the machine stuck until the next green build.

### The policy.json entry

`build_files/40-signing.sh` merges a `sigstoreSigned` entry for
`ghcr.io/${REPO_ORGANIZATION}` into the deny-by-default `policy.json` that
base-main ships:

```json
{
  "type": "sigstoreSigned",
  "keyPaths": ["/etc/pki/containers/workstation-signing.pub"],
  "signedIdentity": { "type": "matchRepository" }
}
```

It merges rather than replaces, because dropping base-main's own
`ghcr.io/ublue-os` entry would leave the machine unable to pull its own base.
The script validates the result with `jq -e` before installing it — the
top-level default is still `reject`, our scope is present, the ublue entry
survived — because a `policy.json` the machine cannot parse means it can pull
nothing at all, including a rollback. `99-check-build.sh` re-asserts all of that
on the built image, and additionally resolves the ublue entry's `keyPaths` to
real files rather than assuming them.

The top-level default is `reject`, but every transport also inherits a `""`
catch-all of `insecureAcceptAnything` from base-main, left alone on purpose: the
`docker` one is what lets dev containers pull arbitrary images, and
`containers-storage` is what makes `just build` output usable locally.

### The registries.d entry

`/etc/containers/registries.d/workstation-signing.yaml` sets
`use-sigstore-attachments: true` for the owner-scoped registry path.

> Without this file the signature is never fetched, so `policy.json` has nothing
> to check. It is the piece whose absence looks like signing works, right up
> until it does not.

`40-signing.sh` generates it from `image.env` rather than shipping it, since its
only content is the owner-scoped registry path and a static file would be one
more place a fork must edit. Being generated, it is not under `system_files/`,
so `tooling/audit/etc-drift` adds it to the image-owned list by hand — see
[validation-and-gates.md](validation-and-gates.md) for what that audit covers.
`99-check-build.sh` asserts both that the file is scoped to this image's
registry path and that the attachment flag is set.

### The update button's polkit grant

The desktop shell's update button runs `systemctl start uupd.service`, and
`system_files/usr/share/polkit-1/rules.d/10-workstation-uupd.rules` grants
exactly that and nothing more. It is scoped three ways, each verified against
systemd's own polkit call site (`bus_verify_manage_units_async_impl`):

| Condition | Effect |
|---|---|
| `action.lookup("unit") == "uupd.service"` | one unit, not every unit |
| `action.lookup("verb") == "start"` | start only — not stop, restart, reload or kill |
| `subject.isInGroup("wheel") && subject.local && subject.active` | a physically present admin session, not an SSH one |

The action's own default is `auth_admin_keep`, so everything the rule does not
match still prompts. What it replaced was `sudo bootc upgrade` as the shell's
update command, which either needs passwordless sudo or fails silently from a
GUI with nowhere to type a password.

That is one mechanism spanning two files, so `99-check-build.sh` gates that they
agree: it asserts the rule still scopes to `uupd.service` and to the `start`
verb, and that the shipped DMS seed's `updaterCustomCommand` is still exactly
`systemctl start uupd.service`. If they drift, the button silently prompts for a
password nobody can answer. [operating.md](operating.md) covers uupd itself and
the nightly timer that runs it unattended.

### Rotating the signing key

The policy entry is a `keyPaths` array — the same shape base-main uses for its
own `ghcr.io/ublue-os` entry, which carries `ublue-os.pub` plus
`ublue-os-backup.pub` — so rotation takes two releases and never a flag day. A
machine that trusts only the old key must already trust the new one *before*
anything is signed with it, or it cannot pull the release that would have taught
it.

1. Generate the new pair. Commit the new public half into
   `system_files/etc/pki/containers/` as `workstation-signing-backup.pub`,
   leaving the old `workstation-signing.pub` in place and still the signer. Ship
   it. `40-signing.sh` picks the backup file up automatically and every machine
   now trusts both keys.
2. Once every machine has booted that image, swap the files so the new key is
   `workstation-signing.pub` (and `cosign.pub`, which `tooling/validate/image-build`
   requires to match byte for byte), update the `COSIGN_PRIVATE_KEY` and
   `COSIGN_PASSWORD` repository secrets, and delete the backup.

Confirm which keys a deployment actually trusts before step 2:

```bash
jq '.transports.docker' /etc/containers/policy.json
```

### Enforcement is a one-time switch

Signing changes nothing on the host by itself: a deployment whose origin is
`ostree-unverified-registry:` ignores `policy.json` entirely.

```bash
sudo bootc switch --enforce-container-sigpolicy \
  ghcr.io/marcortola/workstation-os-image:latest
```

`rpm-ostree status` then shows an `ostree-image-signed:` origin, and any future
update whose signature does not verify is refused rather than deployed.

> Do this only after a signed image has been published, or the switch has
> nothing valid to pull.

---

## The Secret Boundary

The third direction is what leaves the workstation and enters git. Captured
personal configuration is the exposure, because the AI CLI config files hold
credentials and per-project context that this public repository must never
carry.

### Scrub filters make the seeds secret-free by construction

Two manifest entries in `tooling/data/dotfiles.manifest` use the `scrub` kind,
whose fourth column names a filter under `tooling/scrub/`. `tooling/dotfiles/sync`
pipes the live file through that filter on every capture, so the committed seed
is reproducible *and* secret-free by construction rather than by review:

| Filter | Live file | What it removes |
|---|---|---|
| `tooling/scrub/claude-settings` | `.claude/settings.json` | `env` (Help Scout app id and secret), `enabledPlugins` and `extraKnownMarketplaces` (absolute install paths, work-specific), `hooks`, and `autoMode.environment` |
| `tooling/scrub/codex-config` | `.codex/config.toml` | every table, replaced by one canonical credential-free MCP table; machine-local `[projects.*]` trust tables and `[tui.*]` state never reach git |

`autoMode.environment` is the sharpest of these. Claude Code rewrites it per
project with organisation names, private repository names, secret names,
internal domains and cloud services. It regenerates constantly, and no generic
scanner recognises any of it as a secret.

`tooling/audit/personal-config` runs the same filters before comparing, so drift
is measured against the scrubbed shape rather than the live one. Never revert
these entries to a plain `copy`. [subsystems/ai-clis.md](subsystems/ai-clis.md)
covers the config machinery itself, and [capturing-changes.md](capturing-changes.md)
the capture workflow.

### The scanner allowlist

`.gitleaks.toml` is the sole scanner allowlist in this repository. It extends
gitleaks' default ruleset rather than replacing it, and allowlists exactly one
false positive: the keyd source tarball's SHA-256 pinned in the `Containerfile`.
gitleaks' `generic-api-key` rule matches it only because the `ARG` name contains
"key" — from "keyd" — next to a high-entropy value. It is a public build
checksum, not a secret.

`gitleaks dir .` does not respect `.gitignore`, so anything left in the checkout
is inside the scan surface. Keep scratch files out of the tree; `just clean`
removes the known byproducts and deliberately goes no further than `.gitignore`
already does.

### Fix the input, never the check

Never weaken, delete, or add an exception to a `tooling/validate/` assertion or a
`tooling/scrub/` filter to make a run pass. If a gate is genuinely wrong, say so
and stop.

This matters more here than anywhere else in the repository, because gitleaks
misses the tool-specific key shapes the AI CLIs use — the dash-broken context7
key is one it does not flag at all. The hand-written positive gates in
`tooling/validate/sources` are the real secret boundary: they assert the
committed seeds carry no `env` block, no Help Scout identifier, no absolute home
path, no unapproved MCP table, and that the tracked context7 fragment's API key
is a `{file:}` or `{env:}` placeholder rather than a literal. They read the
committed seeds rather than the live files, so they run in CI, where no live
file exists and a comparison-based check would have nothing to do.

If you find a secret in a live file or a diff, stop. Do not echo the value and
do not commit it; report the path only.

### Reporting a vulnerability

[SECURITY.md](../SECURITY.md) carries the routing and the in-scope definition.
The short version: almost every CVE in a scan of the published image belongs to
Fedora, the ublue base or a third-party package, and should be reported to that
project's tracker. What is in scope here is the build and trust machinery — any
way to get unreviewed content into the published image, weaken or bypass the
signature chain, extract a secret from CI, or make one of the gates in
`tooling/validate/` pass while the condition it asserts is false.

---

## Where to go next

[build-and-ci.md](build-and-ci.md) covers the Containerfile stages that consume
the pinned inputs and the workflows that run the signing steps, including how
the `:latest` tag and the retention policy interact with a rollback.
[validation-and-gates.md](validation-and-gates.md) places each gate on this page
in the wider map of what proves the image versus what proves the machine.
[forking.md](forking.md) is the checklist for a fork; the signing scope is
derived from `image.env`, so your own identity and your own cosign pair are part
of it.
