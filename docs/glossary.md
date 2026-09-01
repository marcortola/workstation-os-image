# Glossary

Every term this handbook uses that is not plain Linux vocabulary, defined once and
in alphabetical order. Where a term belongs to a page, the definition links it and
stops there rather than restating that page.

**Most entries name a mechanism that exists because its absence broke something here; the definition says which.**

---

## A–C

| Term | Definition |
|---|---|
| **audit** | `just audit` runs `tooling/audit/workstation`, which chains the deployment, unit, `/etc`-drift, update, package and dotfile audits. Audits assert the *machine*; the build gates assert the *image*. See [validation-and-gates.md](validation-and-gates.md). |
| **base-main** | `ghcr.io/ublue-os/base-main`, the Universal Blue image this one layers on, pinned by digest in the Containerfile's `BASE_IMAGE` ARG. It was chosen because it ships Fedora with the codec stack, brew's sudoers path and Flathub already sorted, and adds no compositor or greeter that would have to be stripped before installing niri. |
| **bootc** | The tool that boots a container image as the operating system and applies updates transactionally in place. This image uses `upgrade`, `switch`, `rollback` and `status` on a machine, and `bootc container lint` at build time. |
| **`bootc container lint`** | The last thing the Containerfile runs, with `--fatal-warnings`. It rejects, among other things, a regular file left in `/var`: `/var` is populated only at initial provisioning, and a regular file cannot be expressed as a tmpfiles entry, so nothing would ever recreate it — which is why `90-cleanup.sh` deletes `/var/cache/ldconfig/aux-cache`. |
| **Brewfile** | `~/.config/homebrew/Brewfile`. The single declaration site for user CLI tools, casks and Flatpaks, seeded create-only by chezmoi. See [subsystems/packages.md](subsystems/packages.md). |
| **capture** | Taking a reviewed live change into the repository. `just capture` runs `sync`, then `validate`, then shows the Git status and diff. See [capturing-changes.md](capturing-changes.md). |
| **chezmoi** | The dotfile manager that applies the image's seed tree at `system_files/usr/share/workstation-os-image/dotfiles/` into a user's home. `workstation-chezmoi-init.service` seeds a new account and `workstation-chezmoi-update.timer` reapplies daily. |
| **chezmoi `create_` entry** | A source file whose basename is prefixed `create_`, which chezmoi writes only if the target does not already exist. Every personal default uses it so a later user edit wins permanently. |
| **`ConditionUser`** | The systemd unit condition every user unit here carries as `ConditionUser=!@system`. Without it the unit also runs in the user manager `pam_systemd` starts for greetd's `greeter` account, whose home is read-only, and fails on every login screen. See [conventions.md](conventions.md). |
| **COPR** | Fedora's community build service. Three COPR repositories are vendored here: `yalter/niri`, `avengemedia/dms` and `avengemedia/danklinux`. |
| **COPR float** | The consequence of COPR pruning superseded builds: an older NEVRA cannot be versionlocked, so the whole desktop stack tracks COPR HEAD permanently. The package manifest baked into each image is the bisectability substitute for a pin. |
| **cosign** | The sigstore signing CLI. `tooling/validate/source-images` uses it to verify both digest-pinned input images against `build_files/keys/ublue-os.pub` before a build, and CI uses it to sign each published digest and re-verify it against `cosign.pub`. See [supply-chain.md](supply-chain.md). |

---

## D–G

| Term | Definition |
|---|---|
| **DankCalendar** | The `com.danklinux.dankcalendar` Flatpak, declared in the Brewfile rather than installed as an RPM. A captured Flatpak override grants it read-only `xdg-cache/DankMaterialShell` so it follows the session palette, and a captured XDG autostart entry starts its daemon at login. |
| **DankMaterialShell (DMS)** | The Material 3 shell for Wayland compositors that provides the bar, launcher, lock screen, notifications and settings on top of niri. Installed as the `dms` and `dms-cli` RPMs from `copr:avengemedia/dms`. See [subsystems/desktop-session.md](subsystems/desktop-session.md). |
| **DankSearch** | The `danksearch` RPM, which ships `/usr/bin/dsearch` and `dsearch.service` — the unit is **not** named `danksearch.service`. It backs the DMS launcher's `/` file search. |
| **deployment (A/B)** | An ostree-managed bootable root. A machine keeps two of them — the booted one and the previous one as a rollback, which is what "A/B" refers to — and a freshly pulled update sits **staged** until reboot; `bootc rollback` reaches exactly one deployment back and discards any staged entry. See [operating.md](operating.md). |
| **dev container** | A containerised project environment, declared by `.devcontainer/devcontainer.json` (or `.devcontainer.json`) in a project directory. The `dev` shell function walks up from the current directory to the repository root and runs a command in the nearest one, starting it on demand. |
| **`dev nvim`** | Runs the *host* Neovim configuration inside the project's dev container, so language servers and debuggers see the project's real dependencies. See [subsystems/dev-environment.md](subsystems/dev-environment.md). |
| **dgop** | A system-monitoring CLI and REST API from `copr:avengemedia/danklinux`, which DMS's resource widgets read. |
| **digest pin** | Referring to an image as `name@sha256:...` rather than by tag, so the reference cannot move. Both build inputs (`base-main` and the ublue `brew` layer) are pinned this way, and CI signs the digest rather than the tag for the same reason. |
| **DMS settings overlay** | `system_files/usr/share/workstation-os-image/dms-settings.json` — the reviewed subset of DMS preferences this image ships. DMS owns the live settings file after the one-time seed. |
| **dotfiles manifest** | `tooling/data/dotfiles.manifest`, the only inventory of captured personal configuration. Each line is `kind`, live path relative to `$HOME`, chezmoi source path and file pattern, separated by pipes; the kinds are `copy`, `template`, `scrub`, `scaffold`, `directory`, `tree` and `jetbrains-app`. |
| **drift** | Divergence between the live machine and this repository's declared source. It comes in two kinds — a tracked item whose live value changed, and an item not tracked at all — and both must be reported. See [capturing-changes.md](capturing-changes.md). |
| **drop-in** | A `.conf` fragment under `<unit>.d/` that merges into a unit without replacing it. Named `NN-<concern>.conf` here and never `override.conf`, because that is the filename `systemctl edit` writes: a local edit would displace the image's file instead of sitting beside it. |
| **`environment.d`** | `/usr/lib/environment.d/*.conf`, the session environment for the systemd user manager. Session variables go here and never in `/etc/profile.d`, because the session is `niri.service` under the user manager and never sources a login shell. |
| **`/etc` three-way merge** | ostree's upgrade rule for `/etc`: the image's version is applied on first deploy, and once anything rewrites the file locally it is recorded as modified and every later image version of it is silently ignored. Recording a deletion counts as a local modification too. This is why image-owned config ships via factory plus tmpfiles, and why `tooling/audit/etc-drift` exists. See [conventions.md](conventions.md). |
| **`ExecCondition`** | Where a "not ready yet" check belongs in a unit. A non-zero `ExecStart` instead reports a failed unit forever, which is the failure this convention was written against. |
| **factory (`/usr/share/factory`)** | The image-owned copy of a file destined for `/etc`, materialised by a tmpfiles `L+` line with the target omitted, which links to the same path under `/usr/share/factory`. The pair keeps the file out of the `/etc` three-way merge: `/etc` holds only a symlink while the content sits in `/usr`, which every image update replaces wholesale, so the image can still change it after first deploy. `L+` re-asserts that symlink on every boot, so an override belongs at a higher-precedence path — `~/.config/xdg-terminals.list` for the terminal list — and never in `/etc`. |
| **Flatpak override** | A sandbox permission file under `~/.local/share/flatpak/overrides/`, named for an application ID or `global` to cover every app. Two per-application ones are captured here, and `workstation-flatpak-wayland.service` re-asserts the `global` one at every login so a base rewrite cannot drop it. |
| **foot / footclient** | `foot` is the terminal emulator; `foot-server.socket` is socket-activated and `footclient` connects to it, so windows share one process. `workstation-footclient.desktop` is the entry `/etc/xdg/xdg-terminals.list` names as the system default. |
| **gate** | This repository's word for an executable assertion — a check in `tooling/validate/`, `build_files/99-check-build.sh` or an audit. The standing rule is to fix the input, never the gate; making a gate pass while the condition it asserts is false is an in-scope security issue per [SECURITY.md](../SECURITY.md). |
| **gitleaks** | The committed-secret scanner, run by `tooling/validate/all` and by the lint workflow, with `.gitleaks.toml` as its sole allowlist. It does not respect `.gitignore`, so anything left in the checkout is inside the scan surface — the reason `just clean` exists. |
| **greetd** | The minimal login daemon. `/etc/greetd/config.toml` starts `dms-greeter --command niri` on VT 1. It is shipped straight into `/etc` rather than via factory plus tmpfiles, because the greetd RPM already owns that path as a `%config` file and a tmpfiles symlink would never be created. |
| **greeter** | The unprivileged account greetd runs the login session as, with a read-only home. Its user manager reaches `default.target` like any other, which is what `ConditionUser=!@system` and the `10-skip-system-users.conf` drop-ins guard against. |

---

## H–N

| Term | Definition |
|---|---|
| **herdr** | The terminal agent multiplexer installed from the Brewfile, with a `Ctrl+G` prefix and one default session. It labels each pane's coding agent as working, blocked, done or idle in a sidebar, which is why it replaced tmux; an agent started outside a herdr pane never reaches that sidebar. |
| **`image.env`** | The one file that declares this image's identity: `IMAGE_NAME`, `REPO_ORGANIZATION`, `IMAGE_DESC` and `OS_NAME`. The Justfile, the audits, CI and the image itself all read it, and `tooling/validate/image-build` fails if the Containerfile ARG defaults drift from it. A fork edits this file. See [forking.md](forking.md). |
| **image-provided brew formula (shadow)** | A Homebrew formula whose command the image already provides in `/usr/bin` — btop, chezmoi, git, just, fzf and others. `tooling/data/image-provided-brew-formulae` lists the known ones and the image binary is the authoritative one. |
| **include order / last-definition-wins** | niri resolves duplicate keybinds by last definition, silently, and `niri validate` does not flag the shadowing. The user's `config.kdl` includes the image's system config first, then DMS's generated fragments, then `local.kdl`; `tooling/audit/niri-binds` is what actually fails on a shadowed bind. See [subsystems/desktop-session.md](subsystems/desktop-session.md). |
| **`includepkgs`** | The content allowlist on a vendored `.repo` file, restricting it to the packages it exists to provide. Not theoretical: Terra's `sdbus-cpp` once replaced a library `dnf5` itself links against. |
| **keyd** | The keyboard remapper, built from source in the toolchain stage from a GitHub tarball pinned by version and SHA-256, because neither Fedora nor base-main packages it. Its factory config maps Caps Lock to a Control layer and the Copilot key chord to Right Ctrl. |
| **LazyVim** | The Neovim distribution this configuration builds on. Its language extras are imported from a gated list in `lua/config/lazy.lua`, so a session only loads the languages it is scoped to. |
| **`local.kdl`** | `~/.config/niri/local.kdl`, seeded create-only and included last, so it is the only include that outranks DMS's generated binds. Personal niri changes belong here and nowhere else. |
| **Mason** | Neovim's installer for language servers, linters and formatters. Inside a dev container it is scoped by `NVIM_MASON_LANGS`, so a container only ever installs its own project's language tools. |
| **matugen** | The Material You colour generator DMS drives to regenerate per-application palette files at runtime, such as `~/.config/foot/dank-colors.ini`. Runtime-generated, which is why that file is a `scaffold` entry and never drift-audited. |
| **NEVRA** | Name, Epoch, Version, Release, Architecture — the fully qualified identity of an installed RPM, and the granularity at which a version could be locked if COPR kept old builds. |
| **niri** | The scrollable-tiling Wayland compositor this desktop is built on. Its sole source is `copr:yalter/niri`, fenced with `priority=1` and `includepkgs=niri` so it wins even if Fedora later packages niri and can contribute nothing else. |

---

## O–S

| Term | Definition |
|---|---|
| **ostree** | The content-addressed filesystem-tree store underneath bootc. It supplies the deployment model, the `/etc` three-way merge and the ability to boot a previous tree unchanged. |
| **package manifest** | `/usr/share/workstation-os-image/package-manifest.txt`, baked by `90-cleanup.sh` from `rpm -qa --qf '%{NAME}-%{EPOCH}:%{VERSION}-%{RELEASE}.%{ARCH}\n'`. CI diffs it against the published image, which turns "the desktop broke this week" into a dated version change. |
| **`policy.json`** | `/etc/containers/policy.json`, the container signature policy. It is deny-by-default, base-main already trusts `ghcr.io/ublue-os`, and `40-signing.sh` merges an owner-scoped entry into it rather than replacing it — dropping the ublue entry would leave the machine unable to pull its own base. See [supply-chain.md](supply-chain.md). |
| **preset (systemd)** | `/usr/lib/systemd/{system,user}-preset/10-workstation-os-image.preset`, numbered to sort before Fedora's, and treated as the single list of enablement intent: `50-services.sh` derives its `systemctl preset` arguments from these files and `tooling/audit/units` reads the same two files as its manifest. A preset cannot undo an enablement symlink another layer already wrote, so those disables are explicit `systemctl disable` calls. |
| **quickshell** | The QtQuick desktop-shell toolkit DMS is written against. It links `libcpptrace.so.1`, so `cpptrace` has to stay inside the danklinux `includepkgs` allowlist or the install fails. |
| **rebase / switch / upgrade** | `bootc switch <ref>` targets a different image reference; `bootc upgrade` pulls the newest digest of the reference already tracked; both queue a staged deployment for the next boot. "Rebase" is rpm-ostree's name (`rpm-ostree rebase`) for what `bootc switch` does — bootc has no `rebase` subcommand. Signature enforcement is turned on once, by passing `--enforce-container-sigpolicy` to `bootc switch`. |
| **Renovate and Dependabot** | Both bump pinned inputs, and the split is deliberate. Renovate (`.github/renovate.json5`) maintains the `BASE_IMAGE` ARG; Dependabot's Docker parser only reads literal `FROM` lines, so it maintains the brew stage's digest — which is why the brew image is a named build stage rather than a `COPY --from=<image>`. |
| **`scaffold` (manifest kind)** | A dotfiles-manifest entry for a file that is image-owned, chezmoi-applied, hand-edited in the repository, and never captured from live or drift-audited. The niri `config.kdl` and `dms.kdl` entrypoints are the canonical examples. |
| **scrub filter** | An executable in `tooling/scrub/` that reads a live config on stdin and writes a secret-free, machine-neutral seed on stdout. Manifest entries of kind `scrub` name the filter, so the AI CLI seeds are secret-free by construction rather than by review. See [supply-chain.md](supply-chain.md). |
| **sigstore attachment** | The legacy simple-signing form in which a signature is stored beside the image in the registry. `40-signing.sh` generates `/etc/containers/registries.d/workstation-signing.yaml` with `use-sigstore-attachments: true` so the signature is actually fetched, and CI signs with `--new-bundle-format=false` because bootc and rpm-ostree read that form and not the new bundle format. |
| **`sigstoreSigned`** | The `policy.json` requirement type that demands a valid signature from one of the listed `keyPaths` before an image in that scope may be pulled. The entry carries two key paths when a key is mid-rotation, so a new key can be trusted a release before it starts signing. |
| **skopeo** | Inspects and copies images in a registry without pulling them into local storage. Used to inspect a published tag before switching, to list tags when rolling back further than one deployment, and in CI to move `:latest` onto the exact digest that was signed. |
| **sync** | `just sync` regenerates every create-only seed in the chezmoi source tree from the live files the manifest lists. It sweeps the whole manifest, not just what you changed. See [capturing-changes.md](capturing-changes.md). |

---

## T–Z

| Term | Definition |
|---|---|
| **tmpfiles `L+`** | A `systemd-tmpfiles` line that creates a symlink, replacing whatever is already at the path. Plain `L` creates only if the path is absent, so anything that repoints the path at runtime outlives every image after it — which is why the greeter's theme files use `L+` and are reset to the image defaults on every boot. |
| **tuned-ppd** | The provider of the `net.hadess.PowerProfiles` D-Bus name that DMS's battery widget and power-profile modal talk to. It needs `tuned` running underneath, and conflicts with `power-profiles-daemon`, the other provider. |
| **Universal Blue** | The `ublue-os` project. Three of its artefacts reach this image: the `base-main` base, the `brew` layer that carries the Homebrew payload as a build stage, and `uupd`, which is packaged in Terra rather than shipped by a ublue image. |
| **user manager** | The per-account `systemd --user` instance. Every login starts one — including one for greetd's `greeter` — which is why user units need `ConditionUser` and why session environment goes in `environment.d`. |
| **uupd** | Universal Blue's single update daemon, run nightly by `uupd.timer`, covering bootc, Flatpak, brew and distrobox in one transaction. It updates Flatpaks but never prunes their runtimes, hence `just flatpak-prune`; a polkit rule lets a `wheel` member in a local, active session start `uupd.service` without a password. See [operating.md](operating.md). |
| **watermark** | `tooling/data/zirconium-watermark`, recording the last upstream Zirconium commit reviewed against this image. `just upstream-diff` reports what changed since, and `just upstream-accept` advances it — only in the change that did the review, never to silence the diff. See [subsystems/upstream-zirconium.md](subsystems/upstream-zirconium.md). |
| **`wjust`** | `/usr/bin/wjust`, the image-owned launcher that runs any recipe from any directory, cloning the checkout to `~/projects/personal/workstation-os-image` on demand the first time and `cd`-ing into it before handing off to `just`. It ships in the image rather than as a shell alias so it reaches existing machines with every update. See [getting-started.md](getting-started.md). |
| **worktree** | A second checkout of one repository on a separate branch. herdr shells out to `git worktree add`, so the repository's `post-checkout` hook covers every creation path. See [subsystems/dev-environment.md](subsystems/dev-environment.md). |
| **`.worktreeinclude`** | The committed, per-repository inventory of gitignored files to copy into a new worktree, in gitignore syntax. Only files git ignores *and* that match are copied; tracked files never are. Every creation path reads this one file, and a second copy list is exactly what must not be added. See [subsystems/dev-environment.md](subsystems/dev-environment.md). |
| **`xdg-terminal-exec`** | The implementation of the proposed XDG Default Terminal Execution spec: it answers "give me a terminal" for the niri binds, Nautilus and anything else. It reads `/etc/xdg/xdg-terminals.list`, and a desktop entry it may select must declare the `X-TerminalArg*` keys or it silently drops `--app-id` and `--title`. |
| **xwayland-satellite** | The rootless Xwayland integration niri delegates X11 clients to. It does not bridge drag-and-drop across the X11/Wayland boundary, which is why Electron and Chromium Flatpaks are pushed onto native Wayland and why the X11 clipboard is mirrored by a user service. |
| **Zirconium** | The image this repository forked from, and the base until 2026-08-29. Its `zirconium-dev/zdots` repository is the origin of the vendored niri includes covered by the NOTICE, and it still solves the same problems on the same desktop stack, so its commits are reviewed rather than inherited. |
| **zram** | Compressed swap in RAM. Sized at `min(ram / 2, 16384)` MiB with zstd, paired with `vm.swappiness = 180` so the kernel actually prefers it over reclaim. |

---

## Where to go next

If a term sent you here from a subsystem page, go back to it — the definitions above
are deliberately short and the owning page carries the reasoning. For the mechanisms
that recur throughout (`/etc` merge, factory plus tmpfiles, `ConditionUser`,
`ExecCondition`, preset derivation) read [conventions.md](conventions.md), which
explains the failure each one was written against. For where a term's artefact
actually lives in the tree, [architecture.md](architecture.md) is the map, and
[validation-and-gates.md](validation-and-gates.md) says which gate proves which of
these claims still holds.
