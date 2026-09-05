# Forcing Image-Owned Scaffolding

The record for why `/usr/libexec/workstation-chezmoi-apply` gained a pass that
overwrites image-owned targets instead of preserving them: the skip that was
protecting the wrong files, the three days a herdr plugin spent frozen without
anything failing, and why the force list is a projection of the manifest rather
than a list of its own.

**A dotfile updater that reports success after declining to update is the
failure mode. Every file it declined stays at whatever version it held on the
day someone last wrote it out of band, and its siblings keep moving.**

---

## Context

`workstation-chezmoi-apply` ended with one line:

```sh
exec sh -c "yes s | chezmoi apply --no-tty --keep-going -S '$src' --verbose --config '$dir/chezmoi.toml'"
```

`yes s` answers chezmoi's `... has changed since chezmoi last wrote it
(diff/overwrite/all-overwrite/skip/quit)?` with **skip**. The reasoning above it
in the file is sound and still stands: with an empty entry-state database no
prompt fires at all and chezmoi rewrites every managed target, measured at 20
files on this machine including the DMS settings and the mode on
`~/.config/opencode`, which holds API keys. Skipping is the safe default for a
seed the *user* owns.

It is the wrong default for a seed the *image* owns. Roughly a third of the
manifest is `scaffold`: the niri system config, the Mod+Slash cheatsheet, the
DMS bar widget's QML, and all 24 files of the `dev.flow` herdr plugin. Nothing
but the image is supposed to write those. When one of them diverges from
chezmoi's recorded state, the divergence is not a user preference to protect —
it is damage, and `yes s` makes it permanent.

---

## The failure

Developing the herdr plugin means editing live and testing immediately, so
copies landed in `~/.config/herdr/plugins/dev-flow/` by hand. Three files kept
the hand-written copy: `spaces.sh`, `layout-common.sh` and `herdr-plugin.toml`.
Their recorded hashes stopped matching, and from that moment every boot skipped
them:

```
.config/herdr/plugins/dev-flow/herdr-plugin.toml has changed since chezmoi last wrote it
.config/herdr/plugins/dev-flow/layout-common.sh has changed since chezmoi last wrote it
.config/herdr/plugins/dev-flow/spaces.sh has changed since chezmoi last wrote it
.config/DankMaterialShell/cheatsheets/workstation.json has changed since chezmoi last wrote it
...
Finished workstation-chezmoi-update.service - Reapply workstation dotfiles.
```

Note the last line. The unit exits 0. Nothing anywhere reports a skip.

Their siblings kept updating, which is what turned a stale plugin into a broken
one. `d005b59` deleted `AGENT_EXPIRED_SECONDS=43200` from `agent-finished.sh`,
because the recency stamp stopped having an expiry window. `agent-finished.sh`
was not one of the frozen three, so the new copy landed. The frozen
`spaces.sh:82` and `layout-common.sh:370` still read the constant, and both
scripts run under `set -euo pipefail`:

```
./spaces.sh: line 75: AGENT_EXPIRED_SECONDS: unbound variable
```

`spaces.sh` is the single row builder behind both the `prefix+s` space picker
and the `herdrJobs` bar widget. It produced nothing, and the widget renders an
empty read as `herdr is not running` — while the herdr server was running, with
four workspaces in it. `claude_command()` in the frozen `layout-common.sh` hit
the same constant, so the dev layout builder was broken too, and the frozen
`herdr-plugin.toml` predated the `[[startup]] ./agent-status-reset.sh` entry, so
the remembered-status reset never ran.

Four failures, one skip, no error anywhere.

---

## Why the audit did not catch it

`tooling/audit/dotfiles` did compare image-owned scaffolding against the image —
for two files:

```sh
show_diff "Managed Niri scaffolding" critical \
    "$HOME/.config/niri/config.kdl" "$HOME/.config/niri/dms.kdl"
```

The other 30 scaffold entries were never diffed. The manifest said why, and the
reason was wrong:

> The static ones chezmoi keeps in sync by itself, so auditing them would be
> redundant

chezmoi keeps them in sync only for as long as nothing writes them out of band,
which is exactly the case worth auditing. `just audit` reported
`Managed Niri scaffolding matches the installed image defaults` and exited 0
throughout.

---

## The shape of the fix

Two mechanisms, both reading the manifest's `scaffold` kind, so neither is a
second inventory:

- `/usr/libexec/workstation-chezmoi-apply` runs `chezmoi apply --force` over the
  scaffold targets before the `yes s` pass. `--keep-going` on both, so one bad
  entry strands nothing.
- `tooling/audit/dotfiles` diffs every scaffold entry at critical severity,
  under the renamed label `Managed image scaffolding`.

The wrapper cannot read `tooling/data/dotfiles.manifest` — that directory is
repo-owned and never reaches a layer — so `tooling/dotfiles/scaffold-list`
projects the paths into
`system_files/usr/share/workstation-os-image/scaffold-targets`, `just sync`
regenerates it, and `tooling/validate/sources` runs the generator with
`--check`. `tooling/validate/all` additionally asserts every listed path appears
in `chezmoi managed` over the shipped source tree, because a forced target that
no source entry answers to is an error rather than a no-op.

### Why forcing the whole kind is safe

Two scaffold entries are create-only: `dank-colors.ini`, which matugen rewrites
on a theme change, and `plugin_settings.json`, which DMS owns for every plugin
other than ours. Forcing those would be a real regression, and the reason it is
not one is a property of chezmoi rather than of this list. Measured on chezmoi
v2.72.0, in a scratch source and destination:

```
$ chezmoi apply --force -S src -D dest
made.txt  -> LOCAL-EDIT     # source was create_made.txt
plain.txt -> IMAGE          # source was plain.txt
```

`--force` overrides the "changed since chezmoi last wrote it" guard. It does not
override `create_` semantics. So the force pass can take the manifest's whole
scaffold kind, which is the only version of the list that cannot drift from the
manifest.

---

## Routes that lost

**Force everything, drop `yes s`.** The simplest change, and the closest call.
It is not the file clobbering it looks like: every non-scaffold source in the
seed tree is `create_`-prefixed — `tree` and `directory` entries included, since
`workstation_seed_path` writes each captured file with that prefix — so
`--force` would leave all of them alone today. What it does not leave alone is
directory modes. Reproduced in the scratch home above, on `~/.local`, whose
source is `private_dot_local`:

```
after chmod 0755:                755
scaffold-scoped force:           755
blanket force:                   700
```

`.local` and `.config/opencode` are the two directory prompts in the same
journal run that skipped `spaces.sh`, and the mode on `~/.config/opencode` — it
holds API keys — is the specific thing the migration comment was written to
protect. Rejected on that, and on a second count: blanket force would be correct
only for as long as every user-owned seed happens to be `create_`. That is a
naming coincidence, not a rule anything enforces. The scaffold list encodes the
intent instead, so the first plain-source user seed anyone adds does not quietly
join the forced set.

**Hand-write the force list in the wrapper.** No generator, no gate, four lines
of shell. Rejected on the standing rule against a second inventory: a scaffold
entry added to the manifest and forgotten here would be silently unprotected,
and "silently unprotected" is the entire defect being fixed.

**Reset chezmoi's entry state instead.** Clearing the recorded hashes makes the
next apply overwrite the frozen files. It is a one-shot repair of the instance,
not of the recurrence — the next hand copy freezes them again — and the only
granularity chezmoi exposes is the whole bucket, which would drop the state for
every user-owned seed at the same time. That is precisely the empty-database
case the migration block exists to avoid.

**Symlink the plugin from `/usr/share` instead of copying it.** Structurally
unable to diverge, and genuinely attractive for the herdr plugin specifically:
herdr only needs `~/.config/herdr/plugins/dev-flow` to resolve. It solves one
instance of a class. The niri config, the cheatsheet and the widget QML have the
same ownership and would each need their own answer, and `plugins.json` records
`plugin_root` as an absolute path that would then point outside the home. A
mechanism that covers the kind beat one that covers a directory.

**Audit only, repair by hand.** Reporting the drift without fixing it was the
first half of this change and is worth having on its own — but a critical audit
finding that recurs every time someone tests a plugin edit is a finding people
learn to ignore. The force pass is what makes the audit line mean something,
because after it fires the only way to see drift is to be mid-edit.

---

## What is still not covered

The force pass repairs a scaffold target the moment it diverges, which means a
deliberate live edit to one — the normal way to test a plugin change — is
reverted at the next timer fire, five minutes after boot and daily thereafter.
That is the intended trade and it is why `scaffold` entries are hand-edited in
the repository rather than captured; the loop for testing one live is to edit,
test, and land it in the repo before the timer catches up, or to stop the timer
while working.

Nothing gates that the *contents* of a scaffold script are internally
consistent. The defect was cross-file — an old script against a new library —
and the gate that would have caught it directly is a shellcheck run with the
libraries resolved, which `tooling/validate/shell-files` already does against
the repository copy. It passed throughout, because the repository copy was
never wrong. Only the machine was.
