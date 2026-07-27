#!/usr/bin/env bash
# Portable installer: lays this repo's personal codex / Claude Code / opencode
# config into $HOME (create-only), then installs the AI CLI tools via their
# OFFICIAL installers -- nothing third-party is vendored here. Works on any
# Linux/macOS account; no workstation image or chezmoi required.
#
# Secrets are never shipped: provider auth is each CLI's own `auth login`, and
# the opencode context7 key lands in a local 0600 file the config references via
# a {file:} placeholder. See ./secrets.example.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cfg="$here/config"

profile="opencode-go"
assume_yes=false

usage() {
    cat <<'EOF'
Usage: ./install.sh [--profile NAME] [--yes]
  --profile NAME  opencode-fusion subscription profile (default opencode-go).
                  Available: opencode-go opencode-zen opencode-zen-free
                  chatgpt github-copilot
  --yes           non-interactive: skip the optional context7 key prompt.
Existing files in ~/.codex, ~/.claude, ~/.config/opencode are never overwritten.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --profile) shift; [[ $# -gt 0 ]] || { echo "--profile needs a value" >&2; exit 2; }; profile="$1" ;;
        --yes | -y) assume_yes=true ;;
        -h | --help) usage; exit 0 ;;
        *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
    esac
    shift
done

have() { command -v "$1" >/dev/null 2>&1; }

copy_create_only() {
    local src=$1 dest=$2 f rel mode
    [[ -d $src ]] || return 0
    while IFS= read -r f; do
        rel="${f#"$src/"}"
        if [[ -e $dest/$rel ]]; then
            printf '  keep     %s\n' "$rel"
        else
            mode="$(stat -c %a "$f" 2>/dev/null || stat -f %Lp "$f" 2>/dev/null || echo 644)"
            mkdir -p "$(dirname "$dest/$rel")"
            install -m "$mode" "$f" "$dest/$rel"
            printf '  install  %s\n' "$rel"
        fi
    done < <(find "$src" -type f | LC_ALL=C sort)
}

node_major_ok() {
    have node || return 1
    local v major minor
    v="$(node -v 2>/dev/null)"; v="${v#v}"
    major="${v%%.*}"; minor="${v#*.}"; minor="${minor%%.*}"
    (( major > 20 )) || { (( major == 20 )) && (( minor >= 12 )); }
}

# --- 1. Personal config (create-only) -----------------------------------------
echo "== personal config =="
copy_create_only "$cfg/codex" "$HOME/.codex"
copy_create_only "$cfg/claude" "$HOME/.claude"
copy_create_only "$cfg/opencode" "$HOME/.config/opencode"

# --- 2. Tools via their official installers -----------------------------------
echo "== rtk =="
if ! have rtk; then
    if have brew; then brew install rtk
    else curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/master/install.sh | sh
    fi
fi
if have rtk; then
    rtk init -g --auto-patch    # Claude PreToolUse hook + RTK.md
    rtk init -g --opencode      # opencode plugin
    rtk init -g --codex         # codex RTK.md + AGENTS.md reference
else
    echo "  rtk not installed; see https://github.com/rtk-ai/rtk" >&2
fi

echo "== caveman =="
if have npx; then
    npx -y skills add JuliusBrussee/caveman -a claude-code -a codex -a opencode -y
else
    echo "  npx (Node) required for caveman; see https://github.com/JuliusBrussee/caveman" >&2
fi

echo "== opencode-fusion (profile: $profile) =="
if node_major_ok; then
    npx -y skills add mihneaptu/opencode-fusion --skill fusion-setup -g -a opencode -y
    node "$HOME/.agents/skills/fusion-setup/scripts/install.js" apply \
        --profile "$profile" \
        --config "$here/opencode-mcp-fragment.json" \
        --extras commands,plugin
else
    echo "  Node >= 20.12 required for opencode-fusion; skipped." >&2
fi

echo "== playwright-cli =="
if have npm; then
    npm install -g @playwright/cli
    # Off-image there is no Flatpak wrapper, so let the CLI manage its own
    # chromium and place its skill.
    have playwright-cli && playwright-cli install --skills || true
else
    echo "  npm required for playwright-cli; see @playwright/cli on npm" >&2
fi

# --- 3. Secrets ---------------------------------------------------------------
if ! $assume_yes && [[ -t 0 ]] && [[ ! -e $HOME/.config/opencode/context7-key ]]; then
    printf '\nContext7 API key (blank to skip, set later): '
    read -r -s context7_key
    printf '\n'
    if [[ -n $context7_key ]]; then
        install -d -m 0700 "$HOME/.config/opencode"
        umask 077
        printf '%s\n' "$context7_key" > "$HOME/.config/opencode/context7-key"
        echo "  wrote ~/.config/opencode/context7-key (0600)"
    fi
fi

cat <<'EOF'

== One-time secrets & auth (see ./secrets.example) ==
  codex:    codex login
  claude:   run `claude`, then /login
  opencode: opencode auth login        (select your provider/subscription)
  Context7 (opencode MCP): put the key in ~/.config/opencode/context7-key (0600)

Restart each CLI so it reloads config.
EOF
