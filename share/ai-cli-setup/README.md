# ai-cli-setup

A portable, deterministic setup for three AI coding CLIs — **codex**, **Claude
Code**, and **opencode** (with the [opencode-fusion](https://github.com/mihneaptu/opencode-fusion)
main/sidekick team) — that you can drop onto any Linux/macOS account. No
workstation image, chezmoi, or Zirconium required.

The config here is **secret-free by construction**: no API keys, tokens, or
machine-specific paths. You supply secrets locally after install via each CLI's
own `auth login` and a couple of local key files (see `secrets.example`).

## Prerequisites

- The CLIs you want: `codex`, `claude`, `opencode` (install whichever you use).
- **Node ≥ 20.12** — only needed if you pick an opencode profile other than the
  default `opencode-go` (the fusion installer runs under Node).

## Install

```bash
./install.sh                 # default opencode-go profile
./install.sh --profile chatgpt   # regenerate opencode models for your subscription
./install.sh --yes           # non-interactive (skips the context7 key prompt)
```

Existing files in `~/.codex`, `~/.claude`, `~/.config/opencode` are **never
overwritten** — install is create-only. Then do the one-time secret/auth steps
it prints (also in `secrets.example`) and restart each CLI.

Available opencode profiles: `opencode-go` `opencode-zen` `opencode-zen-free`
`chatgpt` `github-copilot`. A non-`opencode-go` profile re-runs the vendored
fusion installer (`vendor/fusion-setup/scripts/install.js`) so the model
assignments match your subscription; the agent prompts are identical either way.

## What it installs

- **codex** → `~/.codex/`: `AGENTS.md`, `config.toml` (portable defaults; your
  project-trust grants are yours to add), skills.
- **claude** → `~/.claude/`: `CLAUDE.md`, `settings.json` (no secrets),
  `rules/`, `skills/`, worktree commands.
- **opencode** → `~/.config/opencode/`: fusion agents (build/plan/sidekick/
  explore/research/design/reviewer), fusion commands, audit plugin, `AGENTS.md`,
  and `opencode.json` wiring models + the context7/playwright MCP servers.

Token-optimization tooling is included: the **caveman** skills (~65% output
reduction, toggle with `/caveman`) and **rtk** (a Bash-output compressor wired
as a Claude `PreToolUse` hook + an opencode plugin). install.sh installs the rtk
binary because the shipped Claude hook needs it on PATH; remove the hook from
`~/.claude/settings.json` if you don't want it. rtk has no codex integration.

## Secrets

Nothing secret ships here. After install:

- **Auth**: `codex login`; run `claude` then `/login`; `opencode auth login`.
- **Context7 key** (opencode MCP): `opencode.json` references
  `{file:~/.config/opencode/context7-key}` — put your key in that 0600 file
  (install.sh offers to do this interactively).

## Reset

```bash
./reset.sh                   # dry run: show what would change
./reset.sh --force           # restore config to canonical (timestamped backup first)
./reset.sh --force --replace # also drop preserved machine state (trust grants, live keys)
./reset.sh --diff --tool codex
```

Reset **merges**: it restores the canonical portable settings while preserving
machine-local state the shipped config omits — codex project-trust tables, your
live context7 key, and claude's `env`/plugin blocks. It refuses while a target
CLI is running, and never touches auth stores, histories, sessions, or
databases. Requires `jq`.

## Provenance

`config/` and `opencode-mcp-fragment.json` are **generated** from the workstation
repository's canonical seeds by `scripts/build-ai-cli-bundle` (`just ai-bundle`)
— don't hand-edit them; change the seeds and regenerate. `install.sh`,
`reset.sh`, `secrets.example`, and `vendor/` are maintained here directly.
