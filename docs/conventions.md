# Conventions

Where a change belongs, what to call it, where to put it, and which mechanism to
reach for. The naming rules mostly track the Universal Blue family this image
sits in — it builds on `ghcr.io/ublue-os/base-main`, and the table below compares
against bazzite, bluefin, aurora and `ublue-os/main`. Everything after that
exists because its absence produced a real failure here, and that failure is the
part worth reading.

[AGENTS.md](../AGENTS.md) states these as rules for an agent to obey without
argument. This page is the same set with the reasoning attached, so a human can
tell when a rule applies and when it does not.

**Almost every convention below is a scar. If one looks arbitrary, the story of
why it exists is in the file it governs.**

---

## Classify Every Change

Before touching anything, decide which of four buckets the change lands in.
Getting this wrong is the most expensive mistake available: a personal
preference baked into the image is inflicted on every account, and a system
default written into `~` disappears on the next machine.

| Bucket | What goes there | Where it lives |
|---|---|---|
| **Image** | RPMs, daemons, sockets, privileged helpers, systemd presets, factory defaults | `build_files/` for packages and build steps, `system_files/` for the shipped overlay |
| **Manifest plus create-only chezmoi source** | Deterministic user preferences that should be a default but must lose to an existing user edit | One entry in `tooling/data/dotfiles.manifest`, a seed under `system_files/usr/share/workstation-os-image/dotfiles/` |
| **Image-owned scaffolding** | Config the image owns but chezmoi applies, because the base no longer supplies it — the niri system config, `foot.ini` | `scaffold` entries in `tooling/data/dotfiles.manifest` |
| **Never in Git** | Secrets, tokens, SSH keys, browser profiles, shell histories, caches, application databases, backups, device-specific runtime state | Nowhere. A scrub filter makes the surrounding file committable, never the secret |

The manifest header states the scaffold contract directly: image-owned,
"chezmoi-applied, never captured from live and never drift-audited". Personal
niri changes belong in `~/.config/niri/local.kdl` instead — see
[subsystems/desktop-session.md](subsystems/desktop-session.md) for the include
order that makes that work.

Use chezmoi `create_` entries for personal defaults. `create_` seeds a file only
when it is absent, so an edit the user already made survives every update; a
plain copy would silently revert it.

### The GUI rule

For a change made in a graphical application, find the deterministic config file
behind it and add a reviewed file or a narrow export/restore mechanism. Never
copy an application directory wholesale. Application directories mix the three
things you want with the twenty you must not have: session tokens, sqlite
caches, window geometry, machine ids. A wholesale copy commits all of them and
nobody notices until the repository is public.

The capture side of this — the manifest kinds, the scrub filters, the audit
loop — belongs to [capturing-changes.md](capturing-changes.md).

---

## Naming and Placement

`system_files/` mirrors absolute paths and is copied verbatim into `/`
(`COPY system_files/ /` in the Containerfile). `build_files/` is bind-mounted at
`/ctx` and never reaches a layer. `tooling/` is not even in the build context —
`.containerignore` is a default-deny (`**`) that re-admits only `Containerfile`,
`image.env`, `system_files/` and `build_files/`, so host-side scripts cannot be
baked in by accident.

| Element | Here | Upstream |
|---|---|---|
| Shipped overlay | `system_files/`, mirroring absolute paths | same (`sys_files/` in `main`) |
| Build inputs | `build_files/`, bind-mounted at `/ctx` | same |
| Build scripts | `NN-name.sh`, flat; the prefix is execution order | same in bluefin and aurora; bazzite is flat and unnumbered |
| Host-side scripts | `tooling/`, never baked | `just_scripts/` in bazzite |
| Declarative source | `tooling/data/`, never baked | no analogue; `main`'s `packages.json` and secureblue's `recipes/` are the nearest, and bazzite's `post_install_files/` is installer payload, not this |
| Image identity | `image.env`, read by CI, the Justfile and the image | `image-template.env`; bazzite uses `image-info.json` |
| systemd units | `workstation-<function>` under `usr/lib/systemd/` | same shape (`bazzite-`, `bluefin-dx-`) |
| Unit drop-ins | `NN-<concern>.conf` under `/usr/lib` | the family is 21 numbered drop-ins to 6 named `override.conf`, five of those six under `/etc` where nothing can shadow them |
| tmpfiles | one file per feature, `NN-workstation-<feature>.conf` | same |
| Presets | `10-workstation-os-image.preset`, sorting before Fedora's; the single list of enablement intent | none of the four ship preset files; bazzite has 30 inline `systemctl enable`, bluefin 13 |
| polkit rules | `NN-workstation-<thing>.rules` under `usr/share/polkit-1/rules.d/` | same |
| Shipped scripts | `#!/usr/bin/env bash` or `#!/bin/sh` | bazzite mixes five forms |
| Build scripts | `#!/usr/bin/bash`, since bash is at a known path inside the image | same |

Two of those rows are gated rather than merely stated.

`tooling/validate/sources` walks `system_files/usr/bin` and
`system_files/usr/libexec` and rejects any shebang that is not one of the two
permitted forms. The comment names the outlier that prompted it: `workstation-ocr`
carrying `#!/usr/bin/bash` alone among ten. `build_files/` is excluded
deliberately, since those scripts run inside the image where bash is at a known
path.

`tooling/validate/image-build` walks `image.env` line by line against the
Containerfile's `ARG` defaults, so identity stays written in exactly one place:

```bash
|| fail "Containerfile ARG ${key}=${arg} does not match image.env ${key}=${value}"
```

> Never name a unit drop-in `override.conf`. That is the filename `systemctl
> edit` writes, and a same-named drop-in replaces the earlier one rather than
> merging with it — so the day someone runs `systemctl edit` on that unit, your
> shipped configuration silently vanishes.

---

## Numbering

Build-script prefixes are the execution order, and the gaps between them are
deliberate: `00-toolchain.sh`, `10-repos.sh`, `20-packages.sh`, `25-rpmdb.sh`,
`30-desktop.sh`, `40-signing.sh`, `50-services.sh`, `60-metadata.sh`,
`90-cleanup.sh`, `99-check-build.sh`. A new step slots into a gap without
renumbering the ones after it, which would otherwise turn a one-line addition
into a diff across the whole directory. `25-rpmdb.sh` is what a gap is for: it
had to land between packages and desktop, and it did so without touching a
single other prefix. `99-check-build.sh` stays last because it asserts the finished
image.

Presets are numbered `10-` so they sort before Fedora's `85-display-manager.preset`
and `90-default.preset`, winning by ordering rather than by fighting. The two
preset files together are the **single list of enablement intent**, and three
consumers read them:

- `build_files/50-services.sh` derives its `systemctl preset` arguments from
  them: `mapfile -t system_units < <(sed -n 's/^enable //p' "$system_preset")`,
  then `systemctl preset "${system_units[@]}"`.
- `build_files/99-check-build.sh` asserts each `enable` line actually produced a
  symlink, and separately that every non-`workstation-*` user unit named there
  has a `ConditionUser=!@system` drop-in.
- `tooling/audit/units` checks the same lines against the live machine.

They used to be two hand-maintained copies of the same intent. A unit added to a
preset and forgotten in the script would ship, pass `systemd-analyze verify`, and
simply never be enabled.

The `disable` lines are different. `50-services.sh` writes three explicit
`systemctl disable` calls by hand — `rpm-ostreed-automatic.timer`,
`brew-update.timer brew-upgrade.timer`, `dnf-makecache.timer` — because a preset
file cannot undo an enablement symlink another layer already wrote. The matching
`disable` lines in the preset file change nothing at build time; they are there
as the manifest `tooling/audit/units` checks against the live machine, where a
local `systemctl enable` would otherwise go unnoticed.

---

## Mechanisms Worth Reaching For

### `/etc` is a three-way ostree merge

Anything written to `/etc` becomes machine-local for the life of the install,
and every later image version of that file is ignored silently. Ship image-owned
config as `/usr/share/factory` plus a tmpfiles `L+` line instead, so a user edit
in `/etc` survives an image update while an untouched file keeps tracking the
image.

The worked example is the default terminal. It does **not** ship at
`system_files/etc/`. It ships at
`system_files/usr/share/factory/etc/xdg/xdg-terminals.list` and is materialised
by `system_files/usr/lib/tmpfiles.d/10-workstation-terminal.conf`, whose entire
payload is one line:

```ini
L+ /etc/xdg/xdg-terminals.list
```

A bare `L+` with no source resolves against `/usr/share/factory`, which is why
the target path is written once and the source is implied.
`10-workstation-docker.conf` and `10-workstation-keyd.conf` follow the same
shape, each adding a `d` line first because `/etc/docker` and `/etc/keyd` do not
already exist — `/etc/xdg` does, so the terminal file needs no directory entry.

Build-created accounts get the same treatment in the other direction.
`build_files/90-cleanup.sh` relocates the accounts that RPM scriptlets add to
`/etc/passwd` and `/etc/group` into `/usr/lib/passwd` and `/usr/lib/group`,
matching base-main's own convention, because an account left in `/etc` becomes
machine-local and can collide with a locally created one after a later image
moves or drops it.

`tooling/audit/etc-drift` reports what has diverged anyway. Its header records
the failure that motivated it: `/etc/greetd/niri/config.kdl` had been frozen at
its 2026-07-10 state since `dms greeter install` rewrote it, so a later image
that added `optional=true` to its `dms.kdl` include never reached the machine —
on the path whose failure costs a graphical login.

### `/var` content needs a tmpfiles entry

`/var` is applied at initial provisioning and never again, so a directory shipped
inside the image is frozen at whatever the first deploy wrote.
`bootc container lint --fatal-warnings` rejects the omission outright, and the
Containerfile runs it, so this one fails at build time rather than in the field.
`system_files/usr/lib/tmpfiles.d/10-workstation-tuned.conf` is the minimal case —
two `d` lines for `/var/lib/tuned` and `/var/log/tuned`, taken from the lint's own
suggested output.

### The base's top-level compat symlinks are dangling

`/opt -> var/opt` with no `/var/opt` on base-main, and the same story for
`/root -> var/roothome`, `/home -> var/home` and `/media -> run/media`. A file
shipped under any of them replaces the symlink with a real directory, the content
lands in `/var` or on a tmpfs, and `bootc container lint` passes — the resulting
path is legitimate, so nothing flags it.

Nor is a gentler copy mechanism a fix: `rsync --keep-dirlinks`, which bluefin,
aurora and `main` use instead of `COPY`, only preserves a symlink resolving to an
**existing** directory, so their form clobbers `/opt` too. Since no overlay
mechanism prevents it, `build_files/99-check-build.sh` asserts the outcome
instead, over eight paths — the four dangling compat links plus the four
usr-merge ones:

```bash
for d in /opt /bin /sbin /lib /lib64 /media /root /home; do
    test -L "$d" \
        || fail "$d is a real directory; an overlay path under it replaced the base's compat symlink"
done
```

The assertion also covers the two cross-stage copies, `COPY --from=brew` and
`COPY --from=toolchain`, which an overlay allowlist would not reach. Image-owned
`/opt` payload therefore goes to `/usr/lib/opt` plus a tmpfiles link.

### User units need `ConditionUser=!@system`

Every user manager reaches `default.target`, including the one `pam_systemd`
starts for greetd's `greeter` account, whose home is read-only. Without the
condition, a unit fails on every visit to the login screen. `!@system` excludes
accounts below `SYS_UID_MAX`.

Our own `workstation-*` units carry the line inline. RPM-owned units that we
enable globally need a drop-in, uniformly named `10-skip-system-users.conf`, and
that drop-in is easy to forget because nothing fails loudly when it is missing —
`xdg-user-dirs.service` would just try to write the greeter's read-only home on
every boot. `99-check-build.sh` closes that by walking the user preset and
requiring the condition for every non-`workstation-*` unit it enables.

### "Not ready yet" is an `ExecCondition`, not a non-zero `ExecStart`

An `ExecCondition` that fails marks the unit skipped. A non-zero `ExecStart`
marks it failed, permanently, which trains you to ignore your own audit output.
`workstation-claude-mcp-seed.service` is the shipped example:

```ini
ExecCondition=/usr/bin/test -x /home/linuxbrew/.linuxbrew/bin/claude
```

### A re-runnable seed hashes its own script

Never a bare marker file. A plain existence check makes every later edit to that
script dead code on any account that already ran it — a new tool, a changed path,
a fixed derivation, none of it lands, and the unit reports success by not
running. Hashing the script itself also cannot be forgotten the way a hand-bumped
version counter can. `system_files/usr/libexec/workstation-bootstrap-user` does
it in two lines, checked before the first `mkdir` and well before its ~70 MB
download, so a no-op re-run costs one `sha256sum`:

```bash
script_hash="$(tr -d "[:space:]" <"$0" | sha256sum | cut -d " " -f 1)"
if [[ -f $marker && "$(cat "$marker")" == "$script_hash" ]]; then
```

`system_files/usr/bin/workstation-install-microsoft-fonts` uses the identical
pattern. The DMS settings seed in
`system_files/usr/bin/workstation-apply-dms-settings` is the deliberate
exception: its marker is one-shot forever, because DMS settings are UI-owned
after the seed and re-running would stomp the user's edits.

### Assert coverage, not success

`while read ... done < <(cmd FILE)` on an absent FILE iterates zero times and
passes, so a rename disarms the gate instead of breaking it. That is exactly how
a restructure once disabled two gates in `tooling/validate` without anything
going red. Every gate that reads a file through process substitution declares its
input first. `build_files/99-check-build.sh` defines the helper:

```bash
require_file() { test -f "$1" || fail "gate input is missing: $1"; }
```

`tooling/validate/sources` defines its own copy; `tooling/audit/units` inlines
the idiom over its two preset inputs and names the other two gates in its
comment. A related trap lives beside it in `99-check-build.sh`: never use
`grep -q` in a pipeline there. It exits on the first match, `SIGPIPE`s the
writer, and `pipefail` turns that into a non-zero pipeline — so the gate fails
precisely when the thing it checks for is present. Use `grep ... >/dev/null`,
which reads the whole stream.

### Vendored repos are fenced four ways

`gpgcheck=1`, `gpgkey=file://`, an `https` `baseurl` or `metalink`, and an
`includepkgs` allowlist. All four are gated per file in
`tooling/validate/image-build`, which also refuses
`config-manager addrepo --from-repofile` anywhere in the build: a repofile
fetched from a vendor URL makes whatever `baseurl` and `gpgkey` it carries that
day into this build's trust anchors.

The allowlist is the one that closes a real attack surface rather than a
theoretical one, and `build_files/repos/terra.repo` records the incident that
proves it. That story, the per-requirement gate table and which package comes
from which repo are all in [subsystems/packages.md](subsystems/packages.md).

### Session environment goes in `/usr/lib/environment.d`

Never `/etc/profile.d`. `profile.d` reaches login shells only, and the session is
`niri.service` under the systemd user manager, which never sources one. The
input-method variables the previous base kept in `profile.d` therefore reached no
GUI application at all: fcitx5 was installed in full and `fcitx5.service`
enabled, and the input method engaged in almost nothing.

Three files carry it, numbered by concern, under
`system_files/usr/lib/environment.d/`: `40-workstation-editor.conf`,
`50-workstation-input-method.conf` and `60-workstation-fonts.conf`. Where one
names a binary the path is absolute — `EDITOR=/home/linuxbrew/.linuxbrew/bin/nvim`
— because Homebrew's `bin` is not on the compositor's PATH.

### A terminal entry must declare the `X-TerminalArg*` keys

Fedora's `foot.desktop` and `footclient.desktop` declare none of the Default
Terminal Specification's `X-TerminalArg*` keys, so `xdg-terminal-exec` accepts
`--app-id` and `--title` and silently discards them. Every bind landed as app-id
`foot`, and the three matching desktop entries could never associate.

`system_files/usr/share/applications/workstation-footclient.desktop` declares all
five (`X-TerminalArgExec`, `X-TerminalArgAppId`, `X-TerminalArgTitle`,
`X-TerminalArgDir`, `X-TerminalArgHold`). Note what the gate asserts: checking
*which* entry resolves would not have caught the original bug, so
`99-check-build.sh` runs `xdg-terminal-exec` with probe arguments and asserts the
resulting command line still contains `footclient`, `--app-id=probe-app`,
`--title=probe-title` and the program.

### When one mechanism spans two files, gate that they agree

Three shipped instances:

| Pair | Gate |
|---|---|
| The polkit grant in `10-workstation-uupd.rules` and the command DMS is seeded with | `99-check-build.sh` asserts the rule still scopes to `unit == "uupd.service"` and `verb == "start"`, and that the shipped `dms-settings.json` sets `updaterCustomCommand` to `systemctl start uupd.service` |
| The Containerfile `ARG` defaults and `image.env` | `tooling/validate/image-build` compares them key by key |
| `cosign.pub` and `system_files/etc/pki/containers/workstation-signing.pub` | `cmp -s` in `tooling/validate/image-build` |

Signing and key handling itself belongs to
[supply-chain.md](supply-chain.md); what each gate proves is enumerated in
[validation-and-gates.md](validation-and-gates.md).

### Interactive recipes take a non-interactive selector

Anything a human can choose interactively, a script must be able to choose by
name. `just dms-capture --select KEY` takes the same key the picker shows in its
first column and is repeatable, and `tooling/dms/capture` only reaches for fzf
when no `--select` was passed. The alternative it replaced was driving fzf
through `FZF_DEFAULT_OPTS='--filter=... --exact'`, which tests the filter rather
than the script.

Destructive recipes take `[confirm]` or default to a dry run. `just dms-apply`
carries `[confirm("Overwrite live DMS settings from the tracked overlay?")]` and
`just flatpak-prune` carries `[confirm("Remove every unused Flatpak runtime from
this account?")]`; `just ai-reset` is a dry run until `--force`.

---

## Commits

Conventional Commits with a scope: `fix(build):`, `feat(audit):`,
`docs(niri):`, `chore(packages):`. The log is already uniform; stating it here
means nobody has to infer the pattern from `git log` before their first commit.
Scope names the subsystem the change lands in, not the file.

Durable changes go through a branch and a pull request. A requested permanent
workstation change that exists only on the live machine is not finished — the
repository is the thing that recreates the workstation.

---

## Where to go next

[capturing-changes.md](capturing-changes.md) is the procedural companion to the
classification above: once you know a change is a personal preference, that page
covers the manifest, the audit loop and `just sync`.
[validation-and-gates.md](validation-and-gates.md) explains which gate proves
which of the mechanisms on this page, and why image gates and machine audits are
two different things. For a change you can copy rather than reason about, start
at [cookbooks.md](cookbooks.md).
