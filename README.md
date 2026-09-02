# workstation-os-image

A **personal, reproducible Fedora bootc workstation** built on Universal Blue's
[base-main](https://github.com/ublue-os/main). OS packages, services, desktop
defaults and selected user preferences become one reviewable Git workflow: a
machine switches to the published image, the owner signs in, and the account
converges on the same working environment.

- **A graphical session that is installed, not assembled** — greetd, niri and
  DankMaterialShell arrive together with their configuration and keybinds, and
  are replaced wholesale on every update.
- **A development host with no language runtimes on it** — project-scoped Dev
  Containers, a Neovim that runs inside them, and rootful Docker usable without
  `sudo` from the first session.
- **Personal defaults that are reproducible without being imposed** — portable
  dotfiles ship as create-only chezmoi seeds, so a fresh account gets the
  image's default and an account that edited the file keeps its edit.
- **A capture loop** that turns a change made live on the machine into a
  reviewed commit, so the repository never falls behind the workstation.
- **A supply chain verified in both directions** — digest-pinned,
  cosign-verified inputs going in; a signed digest going out, which the
  machine's `policy.json` requires before it will pull.

The image owns `/usr`, chezmoi seeds own first-write personal defaults, and the
DankMaterialShell UI owns its own settings after a single seed. Learning that
split is the whole job.

Published image:

```text
ghcr.io/marcortola/workstation-os-image:latest
```

---

## Start here: the handbook

New to this repository? **Read [`docs/`](docs/README.md).** It is a guided path
through the architecture, the conventions, each subsystem, and how to make a
change that survives the next update. This README is only a landing pad — the
handbook is the source of truth.

Fast links:

| I want to… | Go to |
|------------|-------|
| Install this image on a machine | [docs/getting-started.md](docs/getting-started.md) |
| Update, roll back or recover one | [docs/operating.md](docs/operating.md) |
| Understand the big picture | [docs/architecture.md](docs/architecture.md) |
| Learn where a change belongs before writing it | [docs/conventions.md](docs/conventions.md) |
| Turn a live change into a commit | [docs/capturing-changes.md](docs/capturing-changes.md) |
| Follow a copy-paste recipe | [docs/cookbooks.md](docs/cookbooks.md) |
| Understand a gate that just failed | [docs/validation-and-gates.md](docs/validation-and-gates.md) |
| Build my own workstation from this one | [docs/forking.md](docs/forking.md) |
| Look up a term I do not recognise | [docs/glossary.md](docs/glossary.md) |
| Work on one part of the machine (desktop, dev environment, AI CLIs, packages) | [docs/subsystems/](docs/subsystems/) |

---

## Install

The target must already be bootc-based; there is no ISO pipeline here, so
rebasing is the only install path.

```bash
skopeo inspect docker://ghcr.io/marcortola/workstation-os-image:latest
sudo bootc switch ghcr.io/marcortola/workstation-os-image:latest
systemctl reboot
```

After the first graphical login, user services restore the Brewfile and
Flatpaks, install the fonts, and seed the DMS preference
overlay once. The repository is not cloned eagerly — `wjust` clones it on demand
the first time you run a recipe, from any directory:

```bash
wjust audit
```

Full sequence, the convergence checks, and the day-one steps that are
deliberately not automatic: [docs/getting-started.md](docs/getting-started.md).

---

## Repository map

| Directory | Holds | In the image? |
|---|---|---|
| `system_files/` | The image payload, mirroring absolute paths and copied verbatim into `/`: systemd units, helpers, factory defaults, the image-owned niri config and the chezmoi seed tree. | Yes |
| `build_files/` | Everything the build reads and nothing it ships: the numbered build scripts, package lists, vendored repositories and keys, and one C source. Bind-mounted at `/ctx`. | No |
| `tooling/` | Host-side scripts grouped by concern, plus `data/` — the declarative source they read — and the AI-CLI machinery, gates and scrub filters. | No |
| `docs/` | The handbook. | No |

Identity is written once, in `image.env`; the Justfile, the OCI labels, the
signing policy scope and `wjust`'s clone URL derive from it, and CI asserts its
own copy has not drifted from it.
[docs/architecture.md](docs/architecture.md) has the ownership model and the
complete inventory.

---

## Recipes

`just` inside a checkout; `wjust` from anywhere, on any machine running the
image. `just --list` is the full index — the ones used daily:

| Command | What it does |
|---|---|
| `just audit` | Report personal and image-managed configuration drift |
| `just capture` | Refresh create-only seeds from live files, validate, show the diff |
| `just sync` | Refresh create-only seeds only |
| `just validate` | Repository gates plus the effective local workstation |
| `just build` | Build and lint the bootc image locally with Podman |
| `just update-status` | Report whether the last automatic update succeeded, and which module failed |
| `just dms-capture` | Review portable DankMaterialShell deviations and capture selected values |
| `just brew-apply` | Install Brewfile entries not yet on this machine |
| `just upstream-diff` | Review what changed in Zirconium since the watermark |

The pre-PR sequence, and the one case where `just capture` is the wrong recipe:
[docs/cookbooks.md](docs/cookbooks.md). CI runs the repository gates on a pull
request that touches the image, the tooling or the docs, and builds the image
when its inputs changed — [docs/build-and-ci.md](docs/build-and-ci.md).

---

## Contributing and security

`AGENTS.md` is the canonical maintenance policy for humans and AI agents alike;
`CLAUDE.md` imports it. Durable changes go on a branch and through a pull
request, and the image build must pass before the workstation is upgraded.

Report anything affecting the build or trust machinery through
[`SECURITY.md`](SECURITY.md).

---

## Licence

MIT — see [`LICENSE`](LICENSE). The niri configuration under
`system_files/usr/share/workstation-os-image/niri/includes/` was vendored from
[zirconium-dev/zdots](https://github.com/zirconium-dev/zdots) and remains under
the Apache License 2.0; its attribution ships inside the image as `NOTICE` and
must not be removed. See
[docs/subsystems/upstream-zirconium.md](docs/subsystems/upstream-zirconium.md).
