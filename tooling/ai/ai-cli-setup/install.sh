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

# Offer a CLI login: skip if already authed or --yes/non-TTY, else ask before
# opening the browser flow.
login_offer() {
    local name=$1 auth=$2; shift 2
    if [[ -s $auth ]]; then
        echo "  $name: already logged in"
    elif $assume_yes || [[ ! -t 0 ]]; then
        echo "  $name: not logged in -- run: $*"
    else
        read -r -p "  Log in to $name now? [Y/n] " reply
        case "${reply:-y}" in
            [Nn]*) echo "  $name: skipped -- run \`$*\` later" ;;
            *) "$@" || echo "  $name: login did not complete -- run \`$*\` later" ;;
        esac
    fi
}

# --- 1. Personal config (create-only) -----------------------------------------
echo "== personal config =="
copy_create_only "$cfg/codex" "$HOME/.codex"
copy_create_only "$cfg/claude" "$HOME/.claude"
copy_create_only "$cfg/opencode" "$HOME/.config/opencode"

# --- 2. Tools via their official installers -----------------------------------
# Run installers from $HOME so skills.sh/npm don't drop files in the CWD.
cd "$HOME"
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
        --extras commands,plugin \
        --adopt-config
else
    echo "  Node >= 20.12 required for opencode-fusion; skipped." >&2
fi

echo "== playwright-cli =="
if have npx; then
    # A user-space npx wrapper avoids `npm install -g` (which fails on
    # brew-managed node, whose global dir is not user-writable) and needs no root.
    mkdir -p "$HOME/.local/bin"
    cat > "$HOME/.local/bin/playwright-cli" <<'WRAP'
#!/usr/bin/env bash
exec npx -y @playwright/cli@latest "$@"
WRAP
    chmod +x "$HOME/.local/bin/playwright-cli"
    npx -y @playwright/cli@latest --version >/dev/null 2>&1 || true
    pw_skill="$(find "$HOME/.npm/_npx" -path '*cli-client/skill' -type d 2>/dev/null | head -1)"
    if [[ -n ${pw_skill:-} ]]; then
        for agent in claude codex; do
            rm -rf "$HOME/.$agent/skills/playwright-cli"
            cp -rL "$pw_skill" "$HOME/.$agent/skills/playwright-cli"
        done
    fi
    # Off-image the CLI manages its own chromium; fetch it now (non-fatal).
    PATH="$HOME/.local/bin:$PATH" playwright-cli install-browser chromium >/dev/null 2>&1 || true
    echo "  installed playwright-cli wrapper + skill (ensure ~/.local/bin is on PATH)"
else
    echo "  npx (Node) required for playwright-cli" >&2
fi

# --- 3. Logins ----------------------------------------------------------------
echo "== logins =="
login_offer codex "$HOME/.codex/auth.json" codex login
login_offer claude "$HOME/.claude/.credentials.json" claude auth login
login_offer opencode "$HOME/.local/share/opencode/auth.json" opencode auth login

# --- 4. Context7 key ----------------------------------------------------------
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

== If you skipped anything above ==
  codex login ; claude auth login ; opencode auth login
  Context7 (opencode MCP): put the key in ~/.config/opencode/context7-key (0600)

Restart each CLI so it reloads config.
EOF
