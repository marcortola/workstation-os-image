# Packages

Where a piece of software is declared, and why it is declared there rather than
somewhere else. Read this before adding anything to the machine: picking the
wrong declaration site is the difference between a change that survives the next
rebase and one that quietly disappears.

**Ownership picks the site: if the system needs it to boot, log in or run
privileged, it is an RPM baked into the image; if only the logged-in user needs
it, it is Homebrew or Flatpak; if only one project needs it, it belongs in that
project's dev container and not on the host at all.**

---

## The decision table

| What you are adding | Declare it in | Applied by |
|---|---|---|
| OS package, daemon, privileged helper, anything that must exist under `/usr` before login | a `.list` under `build_files/packages/` | `build_files/20-packages.sh` at build time |
| Something no repository packages, that has to be compiled or unpacked | `build_files/00-toolchain.sh`, pinned by a `sha256` `ARG` in the `Containerfile` | the `toolchain` build stage |
| A CLI tool the user runs | `~/.config/homebrew/Brewfile` | `just brew-apply` now, `uupd` daily thereafter |
| A GUI application | a `flatpak` line in the same Brewfile | `just brew-apply` |
| A language runtime, SDK or project-specific toolchain | neither — the project's dev container | `dev`, see [dev-environment.md](dev-environment.md) |
| A third-party AI CLI | the Brewfile or `just ai-tools-install`; never vendored | see [ai-clis.md](ai-clis.md) |

The Brewfile is personal configuration, not image payload: it lives at
`~/.config/homebrew/Brewfile` in the account and is captured into the chezmoi
source through one manifest line,

```text
copy|.config/homebrew/Brewfile|dot_config/homebrew/create_Brewfile|-
```

so `just sync` refreshes the seed from the live file and the `create_` prefix
means an existing account's own Brewfile always wins over the seed. The capture
side of that is [../capturing-changes.md](../capturing-changes.md).

---

## The RPM lists

`build_files/20-packages.sh` iterates `build_files/packages/*.list` and runs one
`dnf5` transaction per list, `exclude.list` excepted, "so a failure names the
group it came from rather than dumping one 200-package error". Every transaction
is installed with
`--setopt=install_weak_deps=False --setopt=keepcache=1` and with the contents of
`exclude.list` passed as `--exclude=` arguments.

| List | What it is for |
|---|---|
| `copr.list` | The DankMaterialShell stack: `dms`, `dms-cli`, `dms-greeter`, `quickshell`, `dgop`, `danksearch`, `matugen` |
| `desktop.list` | Compositor, session and shell: niri, XWayland, greetd, foot, the keyring stack, Nautilus and gvfs, DMS's undeclared runtime dependencies, power profiles, and the CLI tools the binds and our own scripts call |
| `dev.list` | Toolchain and CLI: `binutils` and `gcc` (Homebrew needs a linker and a compiler for source builds), `mariadb`, `postgresql`, `mkcert`, the screen-recording pair `slurp` and `wf-recorder`, and four that look like base duplicates but have named consumers here — `cpio` and `unzip` for `workstation-install-microsoft-fonts`, `cabextract` for the `refresh-msttcore-fonts.sh` helper it runs, `shadow-utils` for `workstation-configure-user-groups` |
| `docker.list` | Rootful Docker: `docker-ce`, `docker-ce-cli`, the buildx and compose plugins, `containerd.io` |
| `fonts.list` | Default and emoji fonts plus `glibc-all-langpacks` |
| `input-method.list` | The fcitx5 stack, which base-main installs only for its kinoite variant |
| `insync.list` | `insync`, alone |
| `media.list` | `gstreamer1-plugins-ugly` from negativo17, and `unar` for RAR5 |
| `qt-style.list` | The Qt/QML modules DMS imports at runtime but does not declare |
| `terra.list` | `uupd`, `satty`, `iio-niri`, `maple-fonts`, `xdg-terminal-exec-nautilus` |
| `exclude.list` | Packages that must never be installed, even as a dependency. Skipped as an install group by name |

Two of those lists are worth reading in full before touching them. `qt-style.list`
exists because `rpm -qR dms` declares "only quickshell, dgop, dms-cli,
accountsservice, python3 and bash -- none of the QML modules it imports at
runtime", and a missing one produces a compositor that starts and a shell that
silently dies — a failure no container gate can catch. The same reasoning covers
the `cava`, `khal` and `swaybg` block in `desktop.list`. `exclude.list` currently
holds `fluid-soundfont-lite-patches` and `fluid-soundfont-common`, which
negativo17's `gstreamer1-plugins-bad` would otherwise drag in as 186 MiB of MIDI
samples nothing here plays.

`20-packages.sh` also removes `ublue-os-update-services` outright, because it
schedules the same paths `uupd` covers and it does so through priority-10 preset
files — disabling its timers is not durable, but removing the package removes the
presets.

---

## Compiled and pinned inputs

Three things are packaged nowhere. `build_files/00-toolchain.sh` compiles or
unpacks them in the `toolchain` stage into `/staging`, which the final stage
copies in wholesale with `COPY --from=toolchain /staging/ /`:

- `workstation-x11-clipsync`, compiled from `build_files/src/`, mirroring the X11
  CLIPBOARD selection into the Wayland clipboard for XWayland clients that never
  hand it over.
- **keyd**, built from a tarball pinned by `KEYD_VERSION` and `KEYD_SHA256`.
  Only the daemon, its unit and its sysusers group are kept.
- **FiraCode Nerd Font**, unpacked from a release pinned by `FIRACODE_VERSION`
  and `FIRACODE_SHA256`. It is referenced by `fonts.conf` and by the DMS
  `monoFontFamily` setting, and before it was baked it resolved from
  `~/.local/share/fonts` — owned by no package, so a fresh account rendered every
  Nerd Font glyph as tofu. `build_files/30-desktop.sh` rebuilds the cache with
  `fc-cache --force --really-force --system-only` afterwards, and
  `99-check-build.sh` fails the build unless `fc-list` reports
  `FiraCode Nerd Font Mono` — the exact family name the two consumers ask for.

`tooling/validate/image-build` asserts the literals `KEYD_SHA256=` and
`FIRACODE_SHA256=` are still present in the `Containerfile`, so the pins cannot
be quietly dropped.

---

## Host tuning

Four files in `system_files/` install nothing and change how the kernel and the
journal behave. They are plain drop-ins under `/usr/lib`, which is where an
image update always lands, so none of them is subject to the `/etc` merge
described in [../conventions.md](../conventions.md). No build script and no gate
references them; they ship because they are in the payload.

| File | Sets |
|---|---|
| `system_files/usr/lib/sysctl.d/99-workstation-inotify.conf` | `fs.inotify.max_user_watches = 524288`, `fs.inotify.max_user_instances = 1024` |
| `system_files/usr/lib/systemd/journald.conf.d/10-workstation.conf` | `SystemMaxUse=50M`, `RateLimitBurst=500`, `RateLimitIntervalSec=30s` |
| `system_files/usr/lib/systemd/zram-generator.conf.d/99-workstation.conf` | `zram-size = min(ram / 2, 16384)`, `compression-algorithm = zstd` |
| `system_files/usr/lib/sysctl.d/99-workstation-zram.conf` | `vm.swappiness = 180` |

Nothing else under `/usr/lib/sysctl.d` sets the inotify limits, so without that
first file the kernel defaults stand — and they are what a language server
indexing a repository and a node dev server watching the same tree consume
between them. Exhausting a watch limit does not raise an error the user sees;
the editor simply stops noticing that files changed.

The journald numbers carry a measured rationale in the drop-in's own comment,
and it is the non-obvious half that matters: the byte budget was never the
binding constraint.

```text
# SystemMaxUse alone. SystemMaxFiles=5 was the binding constraint, not the
# byte budget: journald sizes each file at 1/8 of SystemMaxUse, so five files
# capped the journal near 31M and it never reached 50M. Measured before this
# change: 24.1M on disk holding 5.5 hours of history, which is too short to
# investigate anything that happened yesterday.
```

Five and a half hours of retention is useless for the thing the journal is for
here — reading back what a first-boot unit did last night. The rate limit is
raised in the same file so a chatty unit cannot drop its own evidence. What
`zram` is and why `vm.swappiness = 180` pairs with it is in
[../glossary.md](../glossary.md).

---

## Vendored repositories

Every third-party repository is a reviewed `.repo` file under
`build_files/repos/`, installed by `build_files/10-repos.sh`, never fetched from
a vendor at build time — "a remote repofile's baseurl and gpgkey silently become
this build's trust anchors on whatever day it runs". The vendored signing keys
are installed and imported first, because each `.repo` references its key by
`file://`.

Each repo carries a four-way fence, and each part of it is gated in
`tooling/validate/image-build`:

| Requirement | Why | Gate |
|---|---|---|
| `gpgcheck=1` | unsigned packages are not installable | `grep -q '^gpgcheck=1'` |
| `gpgkey=file://` | the key is vendored and reviewable, not handed over at build time | `grep -q '^gpgkey=file://'` |
| `https` `baseurl` or `metalink` | cleartext plus `skip_if_unavailable` is a downgrade window with no alarm | two greps: `^(baseurl\|metalink)=http://` fails, `^(baseurl\|metalink)=https://` is required |
| `includepkgs=` | the repo can contribute nothing but its allowlist | `grep -q '^includepkgs='` |

The `includepkgs` rule is not theoretical. On the previous base, Terra shipped
`sdbus-cpp.terra`, which satisfies `libsdbus-c++.so.2` for `dnf5` itself: a
third-party repository at elevated priority replaced a library Fedora's own
package manager links against. An allowlist makes that structurally impossible
rather than merely unlikely.

| File | Provides | Notes |
|---|---|---|
| `copr-yalter-niri.repo` | `niri` | `priority=1`, so it wins even if Fedora later packages niri |
| `copr-avengemedia-dms.repo` | `dms`, `dms-cli` | DankMaterialShell proper |
| `copr-avengemedia-danklinux.repo` | `dms-greeter`, `quickshell`, `dgop`, `danksearch`, `matugen`, `cpptrace` | `cpptrace` is mandatory: quickshell links `libcpptrace.so.1` |
| `docker-ce.repo` | the five Docker packages plus `docker-ce-rootless-extras` | `rootless-extras` is listed only because `docker-ce` pulls it |
| `insync.repo` | `insync` | one repository for one package, and the only one here that sets `skip_if_unavailable=True` |
| `terra.repo` | `uupd`, `satty`, `satty-bash-completion`, `iio-niri`, `maple-fonts`, `xdg-terminal-exec-nautilus` | `priority=100`; a higher number is a lower priority in dnf, so Terra deliberately loses to negativo17's default 99 on any overlap |

None of these ship. `build_files/90-cleanup.sh` runs

```bash
find /etc/yum.repos.d -name '*.repo' \
    ! -name 'fedora*.repo' \
    ! -name 'negativo17*.repo' \
    -delete
```

so the deployed image ships only what that filter spares: Fedora's own
`fedora*.repo` files, `fedora-cisco-openh264.repo` among them, and base-main's
`negativo17-fedora-multimedia.repo`. `99-check-build.sh` compensates for what
that deletion makes uncheckable at the end of the build: it asserts all six
vendored `.asc` keys shipped to `/etc/pki/rpm-gpg/`, and it asserts provenance
directly, `assert_vendor niri 'yalter'`, `assert_vendor dms 'avengemedia'`,
`assert_vendor uupd 'Terra'`, `assert_vendor systemd 'Fedora Project'` and
`assert_vendor dnf5 'Fedora Project'` — so a package silently changing vendor
fails the build. Key vendoring and rotation are
[../supply-chain.md](../supply-chain.md).

---

## Floating COPRs and the NEVRA manifest

The desktop stack cannot be pinned. As `copr.list` puts it, those COPRs "float
permanently: COPR prunes superseded builds, so versionlock to an older NEVRA is
impossible". Bisectability is the substitute. `90-cleanup.sh` bakes a sorted
NEVRA manifest of everything installed:

```bash
rpm -qa --qf '%{NAME}-%{EPOCH}:%{VERSION}-%{RELEASE}.%{ARCH}\n' \
    | sed 's/-(none)://' | sort > /usr/share/workstation-os-image/package-manifest.txt
```

CI diffs that file against the published image, so "the desktop broke this week"
becomes "niri went 26.04 -> 26.05 on Tuesday". The manifest is on the running
machine too, at the same path. See [../build-and-ci.md](../build-and-ci.md) for
where the diff runs.

---

## Codecs and negativo17

negativo17 (`fedora-multimedia`) already ships in base-main, but with
`enabled=0` and no `priority=` line. base-main enables it during its own build,
installs `ffmpeg`, `ffmpeg-libs`, `libavcodec` and `fdk-aac` from it, then
disables it again — which is why `media.list` does not repeat those four.
`10-repos.sh` turns it back on with
`dnf5 -y config-manager setopt fedora-multimedia.enabled=1` so
`gstreamer1-plugins-ugly` can be pulled, and `90-cleanup.sh` sets it back to `0`.
The repo file itself survives cleanup and ships disabled.

RPM Fusion is gone entirely, and that has consequences worth knowing: `unar`
rather than `unrar` (Fedora's `unrar` is a wrapper around `unrar-free`, which
does not handle RAR5), and `99-check-build.sh` fails the build outright if
`libavcodec-freeworld` ever appears, because it file-conflicts with negativo17's
`libavcodec`.

> negativo17's repo file is owned by base-main and still fetches its key over the
> network. We do not rewrite it, because a base-owned repo file would collide
> with future base updates. The chain still has a defined root: the base is
> digest-pinned and cosign-verified before this image builds on it.

---

## Homebrew

Homebrew carries the user's CLI tools — the things that change often, that no
one wants to rebuild an OS image for, and that need no privilege. It arrives as
a digest-pinned image layer rather than an installer: the `Containerfile` has a
`brew` stage and copies `/system_files/` out of it, which delivers
`/usr/share/homebrew.tar.zst` and `brew-setup.service`. That service unpacks the
prefix on first boot and chowns it to `1000:1000`. `99-check-build.sh` asserts
both the payload and the unit are present. Never install Homebrew by hand: the
image ships `bin/brew` as a symlink into `../Homebrew/bin/brew`, ublue's own
`brew-update.service` and `brew-upgrade.service` gate on
`ConditionPathIsSymbolicLink` against that exact path, and `tooling/audit/packages`
fails if it is anything else.

The Brewfile is the single declaration of what belongs in that prefix, and it
declares three kinds: `brew` formulae, `cask` entries, and `flatpak`
applications. **The file is the inventory; this page does not restate it.** Read
`system_files/usr/share/workstation-os-image/dotfiles/dot_config/homebrew/create_Brewfile`
for the current set — sixty declarations today. `brew "pandoc"` is the shape to
copy for a plain formula; `brew "starship"` is the shape for one whose
configuration then ships separately as a chezmoi seed, covered in
[desktop-session.md](desktop-session.md).

> Never add btop, chezmoi, Git, fzf, Just or Fish to the Brewfile. The image
> installs `btop` and `chezmoi` in `desktop.list` (`just audit` and the chezmoi
> seeding both die without the latter), base-main provides `fzf`, `just` and
> `/usr/bin/git` (from `git-core`), and the image owns `/usr/bin/fish` — a
> Homebrew Fish would shadow the login shell the session was built around.

### Image-provided shadows

Some of those names still end up in the brew prefix anyway — as a dependency of
a formula that was declared, or left behind by an earlier install.
`tooling/data/image-provided-brew-formulae` is the list of formulae the
image itself owns — currently `btop`, `cabextract`, `chezmoi`, `ffmpeg`, `fzf`,
`git`, `just`, `mkcert` and `unar` — and `tooling/audit/packages` is its only
consumer. That script computes the formulae installed but not declared, then
splits them:

```bash
comm -23 "$tmp/installed.formula" "$tmp/declared.formula" > "$tmp/extra.formula"
comm -12 "$tmp/extra.formula" "$tmp/image-formulae" > "$tmp/shadowed.formula"
comm -23 "$tmp/extra.formula" "$tmp/image-formulae" > "$tmp/unknown.formula"
```

Anything in `unknown.formula` is printed as `undeclared` and sets `status=1`;
anything in `shadowed.formula` is printed as `image-shadow` and changes nothing.
Without the file, any of those nine present in the prefix would land in
`unknown.formula` and `just audit` would fail on a machine that is in fact
perfectly consistent. For `btop`, `chezmoi`, `fzf`, `git` and `just` the trap
closes: the usual fix for an `undeclared` report, adding the name to the
Brewfile, is exactly what the never-add rule forbids.

### Trust

`workstation-brew-trust.service` re-derives the trust set from the Brewfile on
every boot. It runs `User=1000` (the uid `brew-setup.service` chowns the prefix
to; the image creates no `linuxbrew` account — that one came with brew-proxy and
left with it), orders `After=brew-setup.service`, and carries
`ConditionPathExists=/home/linuxbrew/.linuxbrew/bin/brew` so a boot before the
prefix exists is a clean no-op rather than a failed unit. The helper reads the
image's Brewfile *seed* at
`/usr/share/workstation-os-image/dotfiles/dot_config/homebrew/create_Brewfile`,
treats any `brew`/`cask` line whose quoted argument contains a slash as
tap-qualified, and runs `brew trust` on each. It is best-effort by design and
always exits 0, so one bad entry never blocks the upgrade that orders after it.
A `uupd.service` drop-in adds `Wants=`/`After=workstation-brew-trust.service`,
which is what actually guarantees the trust store is fresh before `uupd` runs
`brew upgrade` — a boot-time `Before=uupd.service` would be inert, since
`uupd.service` is static and only the timer pulls it in.

The consequence: **a tap-qualified `brew`/`cask` line is self-trusting but not
self-installing.** Adding one is enough for it to be upgraded daily; it does not
appear on an already-deployed machine until you run `just brew-apply`, which
runs `brew bundle install` against the live Brewfile. `just audit` flags entries
that are declared but missing.

### Updates

Homebrew is upgraded by `uupd`, daily, in the same run as bootc, Flatpaks and
Distrobox. The brew payload's own `brew-update.timer` and
`brew-upgrade.timer` are disabled explicitly by `build_files/50-services.sh`,
because a preset line alone cannot undo an enablement symlink another layer
already wrote, and leaving them on would give three brew update paths. `uupd` is
the single updater; [../operating.md](../operating.md) has the detail.

---

## Flatpaks

GUI applications are Flatpaks, declared in the same Brewfile as
`flatpak "app.id"` lines — `flatpak "org.filezillaproject.Filezilla"` is the
shape. As with the formulae, the Brewfile is the inventory and this page does
not duplicate it. Homebrew's bundle implementation installs them into
the *system* installation (`flatpak install -y --system <remote> <names>`,
defaulting to the `flathub` remote), so `just brew-apply` restores the GUI app
set the same way it restores formulae and casks. `tooling/audit/packages` treats
an undeclared Flatpak as a warning rather than an error, deliberately: "a
workstation may keep host-only Flatpaks that should not always ship in the
image". Undeclared formulae and casks stay errors.

Per-application sandbox adjustments are **Flatpak overrides**, and they are
personal config captured through the manifest like any other dotfile — two are
tracked today, one dropping `fallback-x11` for 1Password and one granting
DankCalendar read-only access to the DMS colour cache so it follows the session
palette. There is also one global override, applied by
`workstation-flatpak-wayland.service` at every login:

```ini
ExecStart=/usr/bin/flatpak override --user --socket=wayland --env=ELECTRON_OZONE_PLATFORM_HINT=auto
```

It is re-asserted on every login rather than written once, so it survives a base
rewrite of the global override file, and it carries `ConditionUser=!@system` so
it does not also run in greetd's greeter user manager against a read-only home —
one instance of the mechanism [../conventions.md](../conventions.md) sets out.
The XWayland drag-and-drop gap it works around is
[desktop-session.md](desktop-session.md).

`uupd` updates Flatpaks but never prunes them — it has no such option — so
orphaned runtimes accumulate as applications change. `just flatpak-prune` runs
`flatpak uninstall --unused`, which lists what it would remove and waits for a
yes. It is deliberately not wired into the nightly update path: it deletes data.

---

## What the image deliberately does not install

- **Language runtimes and SDKs.** No `.list` declares node, a PHP stack, a JVM
  or a Go toolchain. Language intelligence and build tools live in the project's
  dev container, reached with `dev` — see
  [dev-environment.md](dev-environment.md). The one host-side concession is the
  `devcontainer` CLI itself, a Brewfile formula.
- **Browsers.** This repository adds no browser RPM. Chrome is the
  `com.google.Chrome` Flatpak, and `workstation-playwright-chrome` attaches
  `playwright-cli` to that Flatpak over CDP precisely so no second browser is
  layered into the image. (base-main's own Firefox is inherited, not declared
  here.)
- **Microsoft fonts.** Nothing is baked; using them means accepting Microsoft's
  EULAs, which is a per-user act, not an image one.
  `workstation-install-microsoft-fonts` fetches them from their original
  distributors into `~/.local/share/fonts` and refuses to run without
  `--accept-microsoft-eula`; the enabled user unit
  `workstation-microsoft-fonts.service` passes that flag, so a fresh account gets
  them at first login without a manual step. Its marker records a hash of the
  script rather than the bare fact that it ran, so editing the installer re-runs
  it instead of becoming dead code.
- **A second updater.** `ublue-os-update-services` is removed and Fedora's
  `dnf-makecache.timer` is disabled: nothing installs from dnf at runtime on an
  image-mode system, so the metadata refresh is pure wakeups.

---

## Gotchas and tech debt

- `tooling/data/image-provided-brew-formulae` silences the audit; it does not
  change resolution order. The `niri.service` drop-in `10-homebrew-path.conf`
  prepends the brew prefix to the session `PATH`, so where a shadowed formula
  really is installed in the prefix the Homebrew copy is the one that runs,
  despite the file's header calling the image binaries authoritative. Check with
  `brew list --formula` before assuming `/usr/bin` won.
- `brew bundle check` fails with "needs to be installed or updated" for a package
  that is installed but merely *outdated*, because its
  `installed_and_up_to_date?` predicate covers both. A `just audit` failure from
  that line is therefore not proof that something is missing; confirm with
  `brew list` before adding anything to the Brewfile.
- The two trust paths are not symmetrical. The system unit matches `brew` *and*
  `cask` lines; the first-login path in `workstation-bootstrap-user` matches only
  `brew` lines, so a tap-qualified cask is trusted in the prefix's store (which
  `uupd` reads) but not in the user's own.
- Every group list is installed in its own transaction, but no gate asserts a
  list is non-empty or that every name in it landed. `20-packages.sh` skips an
  empty list with `[ "${#pkgs[@]}" -gt 0 ] || continue`, and `99-check-build.sh`
  re-checks a fixed 39-name subset with `rpm -q`; anything outside that subset
  can stop being installed without the build noticing.
- The Flatpak *remotes* are set up once by the base's
  `flatpak-add-fedora-repos.service`, which is gated on
  `ConditionPathExists=!/var/lib/flatpak/.ublue-initialized` and touches that
  marker in `ExecStartPost`. A remote the base adds, removes or retargets later
  therefore never reaches an already-provisioned machine; fixing one is a manual
  `flatpak remote-*` on the host.

---

## Where to go next

If you are adding software, [../cookbooks.md](../cookbooks.md) has the
copy-paste form of each declaration site and
[../capturing-changes.md](../capturing-changes.md) covers getting a Brewfile or
override change out of the live account and into the repository. If you are
tracing why a package is where it is, [../conventions.md](../conventions.md)
explains the ownership rules this page applies, and
[../validation-and-gates.md](../validation-and-gates.md) says which gate proves
which half of them. For the trust anchors behind the vendored repositories, read
[../supply-chain.md](../supply-chain.md).
