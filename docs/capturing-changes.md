# Capturing Local Changes

A workstation change starts life in a live file under `$HOME`, or in a GUI that
writes one. This page is the loop that turns it into a reviewed commit: classify
it, audit for what drifted, capture it into the repository's declarative source,
review the diff, validate. It covers the dotfile manifest and the DMS preference
overlay.

**Nothing on this machine is durable until the repository can recreate it.**

---

## The Loop

Six steps. Three are recipes; the other three are yours to judge.

1. **Make the change live.** Edit the real file, or set the preference in the
   real UI. Capture is a projection of live state, never the other way round.
2. **Classify who owns it.** RPMs, daemons and system presets belong in the
   image; deterministic user preferences belong in the manifest plus a
   create-only chezmoi seed; secrets, histories and device state belong nowhere.
   [conventions.md](conventions.md) has the full decision and the mechanisms
   behind it.
3. **`just audit`** — enumerate what diverged, on the machine and against the
   repository.
4. **`just sync`** — refresh the manifest-listed seeds from live.
5. **Review `git diff`** — for credentials, machine paths, generated noise and
   package additions you did not intend.
6. **`just validate`** — structure, shell syntax, linting, the secret scan, the
   manifests, and the effective workstation. For an image change, `just build`
   as well.

`tooling/validate/all` opens with `git diff --check` and, after the repository
gates, runs `tooling/audit/workstation` itself — so step 6 re-runs step 3.
Validation is not a subset of the audit; it is a superset that also asserts the
repository.

Every command on this page is plain `just` and assumes you are standing in the
checkout you just edited. The image also ships `wjust`, a launcher that finds
(and on first use clones) the checkout so a recipe runs from any directory;
[getting-started.md](getting-started.md) covers it.

---

## The Recipes

| Recipe | What it runs, and what that means |
|---|---|
| `just audit` | `tooling/audit/workstation`: atomic deployment drift, unit state drift, image-owned `/etc` drift, automatic update status, package manifest drift, then `tooling/audit/dotfiles` for personal config, image-managed config, the DMS overlay, niri bind ownership and `niri validate` |
| `just audit-diff` | The same with `--diff`, which makes the image-managed comparisons print their complete chezmoi diff instead of a one-line summary |
| `just update-status` | `tooling/audit/updates` alone: whether `uupd.timer` is armed, whether the last run succeeded, and any journal record above INFO from that run, printed verbatim. See [operating.md](operating.md) |
| `just sync` | `tooling/dotfiles/sync`: rewrite every manifest-listed seed from the live account |
| `just capture` | `sync` then `validate`, then `git status --short`, `git diff --stat` and `git diff` |
| `just validate` | `tooling/validate/all`: the repository gates plus the live-workstation gates. See [validation-and-gates.md](validation-and-gates.md) |
| `just build` | `podman build --pull=always` of the full image, tagged `<image-name>:review-<branch>`. See [build-and-ci.md](build-and-ci.md) |
| `just status` | `git status --short --branch` and `git diff --stat`; changes nothing |

`just audit` and `just status` are read-only. `just sync` writes only inside the
checkout.

> `just capture` is defined as `capture: sync validate` — there is no
> `ai-bundle` step between them. `tooling/validate/all` runs
> `tooling/ai/build-ai-cli-bundle --check`, which fails with
> `tooling/ai/ai-cli-setup is stale: run 'just ai-bundle' and commit.` whenever
> `sync` has just changed an AI CLI seed. So on any change that touches one,
> `just capture` cannot pass. Run the four steps by hand instead: `just sync`,
> `just ai-bundle`, `just validate`, then review `git diff`.

---

## The Dotfile Manifest

`tooling/data/dotfiles.manifest` is the only inventory of captured personal
configuration. Four pipe-separated columns:

```text
kind|live path relative to $HOME|chezmoi source path|file pattern
```

`tooling/dotfiles/validate-manifest` expands the manifest into the exact set of
files that should exist under
`system_files/usr/share/workstation-os-image/dotfiles`, diffs it against what is
actually there, and rejects duplicate live paths or duplicate source paths. A
seed with no manifest entry fails; a manifest entry with no seed fails.
**One entry per file** — never a whole application directory, which is how
secrets and machine state get in.

| Kind | When it is right | What `just sync` does |
|---|---|---|
| `copy` | A deterministic file that is portable verbatim | Installs live over the seed |
| `template` | The value must be derived per machine (chezmoi templating) | Nothing — the template is hand-maintained |
| `scrub` | A mixed file holding portable settings next to secrets or machine state | Pipes live through the filter in `tooling/scrub/` named by column 4 |
| `scaffold` | Image-owned config the base no longer supplies | Nothing — capturing it would overwrite what the image ships with whatever the runtime last wrote |
| `directory` | Every matching file at one level (column 4 is the glob) | Installs each match |
| `tree` | The same, recursively | Installs each match |

For `scrub`, column 4 is a filter name, not a glob. The filter runs on capture
*and* in `tooling/audit/personal-config`, so the audit compares filtered live
against the seed and stripped secrets never surface as drift.

`copy`, `scrub`, `directory` and `tree` seeds are generated output: `just sync`
overwrites them wholesale, so hand-editing one is work you will lose. `scaffold`
and `template` are the two exceptions — both are authored in the repository and
left untouched by `sync`, which is why it finishes with *"Reviewed templates were
left unchanged."*

Captured seeds are chezmoi `create_` entries, so they seed a file that does not
exist and never overwrite an edit the user has since made. That is deliberate:
it also means a repository-side refactor of a seed will not reach a machine
where the live file already exists. The `scaffold` entries are the exception.
There are four of them, and three — `dot_config/niri/config.kdl`,
`dot_config/niri/dms.kdl` and `dot_config/foot/foot.ini.tmpl` — carry no
`create_` prefix, so chezmoi rewrites them on every apply. That is what makes
them image-owned, and why a chezmoi diff against the two niri files is the
audit's one critical image-managed check. The fourth,
`dot_config/foot/create_dank-colors.ini`, is create-only despite being
`scaffold`: DMS/matugen regenerates the live file on every theme change, and the
seed exists only so "a fresh account still parses before DMS first runs" —
foot has no optional include, so the file has to be there.

### Never Capture

`fish_variables`, which Fish rewrites itself. Mutable DMS JSON — note that the
manifest carries a `copy` entry for `.config/DankMaterialShell/clsettings.json`
and no entry at all for `settings.json`, which goes through the overlay below
instead. Neovim state and cache. Configuration backup files.

None of these has a mechanical gate, so the manifest's one-entry-per-file
discipline and your review of `git diff` are the whole enforcement. Adding a
`tree` entry over a directory you have not read is how this rule gets broken.

---

## DMS Preferences

DMS's raw `settings.json` is hundreds of schema defaults interleaved with mutable
and device-specific state, so it is never copied wholesale. What the repository
tracks is a small overlay:
`system_files/usr/share/workstation-os-image/dms-settings.json`. For what DMS is
and how it owns its own configuration, see
[subsystems/desktop-session.md](subsystems/desktop-session.md).

`tooling/dms/defaults` reads the `SettingsSpec.js` shipped by the *installed* DMS
(overridable with `DMS_SETTINGS_SPEC`), evaluates it in a Node sandbox and emits
`def` for every key the spec persists. `tooling/dms/capture` then compares live
against those defaults and offers you only what actually deviates — plus anything
already tracked, so you can update it. Keys absent from the spec, `configVersion`,
and everything listed in `tooling/data/dms-settings-denylist` (device profiles,
wallpaper paths, GPU ids, usage histories, monitor preferences) never reach the
picker.

```bash
just dms-capture                        # fzf picker; Tab marks, Enter confirms
just dms-capture --select acLockTimeout # same, by name, repeatable
just dms-capture --list                 # print the candidate table and exit
just dms-remove                         # pick tracked overrides to stop applying
```

`--select` is the escape hatch for scripts and agents: it takes the same key the
picker shows in its first column, and fails loudly with `no such key on offer` if
you name one that is not a candidate, rather than silently selecting nothing.
Every write goes through `tooling/dms/validate-overlay` before it lands.

**Merge semantics.** `system_files/usr/bin/workstation-apply-dms-settings` merges
the overlay onto live, not the other way round. Simple values merge by top-level
key. `barConfigs` merges per bar, matched on `id`, field by field — so a DMS
release that adds a bar field does not get clobbered by an older capture, and an
overlay-only bar is appended. `configVersion` is always restored from the live
file, and `${HOME}` tokens in overlay strings are expanded at apply time. A bar
that has no counterpart in the defaults is captured as a complete portable record
(pinned to `screenPreferences: ["all"]` and `showOnLastDisplay: true`); a
built-in bar stays field-selectable.

`system_files/usr/lib/systemd/user/workstation-dms-settings.service` runs the
same script with `--initialize` at first graphical login, after DMS has migrated
`settings.json` to the installed schema version, and marks itself done. From then
on **the UI is the live editor.** Run `just dms-capture` after a reviewed change
to promote it to a workstation default; the image never writes live DMS changes
back into Git on its own.

`just dms-apply` is the reverse direction and is rarely what you want: it
re-applies every tracked value over live, so any UI change to a tracked key is
discarded, and nothing is backed up first. It is gated by a `just` confirmation
prompt, and that prompt needs a terminal — without one it fails with
``error: recipe `dms-apply` was not confirmed`` and exits 1, which includes an
agent running without a tty. If you genuinely need it unattended, invoke
`system_files/usr/bin/workstation-apply-dms-settings --force` directly with
`WORKSTATION_DMS_SETTINGS_OVERLAY` pointed at the repository overlay, as the
recipe does — unset, the script falls back to the copy the installed image
shipped, which is whatever was captured at build time.

---

## Answering "Is There Drift?"

Enumerate the divergent items. Never report the audit's summary counts as the
answer — a count tells the reader nothing they can act on. There are two
independent signals and a complete answer reports both.

**Tracked items whose live value diverged from their captured baseline.**
`tooling/audit/personal-config` walks the manifest and labels each file
`missing-live`, `uncaptured`, `modified` or `removed-live`; name the paths.
For DMS, `tooling/audit/dms-settings` copies live settings, applies the overlay
to the copy, and compares — `Live DMS preferences differ from the captured
defaults.` means a tracked value drifted. Confirm this kind by diffing live
against the captured source directly. Do not confirm it with `--list`-style
tools: `just dms-capture --list` shows live against the *installed DMS schema
default*, so a tracked key whose live value has moved away from your overlay
still reads as an ordinary `[tracked]` row. This is never noise.

**New items not tracked at all.** `Portable DMS deviations are not captured (N)`
in the audit, and the `[new]` rows of `just dms-capture --list`. List them.

Severity in the image-managed section is not uniform. `Managed Niri scaffolding`
is critical and fails the audit; `DMS clipboard preferences` is informational,
because it covers UI-owned state, and fails only under
`tooling/audit/dotfiles --strict`. Report the informational line as
informational, and never let it stand in for the tracked divergence above it.

---

## Commands That Write Live State

Everything else on this page is read-only or writes only inside the checkout.
Two commands destroy live state, and each needs a human's go-ahead first.

`just dms-apply` re-applies every tracked value over your live DMS settings, with
no backup.
`just ai-reset --force` rewrites the live AI CLI config from the repository
canonical (after a timestamped backup), and adding `--replace` drops the machine
state — trust grants, keys — that the default merge would have preserved.
Without `--force`, `ai-reset` is a dry run whatever else you pass it.

Audits, diffs, dry runs and `just validate` are always safe.

---

## Where to go next

[conventions.md](conventions.md) is the other half of step 2: it decides where a
change belongs and explains the mechanisms — the `/etc` merge, factory plus
tmpfiles, seed hashing — that make the placement rules non-negotiable.
[validation-and-gates.md](validation-and-gates.md) covers what each gate actually
proves and why the machine audits exist alongside the image gates.
[cookbooks.md](cookbooks.md) has the copy-paste form of the common captures, and
[subsystems/ai-clis.md](subsystems/ai-clis.md) explains the AI CLI seeds behind
the `ai-bundle` trap above.
