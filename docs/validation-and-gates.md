# Validation and Gates

There is no application code here to unit-test. Correctness is asserted by
**gates** instead: assertions that run inside the image build, in CI, and
against the live workstation. Almost every one of them exists because its
absence let a real regression ship silently, and that failure is written into
the script as a comment. This page says which gate proves what, where it runs,
and why none of them may be weakened to make a run pass.

**The build gates assert the IMAGE; the `tooling/audit/` scripts assert the
MACHINE — and only the audits can see a local override, because `/etc` is a
three-way ostree merge and a mask or a rewrite there outlives every upgrade.**

---

## Two things to prove, two places to prove them

An image gate can prove that a preset line produced its `/etc` symlink at build
time, that a spawned binary exists, that the polkit rule and the command it
authorises still name the same unit. It proves those things about a filesystem
that has never booted.

The machine is a different artifact. `/etc` is a three-way ostree merge: what
lands there on first deploy becomes machine-local, and a later image version of
the same file is then ignored, silently. Nothing in the build can see that. The
mechanism itself is documented in [conventions.md](conventions.md); what matters
here is that it creates a class of defect no build-time check can reach, and two
audits exist specifically to cover it.

`tooling/audit/units` carries the case that justified it, in its own header:

```text
uupd.timer was found masked here via /etc/systemd/system/uupd.timer ->
/dev/null while the preset line and the timers.target.wants symlink underneath
it were both intact, which is exactly why the build-time gate could not see it.
```

`tooling/audit/etc-drift` carries the other:
`/etc/greetd/niri/config.kdl` had been frozen at its 2026-07-10 state since
`dms greeter install` rewrote it, so a later image that added `optional=true` to
its `dms.kdl` include never reached the machine. That file sits on the path
whose failure costs a graphical login, and the image was fine the whole time.

Both scripts say so in their own headers. `tooling/audit/workstation` marks the
boundary inline, immediately before it calls them:

```bash
# Machine-state, not image-state: /etc is a three-way merge and a local mask or
# rewrite outlives every upgrade, so nothing in the build can assert either.
```

The same asymmetry applies outside `/etc`. The Homebrew prefix lives under
`/var/home`, so it is in no layer at all: `tooling/audit/packages` is the only
thing that looks at it, which is how an inert 721-byte `brew-proxy` wrapper
survived a base swap sitting where the image ships a symlink.

---

## Running them

| Command | Runs | Needs |
|---|---|---|
| `just validate` | `tooling/validate/all` | a workstation booted into this image |
| `just audit` | `tooling/audit/workstation` | a workstation booted into this image |
| `just audit-diff` | the same audits with `--diff`, printing the full chezmoi diffs | same |
| `just build` | the image build, ending in `99-check-build.sh` then `bootc container lint --fatal-warnings` | podman |

Every gate script is directly runnable on its own, which is the fast way to
iterate on one. `tooling/audit/workstation` takes two flags and forwards both to
`tooling/audit/dotfiles`, the only audit that reads them: `--diff`, which
`just audit-diff` passes, and `--strict`, which no recipe passes and which
promotes the informational DMS clipboard diff from a report to a failure.

Where the gates sit in the change workflow — audit, capture, sync, validate — is
[capturing-changes.md](capturing-changes.md).

---

## The image gates: `build_files/99-check-build.sh`

Run as the last command of the main `RUN` chain in the Containerfile, so
`just build` reaches it as well as CI. Its own header states the split from
`bootc container lint`:

```text
The existing checks verify that files parse. These verify that the build's
DECISIONS took effect -- which repo a package came from, whether a preset
actually enabled a unit, whether a sed matched anything.
```

| Class | What it asserts |
|---|---|
| Packages present | `rpm -q` over an explicit list: niri, xwayland-satellite, greetd, foot, fish, chezmoi, the DMS stack, Docker, PipeWire, firewalld and the rest |
| Vendor provenance | niri from yalter, dms and quickshell from avengemedia, uupd from Terra, systemd and dnf5 from Fedora Project; `libavcodec-freeworld` absent |
| DMS version cohesion | dms, dms-cli and dms-greeter carry the same `%{VERSION}`; they ship from two separate COPRs, so a half-finished publish otherwise hands the machine a shell that starts and then misbehaves |
| niri parses | `niri validate` on the greeter chain and on `workstation.kdl` |
| greetd chain | `config.toml` launches `dms-greeter --command niri` as `user = "greeter"`, the greeter niri config sets `DMS_RUN_GREETER`, the sysusers entry exists |
| PAM keyring | the unguarded sed in `30-desktop.sh` actually normalised the auth and session lines, no dashed line survived, and `pam_gnome_keyring.so` is installed at all |
| Preset effects | greetd is `display-manager.service`, `uupd.timer` is enabled, `rpm-ostreed-automatic.timer` and `dnf-makecache.timer` are not, `ublue-os-update-services` is absent, the two brew timers are not enabled, `dms.service` is enabled for the user |
| Preset coverage | every `enable` line in both preset files produced a link under `/etc`, matched by link target or link name; `default.target` is `graphical.target` |
| Unit syntax | `systemd-analyze verify` over the `workstation-*` units plus fcitx5, iio-niri, udiskie and dsearch; `systemd-tmpfiles --dry-run --create`; `systemd-sysusers --dry-run` |
| `ConditionUser` coverage | every non-`workstation-*` unit the user preset enables has a drop-in setting `ConditionUser=!@system`, or it also runs in the greeter's user manager against a read-only home |
| Greeter theme links | every `/var/cache/dms-greeter` line in `99-workstation-dms-greeter.conf` is `L+`, not plain `L`, and its target exists. Derived from the tmpfiles file, so the gate and the mechanism cannot disagree; plain `L` would leave a runtime repoint in place, and a repoint at an account's own file is what once made a graphical login depend on that file's mode |
| Homebrew | `/usr/share/homebrew.tar.zst` is non-empty and `brew-setup.service` shipped |
| Fonts | `fc-list` resolves FiraCode Nerd Font Mono, which both `fonts.conf` and the DMS mono setting name; and the Cambria substitution holds end to end — the Caladea package, its `30-0-` alias rule under `/etc/fonts/conf.d`, the font files in `fc-list`, and `fc-match Cambria` actually landing on Caladea |
| niri spawn targets | every `spawn "..."` in the shipped includes resolves to an executable — `niri validate` never checks this, which is how `spawn "zocr"` survived a base swap |
| Signature configuration | the signing pubkey shipped and is a public key, `policy.json` defaults to `reject`, the scope entry is `sigstoreSigned` against that key path, the ublue-os entry survived and the key it names resolves, and `registries.d` is scoped and sets `use-sigstore-attachments: true` |
| Accounts left `/etc` | `/etc/passwd` holds only root, `/etc/group` only root and wheel, greetd/greeter/wsdd reached `/usr/lib/passwd`, those plus docker reached `/usr/lib/group`, no shadow-utils leftovers shipped |
| RPM trust anchors | the six vendored keys are on disk under `/etc/pki/rpm-gpg` |
| Shipped chezmoi source | the tree shipped, and `chezmoi apply --dry-run` into a throwaway `HOME` succeeds against the copy the machine will actually run |
| Image identity | `VARIANT_ID` matches `image.env`'s `IMAGE_NAME`, and `ID` is still `fedora` |
| Update grant | the polkit rule scopes to `uupd.service` and the `start` verb, and the shipped `dms-settings.json` sets `updaterCustomCommand` to `systemctl start uupd.service` |
| Compat symlinks | `/opt /bin /sbin /lib /lib64 /media /root /home` are all still symlinks; an overlay path under any of them replaces one with a real directory and `bootc container lint` passes on the result |
| Terra key release | the release number in the Terra key's uid equals `VERSION_ID`; `terra.repo` follows `$releasever` and the key does not, so a base moving to a new Fedora silently desynchronises them |
| Default terminal | `xdg-terminal-exec` resolves `workstation-footclient.desktop` **and** the printed command line still carries `--app-id` and `--title` |
| Launcher hygiene | `btop.desktop`, `foot-server.desktop` and `org.fcitx.Fcitx5.desktop` are gone, and the fcitx5 entries Fedora hides keep `NoDisplay=true` |
| Install defaults | `/usr/lib/bootc/install/00-workstation.toml` still selects btrfs, so `bootc install to-disk` reproduces this machine's filesystem |
| Session environment | `50-workstation-input-method.conf` carries the four IM variables, `GTK_IM_MODULE` stays empty, and the font drop-in exists |
| DMS CLI policy | `greeter install`, `greeter enable` and `setup` are in `blocked_commands`, because `dms greeter install` clobbered image-owned `/etc/greetd/config.toml` once already |
| Config validators | `dockerd --validate` on the factory `daemon.json`, `keyd check` on the factory `default.conf` |
| Namespace | no image-owned file references `/usr/share/zirconium` and the tree does not exist |

Two of these deserve their reasoning spelled out, because the obvious version of
the check is the one that failed. The terminal gate asserts the resulting
command line rather than which desktop entry resolves — asserting resolution is
exactly the check that passed while `xdg-terminal-exec` silently discarded
`--app-id` and `--title`, landing the herdr, dev-terminal and lazydocker binds
all as app-id `foot`. And both preset gates assert the *effect* rather than the
preset text. Coverage asserts that each `enable` line produced a link, which
also catches a preset line naming a unit that does not exist at all. Effects
asserts the negative cases by name, because a preset file cannot remove an
enablement symlink another layer already wrote: base-main uses `systemctl
enable` for its update timers, so `50-services.sh` has to call `systemctl
disable` on `rpm-ostreed-automatic.timer`, `dnf-makecache.timer` and the two
brew timers explicitly, and the gate is what proves those calls still land.

---

## The repository gates: `tooling/validate/`

| Gate | Asserts | Where | Absent |
|---|---|---|---|
| `all` | umbrella. Runs the five repo gates below, shell and Lua and fish syntax, hadolint, actionlint, gitleaks, the DMS/JetBrains/AI/manifest gates, a git-seed resolution test, `tooling/audit/workstation`, `foot --check-config`, and a `chezmoi managed` target list | local only (`just validate`) | the live half of the suite runs nowhere |
| `repo` | scan roots exist; no reference to the removed `/usr/share/zirconium` tree; every absolute `/usr/share/workstation-os-image/...` path named anywhere in the repo is actually shipped; at least 87 dotfile seeds; the seed tree dry-applies to an empty `HOME`; both niri chains and the greeter config parse | CI `repo-gates` and local | a half-finished rename ships four dangling references and a seed tree that no longer applies |
| `sources` | `CLAUDE.md` is exactly `@AGENTS.md`; `AGENTS.md` stays under its 279-line cap and `README.md` under its 170-line cap; at least 15 pages exist under `docs/` and at least one agent command under `.claude/commands/`; every `just`/`wjust` recipe and every `system_files/`, `build_files/`, `tooling/` or `docs/` path cited in `AGENTS.md`, `README.md`, every `docs/**/*.md` and `.claude/commands/*.md` exists; every relative link in those same files resolves, a same-file anchor matches a real heading, and a cross-file anchor is rejected outright; the AI seeds carry no key, plugin identifier or absolute home path; the worktree wiring is intact; every tracked JSON, TOML and YAML parses; shipped scripts use one of two shebangs | CI `repo-gates` and local | policy prose rots into dangling pointers, and the tool-specific secret shapes gitleaks misses go uncaught |
| `image-build` | the base and brew inputs are digest-pinned and the base is one full reference; the `ctx` stage and the COPY lines are present; `bootc container lint --fatal-warnings` is invoked; `cosign.pub` matches the shipped signing pubkey byte for byte; the Containerfile ARG defaults match `image.env`; no `COPY build_files/`; packages install before volatile config; no build step mutates the chezmoi source; the keyd and FiraCode checksums are pinned; every vendored repo sets `gpgcheck=1`, a `file://` key, an https source and `includepkgs`; the workflow's cache flags are intact; `.containerignore` still allowlists the three build inputs | CI `repo-gates` and local | a floating pin, an unfenced third-party repo, or a half-finished key rotation that keeps CI green while locking machines out of their own updates |
| `source-images` | every digest-pinned reference in the Containerfile is cosign-verified against a vendored key, default-deny by registry prefix, and the digest is still fetchable | CI `repo-gates` and local, guarded on `command -v cosign` | a compromised upstream push lands on the machine unremarked. See [supply-chain.md](supply-chain.md) |
| `rpm-keys` | each vendored RPM key matches the fingerprint pinned in `build_files/keys/rpm-key-sources.json`; a key that rotated upstream fails the gate, while an unreachable source is skipped so an offline run still passes | CI `repo-gates` and local | the trust anchor under every vendored repo changes without review |
| `lint-nvim-seeds.lua` | helper, not a standalone gate: `loadfile` compile-checks each Neovim Lua seed, the Lua analog of `bash -n` | local only, driven from `all` through the image's own Neovim | a syntax error in a seed reaches the machine |

`tooling/validate/repo` runs in CI but stops early there and says so out loud —
on a runner with no `chezmoi` and no `niri` it prints
`Repository gates passed (niri/chezmoi absent: their gates run against the
image).` rather than passing silently. Those two halves are covered instead by
`99-check-build.sh` inside the built image, which ships both binaries.

`tooling/validate/all`, `repo` and `sources` all install the same ERR trap,
because several assertions are bare `[[ ]]` with no message and used to exit 1
printing nothing at all:

```bash
trap 'echo "FAILED ${BASH_SOURCE[0]}:${LINENO}" >&2' ERR
```

---

## The machine audits: `tooling/audit/`

`tooling/audit/workstation` is the driver. It runs seven audits, keeps going
after a failure, and aggregates their exit statuses; `dotfiles` fans out into
three more plus a live `niri validate`.

| Audit | Asserts | Absent |
|---|---|---|
| `workstation` | driver for the seven below | nothing collects the machine-side signals |
| `deployment` | the booted image origin matches `image.env`; the deployment is not `unlocked`; there are no rpm-ostree package layers, removals or replacements. Reports Secure Boot state, any staged deployment, and a booted reference that is not `ostree-image-signed:` | local package layers and an unverified booted reference accumulate invisibly, and the repository stops describing the machine |
| `units` | every `enable`/`disable` line in both preset files against live `systemctl is-enabled`; any failed unit that is image-owned; and, for image-owned units whose failed state has been cleared, an `ExecMainStatus` that says the last run exited non-zero and nothing has succeeded since | a local `systemctl mask` survives every upgrade with the build-time gate still green, and a `systemctl reset-failed` turns a unit that never worked into a clean audit |
| `etc-drift` | every file under `system_files/etc`, plus the `registries.d` fragment `40-signing.sh` generates, compared byte for byte against `/usr/etc` | a locally rewritten `/etc` file freezes forever and every later image version of it is ignored |
| `greeter` | every `/var/cache/dms-greeter` link the tmpfiles file declares is a symlink to the image-owned default, and that default is world-readable through a world-traversable path — readability as uid `greeter` experiences it, checked without needing root | a link repointed at account state survives, and the first sign of it is a text console at the next boot |
| `updates` | `uupd.timer` is enabled and active, `uupd.service`'s last `Result` is success, and no record above INFO appears in the last invocation | nothing updates the machine, or a module fails behind uupd's single generic notification title |
| `packages` | the brew prefix still ships `bin/brew` as a symlink; installed formulae and casks against the Brewfile, formulae minus the image-provided shadows; `brew bundle check`. An undeclared Flatpak is reported as a warning, not a failure, because a workstation may keep host-only Flatpaks | undeclared tools accumulate, and a rewritten brew prefix flips `ConditionPathIsSymbolicLink` on ublue's brew timers |
| `dotfiles` | driver: `personal-config`, a chezmoi diff of the managed niri scaffolding (critical) and of the DMS clipboard preferences (informational), `dms-settings`, the hashes of any `local.kdl`, `niri-binds`, and `niri validate` on the effective config | captured personal config silently diverges from the live machine |
| `personal-config` | every entry in `tooling/data/dotfiles.manifest`, live file against repo seed, per kind — `scrub` entries are filtered first so stripped secrets are not reported as drift, `scaffold` entries are image-owned and skipped | the manifest stops being an inventory of anything |
| `dms-settings` | the captured overlay applied to a copy of live settings reproduces live settings, and `tooling/dms/capture --list` reports no `[new]` portable deviation | reviewed GUI preferences never become workstation defaults. See [subsystems/desktop-session.md](subsystems/desktop-session.md) |
| `niri-binds` | `local.kdl` is the last include; no bind in the system `binds.kdl` is shadowed by the DMS-generated fragment; `maximize-column` is reclaimed | DMS silently takes keys the system config also binds, and `niri validate` still exits 0 |

Two exit codes carry meaning in `dotfiles` and its children: 1 is drift, 2 is a
broken prerequisite — a missing `chezmoi` or `niri`, an absent image source
tree, a chezmoi comparison that failed to run, an unreadable bind source, an
unknown manifest kind. Treat a 2 as "the audit did not happen", never as
"nothing diverged".

Reporting drift honestly means enumerating the divergent items, not the summary
counts, and reporting both kinds: tracked items whose live value moved away from
their captured baseline, and items not tracked at all. [AGENTS.md](../AGENTS.md)
spells out why the first kind is easy to miss: a `--list`-style tool may compare
against upstream defaults rather than against your own captured baseline.

---

## What CI can and cannot reach

Four jobs in `.github/workflows/build.yml`: `image-inputs`, `repo-gates`,
`dms-settings-tests`, and `build`, which `needs` the other three and runs only
when `image-inputs` reports `changed == 'true'`. The tags, cache and publish
mechanics are [build-and-ci.md](build-and-ci.md); what belongs here is the reach.

`build.yml` is not the whole CI surface. `.github/workflows/lint.yml` runs four
checks on push to `main`, on `pull_request` and on `workflow_dispatch` —
hadolint, `renovate-config-validator --strict` under a pinned
`renovate@44.52.0`, actionlint, and gitleaks — each pinned to an exact version,
because a silent version rollover presents as a new finding on an unchanged
tree. `tooling/validate/all` runs the same hadolint, actionlint and gitleaks
locally, so the two surfaces cannot diverge.

`repo-gates` runs exactly the gates that need no live workstation:
`tooling/validate/repo`, `tooling/validate/image-build`,
`tooling/validate/sources`, `tooling/validate/source-images`,
`tooling/validate/rpm-keys`, `just --fmt --check --unstable`, `just --list`, a
check that `IMAGE_REF` and `image.env` agree, and shellcheck from a pinned
container. `tooling/validate/all` is never invoked, and the split is deliberate.
`tooling/validate/repo` states it in its own header:

```text
Split out of tooling/validate/all so CI can run them: validate itself ends in
audit-workstation and a live `chezmoi managed`, which need the machine to be
booted into this image, so it can only ever run locally.
```

`tooling/validate/sources` states the complement:

```text
Anything needing the live machine (DMS overlay, JetBrains, foot, chezmoi
against $HOME, audit/workstation) deliberately stays in validate/all.
```

The workflow step itself names the third case — gates that need only `just`, and
were unreachable in CI purely because they happened to live in `all`:

```yaml
# Formatting and parse of the Justfile. These live in
# tooling/validate/all, which needs the live workstation, so CI never
# reached them -- and just is already on PATH here for the recipe gate.
```

So the machine audits are never a CI signal. Nothing in a pull request can tell
you that this workstation has a masked timer or a rewritten `/etc` file. That is
what `just audit` is for, and why it is a step in the change workflow rather
than an optional extra.

### The DMS fixture

`tooling/dms/defaults` reads the DMS settings schema from the installed shell:

```bash
spec=${DMS_SETTINGS_SPEC:-/usr/share/quickshell/dms/Common/settings/SettingsSpec.js}
```

Every DMS gate goes through it — `tooling/dms/validate-overlay` and
`tooling/dms/capture` both shell out to it — so on a runner with no DMS
installed the whole lifecycle test would exit 2. `tooling/fixtures/dms-settings-spec.js`
is the substitute: a minimal `SPEC` object modelling only the keys the capture
and validation paths exercise. The `dms-settings-tests` job points the variable
at it:

```yaml
env:
  DMS_SETTINGS_SPEC: ${{ github.workspace }}/tooling/fixtures/dms-settings-spec.js
```

The fixture is deliberately minimal, and its own comment says why: a new
assertion against a real schema key has to add that key here first, which keeps
the fixture honest instead of letting it drift into a second schema.

---

## Shared helpers

| File | Provides |
|---|---|
| `tooling/lib/dotfiles.sh` | the mapping between a `create_`-prefixed chezmoi seed and its live file, and the JetBrains allowlists, denylist and product resolver ([capturing-changes.md](capturing-changes.md) owns what those select). Sourced by ten scripts including `tooling/audit/personal-config`, `tooling/dotfiles/validate-manifest` and `tooling/jetbrains/validate`, so one allowlist backs capture, apply, audit and validation alike, and a gate cannot disagree with the tool it is gating |
| `tooling/lib/jetbrains-xml-flatten.py` | flattens a JetBrains XML settings file into sorted canonical key lines, one deterministic line per element, so attribute order and whitespace do not register as divergence under plain `diff`. Used by `tooling/jetbrains/diff` (`just jetbrains-diff`) |
| `tooling/fixtures/dms-settings-spec.js` | the stand-in DMS schema described above |

---

## How a gate is written

Five rules, each recovered from a gate that once passed while the thing it
checked was broken.

**Assert coverage, not success.** A loop fed by process substitution over a
missing file iterates zero times and reports that everything holds.
`99-check-build.sh` and `tooling/validate/sources` both define a `require_file`
helper for that reason, and `tooling/audit/units` asserts its two preset inputs
inline before reading them:

> `while read ... done < <(sed FILE)` on a missing FILE iterates zero times and
> passes, so a rename silently disarms the check instead of breaking it —
> exactly how the `image/` restructure disabled two gates in
> `tooling/validate` without anything going red.

The same failure shape appears without loops. `tooling/validate/repo` asserts
its scan roots exist before grepping them, because a moved tree makes `grep`
write to stderr and the gate pass without reading anything — the same
restructure shipped four dangling references that way. And
`tooling/validate/source-images` was rewritten to default-deny by registry
prefix after scoping its match to `ghcr.io/ublue-os` left any other pinned input
unverified while the script printed "All source images verified" and exited 0.

**When a mechanism spans two files, gate that they agree.** The polkit rule and
the `updaterCustomCommand` it authorises. The Containerfile ARG defaults and
`image.env`. `cosign.pub` and the signing key under `system_files/`. The
workflow's `IMAGE_REF` and `image.env`'s `IMAGE_NAME`. Each pair drifts silently
otherwise, and in every case the visible symptom lands somewhere far away from
the edit that caused it. The stronger move, where it is available, is to delete
one of the copies: `50-services.sh` derives its `systemctl preset` arguments
from the preset files, and `tooling/audit/units` reads the same two files as its
manifest, so all three agree by construction rather than by assertion.

**Assert the effect, not the arguments.** Related, and stricter. Checking that a
preset file names a unit proves nothing about whether the unit got enabled;
checking that a symlink to it exists under `/etc` does. Checking which desktop
entry `xdg-terminal-exec` resolves proves nothing about the arguments it
forwards; printing the command line does.

**Put the gate where it can actually fire.** The `gpgkey=file://` assertion once
lived in `99-check-build.sh` against `/etc/yum.repos.d`, where `90-cleanup.sh`
had already deleted every file it iterated over — all six iterations hit
`continue`. It now runs source-side in `tooling/validate/image-build`.

**Make the failure name itself.** The ERR trap in the three big scripts, `fail()`
in `99-check-build.sh`, and the standing rule in that file never to use `grep -q`
inside a pipeline: it exits on first match, SIGPIPEs the writer, and `pipefail`
turns that into a failure precisely when the thing being checked for is present.

---

## Fix the input, never the check

> Never weaken, delete, or add an exception to a `tooling/validate/all`
> assertion or a `tooling/scrub/` allowlist to make a run pass. gitleaks misses
> tool-specific key shapes, so those hand-written gates are the real secret
> boundary. If a gate is genuinely wrong, say so and stop.

This is not a style preference. [SECURITY.md](../SECURITY.md) treats it as a
vulnerability class in its own right: a report is in scope if it describes a way
to "make one of the gates in `tooling/validate/` pass while the condition it
asserts is false". Editing the gate to match broken input does that by hand.

Two corollaries. A raised threshold needs a reason attached in the
same commit — the 279-line cap on `AGENTS.md` in `tooling/validate/sources`
carries its own history of every rise, precisely so each one stays deliberate.
And a gate that is genuinely wrong is a change to propose, not a change to make
mid-run: the whole point of the rule is that the moment you most want the
exception is the moment you are least able to judge it.

---

## Environmental failures, not regressions

`just validate` needs DMS installed. It calls `tooling/dms/validate-overlay`
unconditionally, that calls `tooling/dms/defaults`, and `defaults` exits 2 when
the schema is unreadable:

```bash
[[ -r $spec ]] || {
    echo "DMS settings schema is unavailable: $spec" >&2
    exit 2
}
```

On a machine where `/usr/share/quickshell/dms/Common/settings/SettingsSpec.js`
is absent, that is the environment talking, not a repository regression. Setting
`DMS_SETTINGS_SPEC` to the CI fixture reproduces what the runner does, though
the fixture models only a handful of keys and is not a substitute for the real
schema when auditing live settings.

Several other gates degrade rather than fail when their prerequisite is missing.
The audits all say so on stdout: `tooling/audit/deployment` prints "unavailable
outside an rpm-ostree host"; `tooling/audit/etc-drift` prints "unavailable
outside an ostree host"; `tooling/audit/units` and `tooling/audit/updates` print
"unavailable without systemd". `tooling/validate/all` is the exception. It skips
`source-images` without `cosign` and the Neovim Lua check without `nvim`, and
neither skip prints anything, so nothing in the output distinguishes a run that
verified the input images from one that did not. A skipped gate that announces
itself is a known gap. A skipped gate that prints nothing, and then a success
line, is the bug this whole page is about.

---

## Where to go next

[conventions.md](conventions.md) owns the mechanisms these gates enforce — the
`/etc` merge, factory plus tmpfiles, `ConditionUser`, seed hashing, preset
derivation — and is where to look when a gate fails and you need to know what
shape the fix should take. [build-and-ci.md](build-and-ci.md) covers the
workflows the CI gates run inside, including the tags, cache and publish steps
this page deliberately leaves alone. For the day-to-day loop that ends in
`just validate`, and for what to do about the drift the audits report, see
[capturing-changes.md](capturing-changes.md).
