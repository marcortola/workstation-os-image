---
description: Review what changed in Zirconium since the watermark and port what belongs here
argument-hint: "[--patch]"
---

# Port upstream Zirconium changes

This image derived from [Zirconium](https://github.com/zirconium-dev/zirconium)
until 2026-08-29 and now derives from `ghcr.io/ublue-os/base-main`. Nothing
arrives from upstream automatically any more, but it still runs the same niri +
DankMaterialShell + greetd + uupd stack, so it keeps solving problems this
image has. The base swap by itself left nine of its decisions unported,
including having no SSH agent at all.

Your job is to decide, for each upstream change, whether it belongs here.
Porting is the exception, not the default.

## 1. Get the diff

```
tooling/upstream/zirconium-diff --patch $ARGUMENTS
```

Exit 0 means nothing to do; say so and stop. Exit 3 means there is a review to
do. The script maps each changed path to the file here it would land in.

## 2. Classify every in-scope change into exactly one bucket

**Port it** — it fixes something broken here, adds a capability we want, or
tracks a Fedora/systemd/DMS change we will hit too. Package additions that back
a DMS feature are the highest-yield class: `tuned-ppd` was missing for months
and DMS's power widget simply had no backend.

**Already covered** — say by what. Three common cases: `base-main` provides it
(bootc, dracut, ostree, resolved, brew, uupd, journald persistence, the Flathub
`remote-add`); we have it under our own name (`workstation-chezmoi-*` for
`chezmoi-init`/`-update`, `10-workstation-os-image.preset` for
`01-zirconium.preset`, `99-workstation-dms-greeter.conf`,
`10-dms-screenshot-editor.conf` for `dms.service.d/override.conf`, `wjust` for
`zjust`, `workstation-ocr` for `zocr`, `dotfiles/` for `zdots`); or we do the
same thing by a better mechanism, and keeping ours is the point.

**Declined** — record the reason in the commit message. Standing declines, do
not re-litigate: Zirconium branding (`zfetch`, `zmotd`, `zprompt`, `zfunny`,
`glorpfetch`, `fastfetch.jsonc`, logos, wallpapers); `taidan`; kmscon;
`rechunker-group-fix`; `cardwire`; `ntpd-rs` (we use base-main's `chronyd`);
`flatpak-preinstall` (the Brewfile owns Flatpaks — the preinstall unit is
marker-gated and runs once, ever); the `greetd-spawn` PAM stack (see the
rationale in `/etc/greetd/config.toml`); the jackrabbit, nvidia, liveiso and
sysupdate profiles.

## 3. Do not copy upstream's shape without checking it

Upstream is a peer, not an authority. Three of its files were wrong when
audited:

- `99-no-nsresourced.preset` never fires — it sorts after systemd's `90-`
  preset, and the socket is enabled in Zirconium's own shipped image.
- Its `bootc` install default sits at `/usr/lib/bootc/10-zirconium-install.toml`
  with the older `[install] root-fs-type` key, one directory above the
  `/usr/lib/bootc/install/` that bootc documents.
- Its `xdg-terminals.list` overwrites the package's own file, discarding the
  `execarg_default` table with it.

Where our mechanism is deliberately different, it is written down: session
environment goes in `/usr/lib/environment.d`, never `/etc/profile.d`, because
the session is `niri.service` under the user manager and never sources a login
shell; image-owned `/etc` config is `/usr/share/factory` plus a tmpfiles `L+`.
`AGENTS.md` has the full list.

## 4. Verify in the built image, never by reading the source

This is the rule that matters most, and the one broken most recently. A gate
that checks the adjacent thing is worse than no gate, because it reports
success: `89eb668` verified the terminal launcher with `--print-id`, which
reports *which entry resolves* and says nothing about *which arguments
survive* — so `--app-id` and `--title` were being silently discarded while the
check passed.

For anything you port:

```
just build
podman run --rm localhost/workstation-os-image:review-main <check the effect>
```

Add an assertion to `build_files/99-check-build.sh` that would fail if the port
regressed. Assert the effect, not that the file exists. `/var` content needs a
tmpfiles entry or `bootc container lint --fatal-warnings` rejects the layer —
adding `tuned` failed the build for exactly this.

## 5. Finish

- Conventional Commits with a scope, one commit per coherent change.
- `just validate`, and `just build` for anything touching the image.
- `just upstream-accept` to advance `tooling/data/zirconium-watermark`, in the
  same PR as the review. Never advance it to silence the diff: a bumped
  watermark with nothing ported is a claim that every change was examined.
- Report the declines explicitly. A review that lists only what it ported is
  indistinguishable from one that stopped reading halfway.
