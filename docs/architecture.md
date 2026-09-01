# Architecture

This page is the map: what the repository is made of, which source of truth owns
which piece of a running machine, and how an edit travels from your checkout to
a booted system. Read it before [conventions.md](conventions.md), which answers
the narrower question of where one specific change belongs.

**Three top-level trees, one rule: `system_files/` becomes the image,
`build_files/` is only read while the image is built, and `tooling/` never
leaves your checkout.**

---

## The three trees

| Directory | Holds | In the image? |
| --- | --- | --- |
| `system_files/` | The OS payload: systemd units and drop-ins, `/usr/bin` and `/usr/libexec` helpers, tmpfiles rules, `/usr/share/factory` defaults, the few `/etc` files that must be there (greetd's `config.toml`, the container signing pubkey), the image-owned niri system config under `usr/share/workstation-os-image/niri/`, the greeter theme under `greeter/`, and the chezmoi seeds under `dotfiles/`. | Yes — `COPY system_files/ /`, verbatim |
| `build_files/` | Everything the build reads and nothing it ships: the numbered build scripts, `packages/` (one `.list` per group plus `exclude.list`), `repos/` (six vendored `.repo` files, installed by `10-repos.sh` and deleted out of `/etc/yum.repos.d` again by `90-cleanup.sh`), `keys/` (the RPM signing keys under `rpm/`, plus `ublue-os.pub` for verifying the two input images), `src/` (`workstation-x11-clipsync.c`). | No — bind-mounted at `/ctx` from a `scratch` stage, never `COPY`d into a layer |
| `tooling/` | Host-side management scripts that run against a live machine, grouped by concern, plus the declarative data they read and the fixtures that let some of them run in CI. | No — not in the build context at all |

`system_files/` mirrors absolute paths, so a file's location in the tree is
exactly where it lands on disk. That is the whole convention; there is no
install manifest to keep in sync.

The asymmetry between the first two rows is deliberate. `build_files/` travels
in the `scratch` stage so its scripts and data cannot end up in a shipped layer.
`system_files/` is `COPY`d instead, because a bind mount from a stage keys the
cache on the stage result rather than on the files actually read — routing the
overlay through `ctx` would invalidate the package layer, the most expensive one
in the build, every time you edited a systemd unit.

The build scripts are named `NN-name.sh` and **the numeric prefix is the
execution order**, with gaps so a step can be inserted without renumbering
everything after it. [build-and-ci.md](build-and-ci.md) walks through all nine
and through the stages they run in.

---

## Inside `tooling/`

Twelve entries, none of which ever reaches an image layer.

| Entry | Purpose |
| --- | --- |
| `ai/` | The AI-CLI machinery: `install-ai-tools`, `uninstall-ai-tools`, `reset-ai-cli`, `test-reset`, and `build-ai-cli-bundle`, which regenerates the self-contained `ai-cli-setup/` installer. |
| `audit/` | The machine-state audits behind `just audit`. `workstation` is the aggregator the recipe invokes; it runs `deployment`, `units`, `etc-drift`, `updates`, `packages` and `dotfiles`, and `dotfiles` in turn runs `personal-config`, `dms-settings` and `niri-binds`. |
| `data/` | Repo-owned declarative source the scripts read. Glossed below. |
| `dms/` | DMS preference lifecycle: `capture` (interactive review), `defaults` (resolve the upstream schema), `validate-overlay`, and `test`. |
| `dotfiles/` | `sync` regenerates the create-only chezmoi seeds from live files per the manifest; `validate-manifest` checks the manifest itself; `preflight-migration` proves a chezmoi state migration is safe *before* you reboot into the new image. |
| `fixtures/` | Test data. `dms-settings-spec.js` is a stand-in DMS schema modelling only the keys the capture and validation paths exercise, so the CI `dms-settings-tests` job can run the DMS lifecycle on a runner with no DMS installed. |
| `jetbrains/` | `apply-settings`, `apply-plugins`, `diff`, `promote-shared`, `validate`, `ide-setup`, `intelephense-licence`. |
| `keybindings/` | `build-cheatsheet.py`, which generates the `Mod+Slash` cheatsheet from `docs/keybindings.md` and the niri binds. Backs `just cheatsheet`, runs inside `just sync`, and gates itself with `--check`. |
| `lib/` | Shared helpers the scripts source rather than duplicate: `dotfiles.sh` (seed-path and manifest primitives) and `jetbrains-xml-flatten.py`, which flattens JetBrains XML into sorted canonical key lines so attribute order and whitespace do not register as divergence while real key/value changes do. |
| `scrub/` | The filters that strip secrets and tool-injection surface out of the mixed AI-CLI seeds: `claude-settings` and `codex-config`. |
| `upstream/` | `zirconium-diff`: fetches Zirconium, filters to the profiles this image is comparable to, and reports which of our files each upstream change maps onto. Backs `just upstream-diff` and `just upstream-accept`. |
| `validate/` | The gates behind `just validate`: `all` (the aggregator), `repo`, `sources`, `image-build`, `rpm-keys`, `source-images`, `lint-nvim-seeds.lua`. |
| `worktree/` | `init` installs the post-checkout hook and a starter `.worktreeinclude` into a repo; `test-init` covers it. |

### `tooling/data/`

The declarative half: files the scripts in the other directories read.

| Entry | What it declares |
| --- | --- |
| `dotfiles.manifest` | The single inventory of captured personal config: one line per entry, each naming a capture kind, the live path relative to `$HOME`, the chezmoi source path and a file pattern. |
| `jetbrains-settings/` | The canonical IDE configuration: `_shared/` for product-neutral settings, plus `PhpStorm/` and `WebStorm/` for each product's remainder. |
| `ai-tools/` | `opencode-mcp-fragment.json`, the only tracked piece of the fusion-generated `opencode.json`. |
| `dms-settings-denylist` | DMS keys excluded from generic interactive capture because they are runtime, device-specific, sensitive, path-bound, or need nested review. |
| `niri-bind-descriptions` | Labels for the niri binds that carry no `hotkey-overlay-title`, so the generated cheatsheet can name them. Also declares, with a leading `+`, the handful of binds that exist only in the DMS-generated fragment. Asserted in both directions by `tooling/keybindings/build-cheatsheet.py`. |
| `image-provided-brew-formulae` | The Homebrew shadows the image owns — `btop`, `chezmoi`, `git`, `just`, `fzf` and friends — where the `/usr/bin` binary is authoritative and the brew copy must not be installed. |
| `zirconium-watermark` | The last Zirconium commit reviewed against this image, with the date and who reviewed it. `just upstream-diff` reports what changed since; only `just upstream-accept` advances it, and only in the change that did the review. |

---

## Root files

Fifteen tracked files sit at the top level. Every one of them is load-bearing.

| File | Purpose |
| --- | --- |
| `Containerfile` | The four-stage build. See [build-and-ci.md](build-and-ci.md). |
| `Justfile` | The recipe index; `just --list` is authoritative, not any table in these docs. |
| `image.env` | The one place the image's identity is declared (`IMAGE_NAME`, `REPO_ORGANIZATION`, `IMAGE_DESC`, `OS_NAME`). The Justfile dotenv-loads it, `tooling/audit/deployment` and CI read it, and it is `COPY`d to `/usr/share/workstation-os-image/image.env` so runtime consumers resolve the same values. A fork edits this file. |
| `README.md` | The landing pad; it carries the pitch and links into `docs/` for everything else. |
| `AGENTS.md` | The canonical policy for automated contributors: ownership rulings, invariants, the change workflow. |
| `CLAUDE.md` | One line, `@AGENTS.md`. It exists so Claude Code loads the same policy rather than a divergent copy. |
| `SECURITY.md` | CVE-triage routing and the in-scope definition — which includes making a gate in `tooling/validate/` pass while the condition it asserts is false. |
| `LICENSE` | MIT. |
| `cosign.pub` | The public half of the image signing key. See [supply-chain.md](supply-chain.md). |
| `.containerignore` | **Defines the build context.** See the note below. |
| `.gitleaks.toml` | The sole scanner allowlist: gitleaks' default ruleset plus one exemption for a public build checksum the `generic-api-key` rule misreads. See [supply-chain.md](supply-chain.md). |
| `.gitattributes` | Marks `tooling/data/jetbrains-settings/`, `tooling/ai/ai-cli-setup/` and the chezmoi seeds as vendored or generated so linguist does not advertise the repo as XML/PHP, tags the extensionless shipped scripts as Shell, and normalises line endings to LF so a checkout on another platform cannot smuggle CRLF into the image. |
| `.gitignore` | Working-tree noise, the droppings AI tool installers leave in the CWD, and — non-negotiably — `cosign.key` and `*.key`. |
| `.hadolint.yaml` | Two documented suppressions: `DL3041` (this image deliberately tracks current Fedora rather than pinning versions) and `SC2046` (the `$(rpm -E %fedora)` substitution always expands to one integer token). |
| `.worktreeinclude` | The inventory of untracked files to propagate into new git worktrees. Every creation path reads this one file; see [subsystems/dev-environment.md](subsystems/dev-environment.md). |

`.containerignore` is deny-all (`**`) and re-admits exactly four paths:
`Containerfile`, `image.env`, `system_files/` and `build_files/`. Nothing else
reaches the builder.

> `docs/` is therefore excluded from the image, and so are `tooling/`, the
> `Justfile`, `README.md`, `AGENTS.md` and everything else at the root. This is
> correct — documentation has no business in a bootable OS layer. Do not "fix"
> it by adding an exception.

---

## How a change reaches a booted machine

```text
INBOUND -- the image is built

  ublue base-main  ─┐
  ublue brew       ─┤
                    ├──> Containerfile ──> GHCR :latest ──> bootc A/B deploy
  build_files/     ─┤     read at /ctx, never a layer
  system_files/    ─┘     COPYd verbatim to /

ON THE MACHINE -- what the image lands as

  /usr, units, factory defaults   replaced wholesale on every update
  chezmoi seeds  ──> $HOME        created only if missing; your edits survive
  DMS overlay    ──> GUI prefs    seeded once, then the UI owns the values
  the rest of $HOME               never in the image, never in Git

OUTBOUND -- a live change becomes the next image

  live terminal or GUI edit
        └──> just audit ──> review + capture ──> just sync ──> just validate
                                                          └──> branch + PR
                                                                 └──> CI
                                                                       └──> new :latest
```

The outbound half is the loop that keeps the repository able to recreate the
workstation: a durable change made only on the live machine is a change that
will not survive a reinstall. [capturing-changes.md](capturing-changes.md) has
the detail of the audit-to-capture cycle.

---

## Who owns what

This is the page's core idea. Every class of state on the machine has exactly
one source of truth, and each has a different update behaviour. Getting the row
wrong is how a change either gets clobbered on the next update or gets baked in
where it cannot be edited.

| Source | Owns | Update behaviour |
| --- | --- | --- |
| COPR desktop stack | `niri` (from `yalter/niri`), `dms`, `dms-cli`, `dms-greeter`, `quickshell`, `dgop`, `danksearch`, `matugen` (from `avengemedia/dms` and `avengemedia/danklinux`) | Floats permanently on COPR HEAD — COPR prunes superseded builds, so versionlocking to an older NEVRA is impossible. The NEVRA manifest `90-cleanup.sh` bakes to `/usr/share/workstation-os-image/package-manifest.txt` is the bisection substitute. |
| Image-owned scaffolding | The niri system config under `/usr/share/workstation-os-image/niri/`, greetd and the greeter's DMS theme, and the `~/.config/niri` and `~/.config/foot` entrypoints (manifest `scaffold` entries) | The image half is replaced on every update; the three non-`create_` `scaffold` entries are rewritten by every chezmoi run, not seeded once. Never edit either on a running machine. Personal overrides go in `~/.config/niri/local.kdl` and `~/.config/foot/workstation.ini`, which the entrypoints include last so the user always wins. |
| The image itself | RPMs, daemons, sockets, privileged helpers, systemd presets, factory defaults | Replaced transactionally by bootc. The previous deployment stays bootable. There are no `rpm-ostree` package layers anywhere in the design, and `tooling/audit/deployment` reports one if it appears. |
| chezmoi seeds | Portable Fish, Git, btop, herdr, Neovim and other application defaults, plus the personal `local.kdl` and `workstation.ini` override files themselves | `create_` entries: written only when the file is absent, so an edit you make later survives every subsequent update. |
| DMS overlay | Explicitly captured, portable GUI preferences | Seeds a new account exactly once, via `workstation-dms-settings.service`. After that the UI owns the values and later edits win unless you explicitly restore. |
| JetBrains config | One canonical `_shared/` set plus a per-product remainder | Applied into the IDEs on demand and never auto-synced. A file lives in exactly one of the two places. |
| Persistent `$HOME` | Secrets, projects, shell histories, device state, application databases | Never in the image and never in Git. |

### The chezmoi statement

The image owns its chezmoi source outright, at
`/usr/share/workstation-os-image/dotfiles/`. It is applied by
`workstation-chezmoi-init.service` on first login and refreshed by
`workstation-chezmoi-update.timer` (five minutes after boot, then daily).

There is no second dotfile manager and no hardcoded username — templates resolve
`{{ .chezmoi.homeDir }}` instead. If you need a new personal default, extend
this source; do not add a parallel updater beside it.

Both units carry `ConditionUser=!@system`, and the comment in each says why:

> Every user manager reaches default.target, including the one pam_systemd
> starts for greetd's `greeter` account, whose home is read-only. Without this
> the unit fails on every login screen.

That is one instance of a general rule; [conventions.md](conventions.md) owns
the mechanism and the other places it applies.

---

## The build, briefly

The `Containerfile` has four `FROM` stages: `brew`, a digest-pinned
`ghcr.io/ublue-os/brew` whose `/system_files/` is copied straight in so Homebrew
arrives as a pinned layer rather than a download; `ctx`, `FROM scratch` holding
only `build_files` for the bind mounts; `toolchain`, which compiles everything
that is not packaged — the X11 clipsync helper, keyd, the FiraCode Nerd Font
release — into `/staging`; and the final stage. That final stage installs
repositories and packages first, the most expensive and most stable step, then
overlays `--from=brew`, `--from=toolchain` and `system_files/` in that order, so
our own files win any collision.

That is as much as you need to place a change. [build-and-ci.md](build-and-ci.md)
owns the rest: the stage rationale, the per-script breakdown, the workflows, the
build-skip detector, tagging, caching and retention.

---

## Where to go next

[conventions.md](conventions.md) is the natural sequel: it turns this ownership
model into a decision procedure for where a specific change belongs, and it owns
the mechanisms this page only gestured at — the `/etc` three-way merge, the
factory-plus-tmpfiles pattern, `ConditionUser`, seed hashing and preset
derivation. [build-and-ci.md](build-and-ci.md) picks up where "The build,
briefly" stops. If you arrived here trying to decide where to put a package
rather than a config file, go straight to
[subsystems/packages.md](subsystems/packages.md).
