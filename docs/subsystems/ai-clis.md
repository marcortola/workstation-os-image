# AI Coding CLIs

Three AI coding CLIs run on this workstation — **Claude Code**, **codex** and
**opencode** — plus four third-party tools that cut token usage. This page covers
how their configuration is made reproducible, what the image ships versus what you
install, and the recipes that keep the two in sync.

**Configuration is *captured* into the image; tools are *installed* on top by their
own official installers — the same split the Brewfile uses for packages.**

---

## Captured versus installed

The image cannot ship the tools themselves. They are third-party npm packages and
skill bundles that update on their own cadence, and vendoring them would mean
carrying someone else's source in this repository forever. So the boundary runs
between *what you wrote* and *what you installed*:

| Layer | Lives in | Arrives via | Reproducible because |
| --- | --- | --- | --- |
| Personal config (`~/.codex`, `~/.claude`, `~/.config/opencode`) | `system_files/usr/share/workstation-os-image/dotfiles/` | chezmoi, at first login, create-only | It is captured into the image and gated secret-free |
| The four tools | `~/.agents/skills/`, `~/.claude/skills/`, `~/.codex/skills/`, `~/.config/opencode/plugins/` | `just ai-tools-install`, one command | Each installer is idempotent and re-runnable |
| CLI binaries themselves | Homebrew | `just brew-apply` | `~/.config/homebrew/Brewfile` declares them |

The CLIs arrive as Brewfile entries — `cask "claude-code"`, `cask "codex"`,
`brew "anomalyco/tap/opencode"` — alongside `brew "rtk"` and `brew "herdr"`. See
[packages.md](packages.md) for how the Brewfile is the declaration site. The
Fish seed adds one alias for the longest of the three names,
`alias oc="opencode"` in `dot_config/fish/conf.d/create_aliases.fish`.

`install-ai-tools` is not an auto-updater and says so in its own header: "Run once
after deploy, like `just brew-apply` -- this is a manual apply step, not an
auto-updater." You re-run it when you want newer skills, and not before. The brew
half behaves differently: uupd runs `brew upgrade` nightly — which is why
`build_files/50-services.sh` disables Homebrew's own `brew-update.timer` and
`brew-upgrade.timer` — so the CLI binaries move on their own, and `just brew-apply`
only installs Brewfile entries that are not present yet. See
[../operating.md](../operating.md).

---

## What the image ships

### The config seeds

`tooling/data/dotfiles.manifest` is the only inventory of captured personal config,
and eighteen of its entries are the AI CLIs. They land as chezmoi `create_` entries
under `system_files/usr/share/workstation-os-image/dotfiles/`, so an existing user
edit always wins — chezmoi never rewrites a `create_` target once it exists.

| Manifest kind | Files | Captured how |
| --- | --- | --- |
| `copy` | `.codex/AGENTS.md`, `.claude/CLAUDE.md`, `.claude/rules/context7.md`, `.config/opencode/AGENTS.md`, the three worktree commands for claude and opencode | Byte-for-byte from the live file |
| `scrub` | `.codex/config.toml`, `.claude/settings.json` | Through a filter in `tooling/scrub/` |
| `tree` | `.claude/skills/context7-mcp`, `.claude/skills/weekly-summary`, `.codex/skills/weekly-summary`, `.codex/skills/worktree-{create,push,remove}` | Whole skill directories |

The two `scrub` entries are the ones that would otherwise leak; see
[Invariants](#invariants) below.

### Claude Code's default MCP servers

Claude Code keeps user-scope MCP servers in `~/.claude.json`, which also holds
session history and credentials. That file can never be tracked in Git, so the
image seeds the servers on the live machine instead:
`system_files/usr/libexec/workstation-seed-claude-mcp`, run once per account by the
user unit `workstation-claude-mcp-seed.service`.

Two servers are seeded, both over HTTP at user scope:

| Server | Endpoint | Credentials |
| --- | --- | --- |
| `context7` | `https://mcp.context7.com/mcp` | None |
| `ahrefs` | `https://api.ahrefs.com/mcp/mcp` | One-time `claude mcp login ahrefs` (browser OAuth, paid plan) |

The seeder is deliberately conservative in two directions. A server the account
already defines is skipped (`claude mcp get "$name"` short-circuits the add), and a
completion marker at `~/.local/state/workstation-os-image/claude-mcp-seeded` keeps a
deliberate later removal from being re-added on the next login. The unit gates on
that marker with
`ConditionPathExists=!%h/.local/state/workstation-os-image/claude-mcp-seeded`, on
`ConditionUser=!@system` so it does not also run in greetd's greeter user manager,
and on an `ExecCondition` that tests for the Homebrew `claude` binary — because
until `workstation-bootstrap` has installed it there is nothing to seed, and a
non-zero `ExecStart` would have left a failed unit that our own audit then reported
on every fresh machine. Both patterns are explained in
[../conventions.md](../conventions.md).

### Browser automation: a CLI, not an MCP

Browser automation is the `playwright-cli` command, not a Playwright MCP server. The
seeder states the reason inline: attaching over CDP and snapshotting to disk is "far
cheaper on tokens than an MCP that injects the accessibility tree every step".

Two shipped files make it work:

- `system_files/usr/bin/playwright-cli` — a wrapper around
  `npx -y @playwright/cli@latest`. Upstream's `open` command launches a downloaded
  chromium, which this image deliberately avoids, so the wrapper rewrites `open [url]`
  into `attach --cdp=<endpoint>` followed by `goto`. Every other subcommand passes
  straight through and reuses the attached session, so the upstream skill works
  unchanged.
- `system_files/usr/libexec/workstation-playwright-chrome` — brings up the per-user
  Flatpak `com.google.Chrome` with `--remote-debugging-address=127.0.0.1` and a
  loopback-only debugging port, then prints the endpoint. Idempotent: a running
  endpoint is reused. The profile is a throwaway per-boot directory under
  `$XDG_RUNTIME_DIR/workstation-playwright/`, and Chrome is started with `nohup`
  rather than `setsid` so it stays attached to the graphical session's D-Bus portal
  while outliving the script.

| Environment variable | Default | Effect |
| --- | --- | --- |
| `WORKSTATION_PLAYWRIGHT_CDP_PORT` | `9222` | CDP port on loopback |
| `WORKSTATION_PLAYWRIGHT_HEADED` | `0` | `1` drops `--headless=new` for a visible window |

The payoff is that no second browser is layered into the image: Chrome is already
there as a Flatpak, and Playwright cannot launch a Flatpak directly, so the image
starts it and lets the CLI connect.

---

## The four tools

| Tool | What it does | How it installs |
| --- | --- | --- |
| **opencode-fusion** | Main/sidekick agent team: a main agent plans and reviews, a cheap sidekick makes the edits | `npx -y skills add mihneaptu/opencode-fusion --skill fusion-setup`, then its own `install.js apply` with the `opencode-go` profile |
| **caveman** | Skills that cut model output roughly 65% | `npx -y skills add JuliusBrussee/caveman -a claude-code -a codex -a opencode` |
| **rtk** | Compresses shell output before it reaches context | `brew "rtk"`, then `rtk init -g` three times: `--auto-patch`, `--opencode`, `--codex` |
| **@playwright/cli** | Token-lean browser automation | Skill only — the binary is the image wrapper above |

Two of those steps carry a trap the installer works around.

The fusion step passes `--config "$repo_root/tooling/data/ai-tools/opencode-mcp-fragment.json"`
and `--adopt-config`. The fragment is our context7 MCP block with a secret-free
`{file:~/.config/opencode/context7-key}` header; `--adopt-config` makes re-runs
idempotent by accepting an `opencode.json` edited since the last install as the
baseline, still merging the fragment in.

The playwright step does **not** run `npm install -g` on this machine. The image
already ships the binary, and a global npm install fails anyway on brew-managed
node, whose global directory is not user-writable. The installer only copies the
skill out of the npx cache into `~/.claude/skills/playwright-cli` and
`~/.codex/skills/playwright-cli`.

`install-ai-tools` also runs `herdr integration install` for all three CLIs, so a
herdr server restart resumes the conversation with each CLI's native session
identity instead of dropping the pane to a bare shell. herdr itself is covered in
[dev-environment.md](dev-environment.md).

---

## First-time setup

Two commands, once, after switching a machine to a new image:

```bash
just brew-apply         # the CLI casks, rtk, herdr, and any other new Brewfile entries
just ai-tools-install   # install the tools, offer logins, store the Context7 key
```

`ai-tools-install` walks the interactive parts for you:

- **Logins.** It offers `codex login`, `claude auth login` and `opencode auth login`
  in turn, detecting each by its auth file (`~/.codex/auth.json`,
  `~/.claude/.credentials.json`, `~/.local/share/opencode/auth.json`) and printing
  `already logged in` instead of prompting. Answer `n` to defer one; it prints the
  command to run later. With no TTY it prompts for nothing and just tells you what
  to run.
- **The Context7 key.** Hidden input (`read -r -s`), written with `umask 077` to
  `~/.config/opencode/context7-key` inside a `0700` directory — the key is never
  echoed or logged. Press Enter to skip.

To re-enter the key, delete `~/.config/opencode/context7-key` and re-run
`just ai-tools-install`. A non-empty file makes the step report that the key is
already set and move on without prompting.

Restart each CLI afterwards so it reloads its config.

---

## Everyday commands

| Command | What it does |
| --- | --- |
| `just ai-diff` | Report how live config has drifted from canonical. Read-only; exits non-zero when anything drifted |
| `just ai-reset` | Restore config to canonical. Dry run by default; `--force` writes, after a timestamped backup |
| `just ai-tools-install` | (Re)install the four tools, offer logins, store the Context7 key |
| `just ai-tools-uninstall` | Remove the four tools. Config, auth and history are untouched |
| `just ai-bundle` | Regenerate the portable `tooling/ai/ai-cli-setup/` bundle from the seeds |

`ai-diff` is `reset-ai-cli --diff`; both are the same script. Useful flags beyond
`--force`:

| Flag | Effect |
| --- | --- |
| `--tool codex\|claude\|opencode` | Limit to one tool; repeatable. Default is all three |
| `--replace` | Hard-overwrite the two mixed files with the seed, dropping preserved machine state |

`ai-reset` refuses to run while a target CLI is running, because each rewrites its
own config on exit and would silently clobber the reset. Quit it, or scope around it
with `--tool`. `ai-diff` is exempt: it writes nothing, so the guard does not apply.
Backups go to
`$XDG_STATE_HOME/workstation-os-image/ai-cli-reset-backup/<timestamp>/`.

### Reset to a clean base

Canonical config, no tools, logins and history intact:

```bash
just ai-tools-uninstall
just ai-reset --force
```

Reverse it with `just ai-tools-install`.

---

## The portable bundle

`tooling/ai/ai-cli-setup/` does the same install on a machine that has neither this
image nor chezmoi — any Linux or macOS account with Node, npm and `jq`. It has its
own `install.sh` (create-only config copy, then the same official installers, then
the same login offers and key prompt) and its own `reset.sh`. See
[tooling/ai/ai-cli-setup/README.md](../../tooling/ai/ai-cli-setup/README.md).

The bundle's `config/` tree and its `opencode-mcp-fragment.json` are **generated**,
not authored: `just ai-bundle` runs `tooling/ai/build-ai-cli-bundle`, which walks the
same `tooling/data/dotfiles.manifest`, projects every `copy`, `scrub`, `tree` and
`directory` entry whose live path starts `.codex/`, `.claude/` or
`.config/opencode/` into `config/<tool>/...`, and copies
`tooling/data/ai-tools/opencode-mcp-fragment.json` in beside it. Everything else in
the bundle — `install.sh`, `reset.sh`, `README.md`, `secrets.example` — is a
committed artifact the generator never touches.

`build-ai-cli-bundle --check` regenerates into a temporary tree and diffs it against
the committed bundle instead of writing, failing with
`tooling/ai/ai-cli-setup is stale: run 'just ai-bundle' and commit.`
`tooling/validate/all` calls it, so `just validate` asserts the bundle is in sync
with the seeds.

> Never hand-edit anything under `tooling/ai/ai-cli-setup/config/` or the bundle's
> `opencode-mcp-fragment.json`. Change the live file, run `just sync` to refresh the
> seed, then `just ai-bundle` to reproject. Two files share the name
> `opencode-mcp-fragment.json`: `tooling/data/ai-tools/opencode-mcp-fragment.json` is
> the tracked source, and `tooling/ai/ai-cli-setup/opencode-mcp-fragment.json` is the
> generated copy.

---

## Invariants

**The two mixed files are secret-free by construction, not by review.**
`.codex/config.toml` and `.claude/settings.json` are captured through the `scrub`
manifest kind, which pipes the live file through a filter in `tooling/scrub/` before
it becomes a seed:

- `tooling/scrub/claude-settings` runs
  `del(.env, .enabledPlugins, .extraKnownMarketplaces, .hooks, .autoMode.environment) | .model = "opus[1m]"`
  with `--sort-keys`. `.env` carries API credentials; `.enabledPlugins` and
  `.extraKnownMarketplaces` carry absolute install paths; `.hooks` holds the hooks
  installed tools register (rtk's `PreToolUse` entry, herdr's session hook and its
  absolute home path). `.autoMode.environment` is the sharpest one — Claude Code
  rewrites it per project with organisation names, private repository names, secret
  names and internal domains, this repository is public, and gitleaks recognises none
  of it.
- `tooling/scrub/codex-config` keeps only the portable top-level scalars up to the
  first table, then emits one canonical, secret-free `[mcp_servers.openaiDeveloperDocs]`
  table pointing at `https://developers.openai.com/mcp` (OpenAI's developer-docs MCP
  needs no credentials). Machine-local `[projects.*]` trust tables and `[tui.*]` NUX
  state never reach the seed. Rebuilding the table rather than copying the live block
  is what stops an inline secret from riding along.

The filters are not trusted on their word. `tooling/validate/sources` re-asserts the
outcome on the committed seeds and again on the generated bundle: no `env` key, no
`helpscout` string, no `enabledPlugins`/`extraKnownMarketplaces`, no absolute home
path, `.autoMode.environment == null`, and exactly one table in the codex seed. gitleaks misses tool-specific key
shapes — the dash-broken context7 key is the example named in the gate — so these
hand-written assertions are the real secret boundary, and
[../supply-chain.md](../supply-chain.md) covers them as a set.

> Never revert `.codex/config.toml` or `.claude/settings.json` to a plain `copy`
> manifest entry. A `copy` publishes the live file verbatim, which for these two
> means credentials and a client's internals.

**`ai-reset` merges; it does not stamp.** chezmoi cannot do this reset at all —
`create_` targets are never rewritten once they exist — so an explicit out-of-band
reset is the sanctioned bridge. For the two `scrub` files it restores the canonical
portable keys while preserving exactly the machine state the seed deliberately omits:

- codex — the seed is emitted first, then `[features]`, `[projects.*]` and `[tui.*]`
  tables are copied verbatim from the live file, per table. Copying only those blocks
  rather than the whole tail keeps a no-op reset byte-identical and never redefines a
  portable table that happens to sit after them, which would make the TOML
  unparseable. `[features]` carries `hooks = true`, which
  `herdr integration install codex` sets, so dropping it would silently disable
  agent-state reporting.
- claude — `jq -s '.[0] * .[1]'` over live then seed, so the seed wins on shared keys
  and live-only keys (`env`, `enabledPlugins`, `extraKnownMarketplaces`) survive.

It never touches auth stores, credential files, histories, sessions, databases, or
any path outside the manifest. `--replace` opts out of the merge.

**Third-party tools are never vendored.** Everything the four installers produce
lives outside the repository and is expected to differ from a fresh install: rtk's
Claude `hooks` block, its opencode plugin, the `RTK.md` files it writes, the caveman
and fusion skill trees, the copied playwright-cli skill. None of them are in the
manifest, so `just audit` never asks about them. The one exception is the single
`@RTK.md` include line at the end of `.codex/AGENTS.md` and `.claude/CLAUDE.md`,
which is part of those captured files — which is why `install-ai-tools` rewrites
rtk's absolute `@$HOME/.codex/RTK.md` reference into a relative `@RTK.md`, so the
live file keeps matching the seed and capture stays stable.

**`opencode.json` is generated, never captured.** The fusion installer writes it.
Only our context7 fragment is tracked, and `tooling/validate/sources` asserts its
key is a `{file:}` or `{env:}` placeholder and never a literal.

---

## Gotchas and tech debt

`just capture` fails on any change to an AI seed. The recipe is `capture: sync
validate`, with nothing between them: `sync` rewrites the seeds from live, then
`validate` runs `build-ai-cli-bundle --check`, which sees the bundle still projecting
the old seeds and exits 1. Run the steps by hand instead — `just sync`, then
`just ai-bundle`, then `just validate`.

`ai-diff` compares live against the *merged* canonical, not against the raw seed, so
the machine state the merge preserves — `env`, `enabledPlugins`, `[projects.*]` trust
grants, `[tui.*]` NUX state — never surfaces as drift. What does surface is live
content the canonical deliberately excludes: an unapproved `[mcp_servers.*]` table,
or a `model` other than the pinned `opus[1m]`. Both are things `ai-reset --force`
would rewrite, so read the report as "what a reset would change", not as a capture
backlog. `just audit` answers the capture question instead:
`tooling/audit/personal-config` runs the scrub filter over the live file before
comparing, so only portable-content divergence surfaces.

Three committed files — `tooling/ai/build-ai-cli-bundle`, `tooling/validate/all` and
the bundle's own `README.md` — still describe a `vendor/` directory inside
`tooling/ai/ai-cli-setup/`. It does not exist and is not tracked; the bundle's
committed artifacts are the four named above. That README also describes
`@playwright/cli` as an `npm i -g`, which is exactly what the on-image installer
refuses to do.

The playwright CDP endpoint defaults to loopback port 9222, and the Chrome profile
lives on the tmpfs runtime directory, so it is discarded at every reboot. Anything
requiring a logged-in browser session has to log in again each boot.

`ai-tools-install` needs Node 20.12 or newer and the `rtk`/`herdr` binaries already
present; run `just brew-apply` first or the rtk and herdr steps print a warning and
skip. It also depends on the upstream skill registries being reachable, so it is not
usable offline.

---

## Where to go next

[../capturing-changes.md](../capturing-changes.md) is the full audit -> capture ->
sync -> validate loop that the manifest entries above plug into, and the place to
look when you want to add a new AI config file rather than change an existing one.
[../supply-chain.md](../supply-chain.md) covers the scrub filters and secret gates as
a whole, including why the hand-written assertions exist alongside gitleaks. For the
Brewfile entries that put the three CLIs and rtk on the machine in the first place,
see [packages.md](packages.md); for the herdr panes these agents are meant to run
inside, and the per-branch worktrees the seeded `worktree-*` helpers drive, see
[dev-environment.md](dev-environment.md).
