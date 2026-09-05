# Operating a Workstation

Day-two operations on a machine already running this image: taking an update,
proving the image you are about to boot is the one this repository published,
getting back to a working deployment when it is not, and the routine
housekeeping nothing else does for you. Recipes are shown as `wjust`, the
image-provided launcher that runs one from any shell and any directory;
[getting-started.md](getting-started.md) covers it and the first-login path.

**The image is the unit of change: fix the repository, wait for the signed
publication, then upgrade the machine.**

---

## The Ordering Rule

Merge the repository change, wait for the image publication, and only then
upgrade the machine. In that order, always.

The machine tracks `:latest`, and `:latest` is not moved by the push that builds
the image. `.github/workflows/build.yml` pushes `:$GITHUB_SHA` and
`:$BUILD_TAG`, signs the resulting digest, and only then copies that exact
digest onto `:latest`. Its comment says why:

```text
:latest is deliberately NOT pushed here. policy.json on the machine
requires a signature for this scope, so a failure between push and sign would
leave a published :latest that uupd refuses to pull, and the machine stuck
until the next green build.
```

So an upgrade run before the workflow finishes does not pick up a half-published
image — it silently picks up the *previous* one. You reboot, the change is not
there, and you go looking for a bug in a change that was never on the machine.

Sometimes there is nothing to wait for. A merge that touches none of
`Containerfile`, `image.env`, `system_files/`, `build_files/` or
`.github/workflows/build.yml` leaves the `image-inputs` job reporting
`changed=false`, and the `build` job is gated on
`if: needs.image-inputs.outputs.changed == 'true'`. A `tooling/`-only or
`Justfile`-only push therefore starts the workflow and publishes no image, which
is correct — nothing in the image changed. See
[build-and-ci.md](build-and-ci.md) for the two-layer trigger and the tag scheme.

---

## Updating

Check what is published, stage it, confirm what you are about to boot, then
reboot:

```bash
skopeo inspect --no-tags docker://ghcr.io/marcortola/workstation-os-image:latest
sudo bootc upgrade
sudo bootc status --verbose
systemctl reboot
```

Between `bootc upgrade` and the reboot the machine has fetched and staged a
deployment it is not running, and `bootc status --verbose` is the only place you
see the staged image reference before you boot it. Skip it and a reboot is the
first thing that tells you what you adopted. `tooling/audit/deployment` reports
the same gap for the same reason:

```text
  reboot required to adopt the staged deployment
```

After the reboot, confirm the machine actually converged:

```bash
wjust audit
```

The image name and owner in those references come from `image.env`, the single
declaration a fork edits. Everything else that spells them out — the
Containerfile's `ARG` defaults, the workflow's `IMAGE_REF` — is gated against
that file, so substituting your own is enough and every command on this page
follows.

> Do not install image-owned software with `rpm-ostree` layering. A layered
> package is machine-local state this repository cannot see and no other
> workstation ever gets. `tooling/audit/deployment` fails on it: it collects
> `requested-packages`, `requested-local-packages`, `requested-base-removals`,
> `requested-base-local-replacements` and
> `requested-local-fileoverride-packages` from the booted deployment and exits
> non-zero if any is non-empty, printing each as an `rpm-ostree-layer` line. It
> fails on a non-`none` `unlocked` value for the same reason. Add the package to
> the repository instead; see
> [subsystems/packages.md](subsystems/packages.md).

---

## Verifying a Published Image

`cosign.pub` at the repository root is the public half of the signing key, and
both `cosign` and `skopeo` are already on the image. Resolve the tag to a digest
first, then verify the digest — a tag can move between the two commands, a
digest cannot:

```bash
digest=$(skopeo inspect --no-tags \
  docker://ghcr.io/marcortola/workstation-os-image:latest --format '{{ .Digest }}')
cosign verify --new-bundle-format=false --key cosign.pub \
  "ghcr.io/marcortola/workstation-os-image@$digest"
```

Run it from the checkout, so `cosign.pub` resolves. `--new-bundle-format=false`
is not optional and not cosmetic: bootc and rpm-ostree read the legacy
simple-signing attachment, and `.github/workflows/build.yml` signs with the same
flag for that reason. Drop it and the verification fails against a signature
the machine itself accepts without complaint.

This is a manual cross-check of what `policy.json` enforces on a pull — but the
policy only bites when the booted deployment asks for it. A
`container-image-reference` of `ostree-unverified-registry:` was pulled without
checking a signature, whatever `policy.json` says now, which is why
`tooling/audit/deployment` prints `booted deployment is not signature-verified`
for any reference that is not `ostree-image-signed:`.
[supply-chain.md](supply-chain.md) owns the signing model, the policy file and
key rotation.

---

## Rolling Back

### One deployment back

`bootc rollback` reaches exactly one deployment back — the other half of the A/B
pair:

```bash
sudo bootc rollback
systemctl reboot
```

### Further back

Past that there is nothing on the machine to roll back *to*, so `:latest` has to
be pointed at an older image server-side. The **Roll back :latest** workflow
(`.github/workflows/rollback.yml`) takes a digest, not a tag, so list the tags
and resolve the one you want:

```bash
skopeo list-tags docker://ghcr.io/marcortola/workstation-os-image
skopeo inspect --no-tags --format '{{ .Digest }}' \
  "docker://ghcr.io/marcortola/workstation-os-image:$tag"
```

Rebuilding the same commit is not a substitute. The desktop stack floats on COPR
HEAD, so a rebuild of the same SHA is a genuinely different image.

The workflow re-verifies the signature before it moves the tag:

```bash
cosign verify --new-bundle-format=false --key cosign.pub "$ref@$DIGEST" >/dev/null
```

That gate exists because `policy.json` requires a signature for this scope. An
unsigned or wrongly-signed rollback target would publish a `:latest` that every
machine tracking it then refuses to pull — bricking updates at the exact moment
someone is trying to recover. The workflow also validates the digest shape
(`^sha256:[0-9a-f]{64}$`), sleeps 30 seconds in a "Confirm" step so you can
cancel, and re-reads `:latest` afterwards to prove it resolves to the digest you
asked for.

### Which tag to roll back to

Use the `YYYYMMDD.<run>` tag, not the commit SHA.

The per-commit tag is not durable. The nightly scheduled build (`cron: "17 4 * * *"`)
rebuilds `main`'s HEAD and overwrites `:$GITHUB_SHA`, and the two images
genuinely differ — the desktop stack tracks COPR HEAD, and the scheduled build
reads no layer cache (`--cache-from` is added only when the event is not
`schedule`). `BUILD_TAG` is `$(date -u +%Y%m%d).${GITHUB_RUN_NUMBER}`,
unique per run, so every published build stays individually addressable.

### How far back the list reaches

`.github/workflows/clean.yml` bounds it, weekly. The practical number to hold on
to: **ten tagged images is the floor**, and it is the floor rather than the age
rule that protects a rollback on a repository that publishes for one machine.
Past it the images are gone and no workflow can bring them back — so if you need
an old deployment, get its digest before the next Sunday. The retention policy
itself is [build-and-ci.md](build-and-ci.md).

---

## Homebrew and the Single Updater

Nothing on this machine needs a manual update command. Universal Blue's **uupd**
is the single updater, and one run covers all four of its modules: system
(bootc), Flatpak, Homebrew and Distrobox. `uupd.timer` fires `OnCalendar=*-*-* 04:00:00` with
`Persistent=true` (so a machine that was asleep at 04:00 catches up on resume)
and `RandomizedDelaySec=15m`.

"Single" is enforced, not assumed. `build_files/50-services.sh` disables the
brew payload's own timers:

```bash
systemctl disable brew-update.timer brew-upgrade.timer
```

The comment above that line records the reason, which is not the obvious one:

```text
The ublue brew layer's own preset enables brew-update.timer (every 6h) and
brew-upgrade.timer (every 8h). On the previous base these were inert because
brew-proxy broke them; dropping brew-proxy revives them, which would give us
three brew update paths counting uupd's brew module.
```

`systemctl disable`, not a preset line — `01-homebrew.preset` sorts before ours,
so a preset entry alone would not win. The same file disables
`rpm-ostreed-automatic.timer` and `dnf-makecache.timer` for the same class of
reason: base-main wrote real enablement symlinks into `/etc`, and a preset
cannot undo one. That is an instance of the preset-derivation rule in
[conventions.md](conventions.md).

uupd runs brew as **uid 1000**, not as a service account, because
`brew-setup.service` untars the prefix and then runs
`ExecStart=/usr/bin/chown -R 1000:1000 /home/linuxbrew`. The image ships no
`linuxbrew` account — `/usr/lib/passwd` carries no such entry. A machine rebased
from the old base may still show one under `id linuxbrew`, because that account
came from brew-proxy and lives in `/etc/passwd`, which is a three-way merge no
image can prune. It owns nothing here.

To update now rather than at 04:00, start the unit the timer would have started:

```bash
sudo systemctl start uupd.service
```

### Tap trust

Tap-qualified formulae and casks would otherwise be skipped by `brew upgrade`.
`workstation-brew-trust.service` re-derives the whole trust set before every uupd
run so you never trust a package by hand; the unit, its ordering and why it is
best-effort are in [subsystems/packages.md](subsystems/packages.md). Three
consequences of that design are yours to operate, and none of them is obvious.

The file the unit reads is the *image*
Brewfile seed at
`/usr/share/workstation-os-image/dotfiles/dot_config/homebrew/create_Brewfile`,
not your live `~/.config/homebrew/Brewfile`. A tap-qualified line you add
locally is therefore trusted only once `wjust sync` has captured it into that
seed — `tooling/data/dotfiles.manifest` maps the pair with
`copy|.config/homebrew/Brewfile|dot_config/homebrew/create_Brewfile|-` — and the
resulting image is published and deployed. Until then uupd's `brew upgrade`
keeps skipping it.

There are two trust stores, and only one of them is seeded. `brew trust` writes
`$XDG_CONFIG_HOME/homebrew/trust.json` when that variable is set and
`~/.homebrew/trust.json` otherwise, so the unit exports `HOME=/home/linuxbrew`
and unsets `XDG_CONFIG_HOME` to land on `/home/linuxbrew/.homebrew/trust.json` —
the store uupd's `brew upgrade` reads. An interactive `brew upgrade` in your own
shell reads your own store instead, which nothing seeds, so it can skip a
tap-qualified formula that uupd upgrades. Start `uupd.service` rather than
running `brew upgrade` by hand.

Trust is also not installation, so run this once after a deploy that added
Brewfile entries:

```bash
wjust brew-apply
```

`wjust audit` flags entries that are declared but missing.

---

## Recovering

### Read the state before you change it

```bash
sudo bootc status --verbose
rpm-ostree status -v
ostree admin status
```

These answer three different questions: what bootc thinks it is tracking, what
mutations the deployment carries, and which deployments actually exist on disk.
Then roll back if the answer calls for it:

```bash
sudo bootc rollback
systemctl reboot
```

### Read the per-unit journal

Most first-boot problems are one user unit that failed, not a broken image. Each
has its own journal:

```bash
journalctl --user -u workstation-bootstrap.service -b
journalctl --user -u workstation-chezmoi-init.service -b
journalctl --user -u workstation-microsoft-fonts.service -b
journalctl --user -u workstation-dms-settings.service -b
journalctl --user -u workstation-claude-mcp-seed.service -b
```

Note `--user`: these are user units, and the system journal will not show them.

> Do not delete a state marker to force a seed to re-run. A re-runnable seed
> here keys on a hash of its own script, not on a bare marker file:
> `system_files/usr/libexec/workstation-bootstrap-user` computes
> `script_hash="$(tr -d "[:space:]" <"$0" | sha256sum | cut -d " " -f 1)"` and
> re-runs whenever that hash differs from
> `~/.local/state/workstation-os-image/bootstrap-complete`. Deleting the marker
> forces one extra run and tells you nothing; fixing the script re-runs it
> automatically, on every account, forever. [conventions.md](conventions.md)
> covers the mechanism and the failure that produced it.

The one deliberate exception is the DMS preference seed:
`system_files/usr/bin/workstation-apply-dms-settings` in `--initialize` mode
exits early when `~/.local/state/workstation-os-image/dms-settings-initialized`
exists, because DMS settings are UI-owned after their seed and re-running would
stomp your edits. Restoring the tracked overlay is therefore an explicit act:

```bash
wjust dms-apply
```

It prompts (`Overwrite live DMS settings from the tracked overlay?`) and then
runs the applier with `--force`, which ignores the marker. Only run it when you
intend to overwrite live DMS settings; the capture direction, and what belongs
in the overlay at all, is [capturing-changes.md](capturing-changes.md).

### Check that anything is updating at all

```bash
wjust update-status
```

This runs `tooling/audit/updates`. It reports whether `uupd.timer` is enabled
and active, when it next elapses, and `uupd.service`'s last `Result` and
`ExecMainStatus`. It exists because uupd notifies with one generic title for
every module, so a failure tells you something broke without telling you what —
the script scopes the journal to the last invocation via
`_SYSTEMD_INVOCATION_ID` and prints every JSON record above `INFO` verbatim,
which is where the failing module's name is. It deliberately does not parse a
failure schema, since no run on this machine has ever emitted a record above
`INFO` and any field names would be guessed.

It exits non-zero on a masked or stopped timer, and the comment records why that
check is there: `uupd.timer` was once found masked via
`/etc/systemd/system/uupd.timer -> /dev/null`, which no image can undo. That is
the `/etc` three-way merge biting — see
[validation-and-gates.md](validation-and-gates.md) for why machine audits exist
alongside build gates.

---

## Housekeeping

Two recipes cover the things nothing automatic does.

| Recipe | What it does | Why it is manual |
|---|---|---|
| `wjust flatpak-prune` | `flatpak uninstall --unused` | uupd updates Flatpaks but never prunes — it has no such option — so orphaned runtimes accumulate as apps change or are removed |
| `wjust clean` | Removes `localhost/<image>:review-*` Podman images and untracked tool byproducts | `gitleaks dir .` does not respect `.gitignore`, so anything left in the checkout is inside the secret-scan surface |

`flatpak-prune` is guarded by
`[confirm("Remove every unused Flatpak runtime from this account?")]`. It is
interactive and confirmed rather than wired into the update path, because it
deletes data and a nightly job that silently removes things is the wrong
default.

`clean` mirrors `.gitignore` and deliberately goes no further: it deletes the
local review images, `.playwright-cli`, `.agents`, `.claude/skills`,
`.codex/skills`, `.playwright`, `nvim.log` and `skills-lock.json`. It is what
you run before `wjust validate` when a tool has scattered scratch files through
the checkout.

---

## Adopting a Changed Default

Create-only chezmoi targets and the one-time DMS preference seed both
intentionally preserve later user edits. That is the point of them: a `create_`
entry seeds a file that does not exist and never touches one that does, so your
edits win over the image's default for as long as the account lives.

The consequence is that changing a default in this repository does **not**
change it on an account that already has the file. Adopting one is a deliberate
act. For a chezmoi target: review the new seed, keep a copy of whatever you had
edited, delete the live file, and let `workstation-chezmoi-update.service`
re-create it — its timer fires 5 minutes after boot and daily thereafter, or
start it now:

```bash
systemctl --user start workstation-chezmoi-update.service
```

This asymmetry does **not** apply to `scaffold` manifest entries. Those are
image-owned, and `/usr/libexec/workstation-chezmoi-apply` forces the paths named
in `/usr/share/workstation-os-image/scaffold-targets` on every run — an edit to
one of them is reverted rather than preserved, and a target that has diverged is
repaired rather than skipped forever. See
[scaffold-force-apply.md](design-records/scaffold-force-apply.md).

For DMS the equivalent is `wjust dms-apply`, above.
[capturing-changes.md](capturing-changes.md) covers the capture direction; this
is the same asymmetry seen from the other side.

---

## Where to go next

If the update you were waiting for never appeared, [build-and-ci.md](build-and-ci.md)
explains what triggers a build, which tags it publishes and why a
`tooling/`-only merge publishes nothing. If a verification or policy question
came out of this page, [supply-chain.md](supply-chain.md) owns signing,
`policy.json` and key rotation. And when a drift report from `wjust audit` needs
turning into a committed change, start at
[capturing-changes.md](capturing-changes.md).
