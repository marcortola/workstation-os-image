# ai-cli-setup

A portable setup for three AI coding CLIs — **codex**, **Claude Code**, and
**opencode** — that you can drop onto any Linux/macOS account. No workstation
image or chezmoi required.

`install.sh` does two things: lays down this repo's **personal config**
(secret-free — no keys, tokens, or machine paths) create-only, then installs the
**AI tools via their own official installers** (nothing third-party is vendored
here). You supply secrets afterwards via each CLI's `auth login` and local
the Context7 credential file (see `secrets.example`).

## Prerequisites

- The CLIs you use: `codex`, `claude`, `opencode`.
- **Node ≥ 20.12** and `npm`/`npx` (for caveman, opencode-fusion, playwright-cli).
- `jq` (for `reset.sh`). Optionally Homebrew (for rtk; else a curl fallback).

## Install

```bash
./install.sh                     # default opencode-go fusion profile
./install.sh --profile chatgpt   # different opencode-fusion subscription profile
./install.sh --yes               # non-interactive (skips the context7 key prompt)
```

Existing files in `~/.codex`, `~/.claude`, `~/.config/opencode` are **never
overwritten**. Then do the one-time secret/auth steps it prints and restart each CLI.

## What it installs

**Personal config** (create-only): codex `AGENTS.md`/`config.toml`/MCP launcher/skills; claude
`CLAUDE.md`/`settings.json`/`rules`/`skills`/worktree commands; opencode `AGENTS.md`
+ worktree commands.

**Tools, via their official installers:**
- [**opencode-fusion**](https://github.com/mihneaptu/opencode-fusion) — main/sidekick
  agent team; `skills add` + its `install.js` with your profile and our context7
  MCP fragment, which generates `opencode.json`.
- [**caveman**](https://github.com/JuliusBrussee/caveman) — ~65% output-token
  reduction skills (`skills add`; toggle `/caveman`).
- [**rtk**](https://github.com/rtk-ai/rtk) — Bash-output compressor; `rtk init`
  wires the Claude hook, opencode plugin, and codex reference.
- **@playwright/cli** — token-lean browser automation (`npm i -g` + its skill;
  off-image it manages its own chromium).

## Secrets

Nothing secret ships here. After install:

- **Auth**: `codex login`; run `claude` then `/login`; `opencode auth login`.
- **Context7 key** (opencode MCP): the config references
  `{file:~/.config/opencode/context7-key}` — put your key in that 0600 file
  (install.sh offers to do this interactively).

## Reset

```bash
./reset.sh                   # dry run: show what would change
./reset.sh --force           # restore personal config to canonical (backup first)
./reset.sh --force --replace # also drop preserved machine state (trust grants, live keys)
./reset.sh --diff --tool codex
```

Reset restores the **personal config** (merging, so it preserves codex
project-trust tables and claude's `env` block); it does not touch the installed
tools — re-run `./install.sh` for those. It refuses while a target CLI is
running and never touches auth stores, histories, sessions, or databases.

## Provenance

`config/` and `opencode-mcp-fragment.json` are **generated** from the workstation
repo's canonical seeds by `just ai-bundle` — don't hand-edit them; change the
seeds and regenerate. `install.sh`, `reset.sh`, `secrets.example`, `vendor/` and
this README are maintained here directly.
