# Getting Started

How to take a machine that already boots a bootc container image and converge it
onto this one: the rebase, what the first graphical login does on its own, and
the handful of steps that are deliberately not automatic.

**Rebasing installs the image; the first graphical login installs the account.**

---

## Before You Start

The target must already be bootc-based — `bootc status` has to report a booted
container image. This repository builds a container image and nothing else:
there is no `disk_config/`, and `.github/workflows/` holds only `build.yml`,
`clean.yml`, `lint.yml` and `rollback.yml`, so no ISO or disk image is ever
produced. Rebasing is therefore the only install path. If you are forking rather
than joining this image, [forking.md](forking.md) lists what a fork edits, what
it deletes, and the fact that an installer pipeline is one of the things it does
not inherit.

You also need a normal, non-system user account on the target. Everything that
converges after the reboot runs in that account's systemd user manager, and the
units are all conditioned to skip system accounts.

---

## Switch the Machine

The published reference is derived from `image.env`, which is the only place
this image's identity is written:

```ini
IMAGE_NAME=workstation-os-image
REPO_ORGANIZATION=marcortola
```

`tooling/audit/deployment` builds the same string and fails the audit if the
booted deployment does not match it:

```bash
expected_image="ghcr.io/${REPO_ORGANIZATION}/${IMAGE_NAME}:"
```

So the reference to switch to is `ghcr.io/<REPO_ORGANIZATION>/<IMAGE_NAME>:latest`.
Read those two values out of `image.env` before you type the command — on a fork
they are the only thing that changes.

```bash
skopeo inspect docker://ghcr.io/marcortola/workstation-os-image:latest
sudo bootc switch ghcr.io/marcortola/workstation-os-image:latest
sudo bootc status --verbose
systemctl reboot
```

`skopeo inspect` first, because it fails cheaply on a typo, an unpublished tag
or a registry outage, before `bootc switch` has staged anything. `bootc status`
after the switch lists the deployments and their origins, the freshly staged one
included, and `--verbose` adds the remaining fields; it needs root, which is why
it carries `sudo` here. Nothing is running yet at that point, which is why the
reboot is part of the sequence rather than an afterthought.

> A plain `bootc switch` pulls without checking the image signature, and the
> origin stays `ostree-unverified-registry:` for every future update until you
> change it. The trust anchor ships inside this image — `build_files/40-signing.sh`
> writes the `policy.json` entry at build time — so enforcement is a second,
> one-time switch made from the running image, not part of the first rebase.
> [supply-chain.md](supply-chain.md) has the command and the key-rotation rules.

---

## What Happens At First Login

Nothing user-level runs during the reboot; the account converges at the first
login. `system_files/usr/lib/systemd/user-preset/10-workstation-os-image.preset`
is the single list of enablement intent, and the units it names ship in
`system_files/usr/lib/systemd/user/`. That preset also enables the session's own
units — dms, dsearch, foot-server, the gcr SSH agent, fcitx5, udiskie — which
[subsystems/desktop-session.md](subsystems/desktop-session.md) owns. The nine
below are the convergence half.

| Unit | Pulled in by | What it does |
|---|---|---|
| `workstation-chezmoi-init.service` | `graphical-session-pre.target` | Runs `/usr/libexec/workstation-chezmoi-apply --init`, which applies the image's chezmoi seeds to a new account from `/usr/share/workstation-os-image/dotfiles`. This is what creates `~/.config/homebrew/Brewfile`. Skipped once `~/.config/workstation-os-image/chezmoi/chezmoi.toml` exists. |
| `workstation-dms-settings.service` | `graphical-session.target` | Runs `workstation-apply-dms-settings --initialize`, seeding the tracked DMS preference overlay from `/usr/share/workstation-os-image/dms-settings.json`. One-shot per account, forever. |
| `workstation-bootstrap.service` | `graphical-session.target` | Trusts the Brewfile's tap-qualified formulae, runs `brew bundle install` over the Brewfile (`brew`, `cask` and `flatpak` entries alike), then installs DataGrip under `~/.local/opt` from the JetBrains release API, verified against the checksum that API serves. |
| `workstation-claude-mcp-seed.service` | `graphical-session.target` | Adds the default user-scope Claude Code MCP servers, leaving any the account already defines untouched. |
| `workstation-microsoft-fonts.service` | `default.target` | Installs the user font set into `~/.local/share/fonts`: Caskaydia Mono (Nerd Fonts), iA Writer Mono, Font Awesome, and the Microsoft core fonts under `Microsoft/`. Passes `--accept-microsoft-eula` on your behalf, which the script otherwise refuses to run without. |
| `workstation-flatpak-wayland.service` | `default.target` | Sets the global Flatpak override that makes Electron and Chromium Flatpaks native Wayland clients, re-asserted every login. |
| `workstation-x11-clipsync.service` | `graphical-session.target` | Long-running: mirrors the XWayland clipboard into the Wayland one. |
| `workstation-chezmoi-update.timer` | `timers.target` | Reapplies the dotfile seeds 5 minutes after boot and daily thereafter, skipping any target you have edited. |
| `workstation-invoice-bookmarks.timer` | `timers.target` | Monthly bookmark refresh; nothing to do with convergence. |

The ordering between the first four is load-bearing, not incidental. The
bootstrap runs `After=workstation-chezmoi-init.service`, because it exits with
`Waiting for chezmoi to create $brewfile` if the seed has not landed yet; the
Claude seed runs `After=workstation-bootstrap.service`, because `claude` arrives
through Homebrew. The last three are additionally ordered after
`graphical-session.target` and not merely after `dms.service`, and the comment in
`workstation-dms-settings.service` says why:

```text
# implicitly Before it; ordering after dms.service alone therefore closes an
# ordering cycle (target -> dms -> us -> target) that systemd breaks by dropping
# dms.service, leaving the session with no DMS bar/launcher.
```

Every one of these carries `ConditionUser=!@system`, so it does not also fire in
the greeter account's user manager against a read-only home, and the re-runnable
ones key their completion marker on a hash of their own script rather than a
bare marker file. Both are house mechanisms with their own failure stories —
[conventions.md](conventions.md) owns them.

On the system side the work is already done by the time you reach the login
screen: `workstation-user-groups.service` runs
`Before=systemd-user-sessions.service` and joins every local interactive account
to `docker` and `input`, which is why Docker works without `sudo` in the very
first session after the rebase.

---

## The wjust Launcher

There is no checkout on a freshly rebased machine, and the bootstrap does not
make one. From `system_files/usr/libexec/workstation-bootstrap-user`:

```text
# The repository checkout is no longer cloned here: /usr/bin/wjust clones it on
# demand the first time a recipe runs.
```

**`wjust`** is the image-provided launcher that fills the gap. It ships at
`system_files/usr/bin/wjust`, which means it updates with every build and
reaches machines that already exist — unlike a shell alias, which would only
reach accounts seeded after it was added. On its first run it derives the clone
URL from the copy of `image.env` the image was built from, cloning into
`$HOME/projects/personal/workstation-os-image`:

```bash
source /usr/share/workstation-os-image/image.env
git clone "https://github.com/${REPO_ORGANIZATION}/${IMAGE_NAME}.git" "$repo"
```

It then `cd`s into the checkout and `exec just "$@"`. The `cd` is deliberate:
`just` demands `--justfile` whenever `--working-directory` is given, which would
bake the justfile's name into the image, so searching from the checkout keeps a
`Justfile` rename from needing a matching bootc upgrade.

**The prefix rule for this handbook**, stated once here: this page and
[operating.md](operating.md) use `wjust`, because their reader may not have a
checkout yet. Every other page under `docs/` uses plain `just`, because by then
you are standing in the checkout you just edited. They are the same recipes —
`wjust audit` is `just audit` run from wherever you happen to be.

---

## Convergence Checklist

Paste this after the first graphical login. It is safe to re-run.

```bash
wjust audit

systemctl --user status workstation-chezmoi-init.service \
  workstation-dms-settings.service workstation-bootstrap.service \
  workstation-claude-mcp-seed.service workstation-microsoft-fonts.service

systemctl is-enabled greetd.service containerd.service docker.service keyd.service
systemctl is-active containerd.service docker.service keyd.service

docker run --rm hello-world
```

`wjust audit` is the real check: it runs six audits in sequence — deployment,
unit state, image-owned `/etc` drift, update status, packages and personal files
— and a converged machine reports no divergence in any of them. What each one
proves, and why some of these questions can only be answered against a live
machine rather than in CI, belongs to
[validation-and-gates.md](validation-and-gates.md).

> A `Type=oneshot` unit that has succeeded reads `inactive (dead)`, not
> `active`; look at the `status=0/SUCCESS` line instead. A genuinely failed
> `workstation-bootstrap.service` on a brand-new machine is usually benign: it
> exits non-zero with `Waiting for brew-setup.service to provision` when
> Homebrew has not finished unpacking yet, deliberately leaving its marker
> absent so the next login retries. `tooling/audit/units` reports it as a failed
> image-owned unit until that retry succeeds, so log out and back in before
> investigating.

---

## The Dictation API Key

Dictation needs an OpenAI API key. It is one of the two credentials this
workstation keeps outside Git — the other is the intelephense licence
`wjust intelephense-licence` stores. Store this one with the helper chezmoi
deploys into your own `~/.local/bin`:

```bash
workstation-openai-key
```

It prompts without echo and writes `~/.config/openai/api-key` into a `0700`
directory under `umask 077`. The key never enters Git: what the repository
tracks is the script, as one `copy` line in `tooling/data/dotfiles.manifest`
pointing at `private_dot_local/bin/create_executable_workstation-openai-key`.
`workstation-dictate` reads `OPENAI_API_KEY` first and falls back to that file at
run time; with neither it raises a `notify-send` desktop notification telling you
to run the helper, rather than failing silently in a keybind with no terminal
attached.

---

## Day-One Follow-Ups

The first login converges the account against the Brewfile and the seeds *as
they stood at that moment*. These three are not automatic, and each one bites
somebody eventually.

| Command | Why it is not automatic |
|---|---|
| `wjust brew-apply` | A newly added `brew`, `cask` or `flatpak` line in the Brewfile is self-trusting but not self-installing on a machine that has already bootstrapped. In the recipe's own words, "tap trust and daily upgrades are already automatic" — installing what is *new* is not. See [subsystems/packages.md](subsystems/packages.md). |
| `wjust intelephense-licence` | Stores the intelephense premium key that `dev nvim` injects into the container. Machine-local by design, because it writes a licence key. See [subsystems/dev-environment.md](subsystems/dev-environment.md). |
| `wjust ai-tools-install` | Installs the AI CLI tools through their own official installers rather than vendoring them, so nothing in the image pins their versions. See [subsystems/ai-clis.md](subsystems/ai-clis.md). |

Run these once after the first login has settled, `brew-apply` first: the AI
tool installer needs `rtk`, which the Brewfile declares, and Node, which
Homebrew pulls in behind the Brewfile's `claude-code` cask.

---

## Where to go next

[operating.md](operating.md) is the next page for anyone who now has a working
machine: upgrades, rollback, what the automatic update run covers and how to
find out which part of it failed. If the desktop is the reason you are here —
niri, DMS, keybinds, the terminal — go to
[subsystems/desktop-session.md](subsystems/desktop-session.md). Once you want to
change something rather than just run it, [capturing-changes.md](capturing-changes.md)
is the workflow that turns a live edit into a reviewed commit, and
[architecture.md](architecture.md) explains the ownership model it rests on.
