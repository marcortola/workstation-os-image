# Forking This Image

This repository builds one person's workstation, but the scaffolding around it —
the build, the gates, the signing chain, the capture workflow — is not personal
at all. This page is the complete list of what a fork has to change, what it can
delete, and what it must leave alone.

**Identity lives in exactly one file; everything else here is either personal
data you replace or a gate you leave standing.**

---

## What you are forking, and what is missing

There is no `disk_config/` and no ISO pipeline in this repository, so the only
install path is rebasing a machine that is already bootc-based. See
[getting-started.md](getting-started.md) for that procedure — the fork changes
the image reference, not the steps.

There is also no `artifacthub-repo.yml`. Add one carrying the `repositoryID`
Artifact Hub issues you if you want the image indexed there; nothing in the build
or the gates depends on it either way.

---

## Edit

These carry this repository's identity or this person's data. Change them first,
before you push anything.

| Path | Why |
|---|---|
| `image.env` | Image name, registry owner, description, OS name — `IMAGE_NAME`, `REPO_ORGANIZATION`, `IMAGE_DESC`, `OS_NAME`. The one place identity is written. The Justfile reads it as its dotenv file (`set dotenv-filename := "image.env"`), `tooling/audit/deployment` builds `expected_image="ghcr.io/${REPO_ORGANIZATION}/${IMAGE_NAME}:"` from it, `build_files/40-signing.sh` derives the signing policy scope `scope="ghcr.io/${REPO_ORGANIZATION}"`, `system_files/usr/bin/wjust` clones `https://github.com/${REPO_ORGANIZATION}/${IMAGE_NAME}.git`, and the Containerfile interpolates all three into the OCI labels. `OS_NAME` is the odd one out: it has no matching `ARG` because nothing interpolates it into a label — `build_files/60-metadata.sh` reads it out of the baked copy to write `NAME` and `PRETTY_NAME` into `/usr/lib/os-release`, so a fork changing it changes what the system calls itself in the boot menu and in every fetch tool. It is also `COPY`d to `/usr/share/workstation-os-image/image.env` so the running machine resolves the same values. |
| `Containerfile` `ARG IMAGE_NAME`, `ARG REPO_ORGANIZATION`, `ARG IMAGE_DESC` | Defaults that mirror `image.env`, so a bare `podman build` with no `--build-arg` still labels correctly instead of shipping `https://github.com//` in the source label. `tooling/validate/image-build` reads each key out of `image.env`, pulls the matching `ARG` out of the Containerfile with `sed -n "s/^ARG ${key}=//p"`, and fails on any difference — it matches by pattern, not by line number, so inserting lines above them is harmless. |
| `cosign.pub` and `system_files/etc/pki/containers/workstation-signing.pub` | Your own signing keys. Generate with `COSIGN_PASSWORD="" cosign generate-key-pair`, store the private half as the `COSIGN_PRIVATE_KEY` repository secret alongside `COSIGN_PASSWORD`, and never commit `cosign.key`. The two public copies must be byte-identical: `tooling/validate/image-build` runs `cmp -s` on them, because CI verifies the published image against the first while every machine's `policy.json` points at the second. |
| `system_files/usr/share/workstation-os-image/dotfiles/` and `tooling/data/dotfiles.manifest` | The chezmoi seed tree is one person's dotfiles — ninety files of shell, editor, Git and AI-CLI configuration. Replace it through the manifest, not by hand: `just sync` rewrites every manifest-captured seed from your live account, so a hand edit is lost on the next run. The four `scaffold` entries are the exception — they are image-owned, `tooling/dotfiles/sync` skips them on capture, and they are edited in the repo. |
| `Documentation=` URLs under `system_files/usr/lib/systemd/` | Ten units point at this repository. Cosmetic, but wrong on a fork. Eleven `Documentation=` lines ship there in total; the eleventh, in `workstation-flatpak-wayland.service`, points at an upstream xwayland-satellite issue and should stay. |
| `.github/workflows/build.yml` (`IMAGE_REF`, `CACHE_IMAGE`) and `.github/workflows/clean.yml` (both `packages:` inputs) | The owner interpolates from `github.repository_owner`, but the image *name* is a literal in all four places. Only `IMAGE_REF` is checked: the `repo-gates` job sources `image.env` and fails if `IMAGE_REF != "ghcr.io/${GITHUB_REPOSITORY_OWNER}/${IMAGE_NAME}"`, and again if `REPO_ORGANIZATION` is not the repository owner. The other three names are gated by nothing: `tooling/validate/image-build` asserts only that the `--cache-from` and `--cache-to` flags are present, never what they name. A rename leaves the cache under the old name and points the pruner at a package your fork does not publish, so the real image and cache grow unbounded. |
| `LICENSE` | MIT, currently naming one copyright holder. The licence requires the notice be retained for the code you inherited, so add your own line rather than replacing the existing one. |

> Half a rename fails in two different places. `image.env` out of step with the
> Containerfile `ARG`s fails locally, in `tooling/validate/image-build`. Either
> out of step with the workflow literals fails only in CI, in `repo-gates`, after
> you have already pushed — nothing in `just validate` reads
> `.github/workflows/build.yml` for an image name. Change `image.env`, the three
> `ARG` defaults and the four workflow literals in one commit.

`.gitignore` carries `cosign.key` and `*.key`, which stops the private half being
committed but not scanned: `gitleaks dir .` does not respect `.gitignore`, so a
key left in the checkout fails `just validate`. `just clean` removes that class
of leftover. The signing chain, key rotation and the second trust anchor are in
[supply-chain.md](supply-chain.md).

### What a rename does not require

The `workstation-` unit prefix, the `/usr/share/workstation-os-image/` payload
directory and the `10-workstation-os-image.preset` filenames are an internal
namespace, not registry identity. Nothing resolves them from `image.env`, so
they keep working under any image name. Renaming them anyway is a wide mechanical
edit for no gain: the strings are literals in the build scripts
(`build_files/50-services.sh` reads
`/usr/lib/systemd/system-preset/10-workstation-os-image.preset` to derive its
`systemctl preset` arguments), in every shipped unit and helper, and in the gates
— `tooling/validate/repo` and `tooling/validate/image-build` both match on the
payload path.

---

## Delete if you do not want it

Each of these is a self-contained subsystem. Removing one is a normal fork
decision, not a downgrade.

| Path | What it is | What removing it touches |
|---|---|---|
| `build_files/packages/insync.list`, `build_files/repos/insync.repo`, `build_files/keys/rpm/insync.asc`, and the `insync` entry in `build_files/keys/rpm-key-sources.json` | Insync is proprietary and needs a licence. One package, one repository, one vendored key. | `build_files/20-packages.sh` globs `packages/*.list` and `build_files/10-repos.sh` globs `repos/*.repo` and `keys/rpm/*.asc`, so neither needs an edit. Two places do. `build_files/99-check-build.sh` names the six keys literally in its presence loop (`copr-yalter-niri`, `copr-avengemedia-dms`, `copr-avengemedia-danklinux`, `terra`, `docker-ce`, `insync`), so leaving `insync` there fails the build with `vendored signing key missing: insync.asc`. And `tooling/validate/rpm-keys` iterates the JSON, so leaving that entry behind fails with `MISSING vendored key: build_files/keys/rpm/insync.asc`. |
| `tooling/data/ai-tools/` and `tooling/ai/` | The AI-CLI seeds, the portable installer bundle and the reset machinery. See [subsystems/ai-clis.md](subsystems/ai-clis.md). | `tooling/validate/sources` asserts against `tooling/data/ai-tools/opencode-mcp-fragment.json` and `tooling/ai/ai-cli-setup/config/claude/settings.json` directly, and `tooling/validate/all` calls `tooling/ai/test-reset` and `tooling/ai/build-ai-cli-bundle --check`. Those lines go with the subsystem. So do the `ai-*` recipes. |
| `tooling/upstream/`, `tooling/data/zirconium-watermark`, `.claude/commands/port-zirconium.md` | The upstream-tracking set: a diff tool, the last-reviewed Zirconium commit, and the review procedure that advances it. See [subsystems/upstream-zirconium.md](subsystems/upstream-zirconium.md). | A fork of a fork inherits a watermark that means nothing to it — it records a review *this* repository performed. Drop the `upstream-diff` and `upstream-accept` recipes with it. Note that `.claude/commands/port-zirconium.md` is currently the only file under `.claude/commands/`, and `tooling/validate/sources` fails outright when none are present (`no agent commands found under .claude/commands`); add your own command file or drop that specific assertion. |

> Deleting a gate line because you deleted the subsystem it asserts is fine.
> Deleting one because it is failing is not — that is the rule in
> [AGENTS.md](../AGENTS.md), and the distinction is whether the thing being
> asserted still exists.

The chezmoi seed tree has the same property, so replacing it is not purely a
content swap: `tooling/validate/sources` reaches into it by path for the AI-CLI
secret gates (`dot_claude/create_settings.json`,
`dot_codex/create_config.toml`) and for the worktree-propagation wiring
(`dot_config/git/create_config`, `dot_config/git/template/hooks/create_executable_post-checkout`,
`dot_config/homebrew/create_Brewfile`). Replace the contents freely; if you drop
those files entirely, drop their assertions in the same commit.

---

## Do not touch

| Path | Why |
|---|---|
| `system_files/usr/share/workstation-os-image/niri/NOTICE` | Apache-2.0 attribution for the niri includes vendored verbatim from Zirconium's zdots. It names the six byte-identical files, the one substantially rewritten (`binds.kdl`) and the upstream commit they were compared against. Stripping it breaks the licence terms. Context in [subsystems/upstream-zirconium.md](subsystems/upstream-zirconium.md). |
| `tooling/validate/` | The gates. They are what makes the skeleton worth forking: they encode failures this image already hit — a vendored repository with no `includepkgs` allowlist (Terra's `sdbus-cpp` substituted itself into a transaction that way), a half-finished key rotation that keeps CI green while locking every machine out of its own updates, a build input `COPY`d into the final image instead of bind-mounted, a build step mutating the chezmoi source. See [validation-and-gates.md](validation-and-gates.md). |
| `tooling/scrub/` | The capture-time filters that keep the AI-CLI seeds secret-free by construction. This is the real secret boundary, not gitleaks: gitleaks does not recognise these tools' key shapes, which is why the hand-written gates exist. See [supply-chain.md](supply-chain.md). |

Fix the input, never the check — and where a gate is genuinely wrong for your
fork, change it deliberately and say so in the commit.

---

## Order of operations

1. Edit `image.env`, the three Containerfile `ARG` defaults, the two literals in
   `.github/workflows/build.yml` and the two in `.github/workflows/clean.yml`.
2. Generate your signing key pair, write both public copies, and add
   `COSIGN_PRIVATE_KEY` and `COSIGN_PASSWORD` as repository secrets.
3. Delete the subsystems you do not want, together with their recipes and the
   gate lines that assert them.
4. Rewrite `tooling/data/dotfiles.manifest` for your own configuration, then run
   `just sync` on your machine to regenerate the seed tree.
5. Run `just validate` and `just build` locally. `tooling/validate/all` needs a
   live workstation, so CI never runs it — locally is the only place it fires.
   See [validation-and-gates.md](validation-and-gates.md).
6. Push. `repo-gates` runs the identity check and the repository-only gates;
   `build` publishes and signs. The workflow layout is in
   [build-and-ci.md](build-and-ci.md).

---

## Where to go next

Read [architecture.md](architecture.md) before you start cutting: it explains why
`build_files/` never reaches a layer and why `system_files/` is copied verbatim,
which is what makes most of these deletions safe. [conventions.md](conventions.md)
covers where a *new* file goes and the mechanisms — the `/etc` merge, factory
plus tmpfiles, seed hashing — that a fork will meet the first time it adds
something of its own. For the signing chain you are about to re-key end to end,
[supply-chain.md](supply-chain.md) is the page.
