#!/usr/bin/env bash
# Portable installer for the codex / claude / opencode configuration in this
# bundle. Lays the canonical config into $HOME create-only (never overwrites an
# existing file), configures opencode-fusion from the vendored installer, and
# prints the one-time secret/auth steps. Works on any Linux/macOS account; it
# does not depend on the workstation image, chezmoi, or Zirconium.
#
# Secrets are never shipped or written to git: tool auth is done with each CLI's
# own `auth login`, and the opencode context7 key lands in a local 0600 file the
# config references via a {file:} placeholder. See ./secrets.example.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cfg="$here/config"

profile="opencode-go"
assume_yes=false

usage() {
    cat <<'EOF'
Usage: ./install.sh [--profile NAME] [--yes]

  --profile NAME  opencode subscription profile for fusion (default opencode-go).
                  Any other value regenerates opencode.json via the vendored
                  fusion installer so the models match your subscription.
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

# Create-only copy: install every file under $1 into $2 unless it already exists.
copy_create_only() {
    local src=$1 dest=$2 f rel mode
    [[ -d $src ]] || return 0
    while IFS= read -r f; do
        rel="${f#"$src/"}"
        if [[ -e $dest/$rel ]]; then
            printf '  keep     %s\n' "$rel"
        else
            # GNU stat -c / BSD stat -f; portable install (BSD install has no -D).
            mode="$(stat -c %a "$f" 2>/dev/null || stat -f %Lp "$f" 2>/dev/null || echo 644)"
            mkdir -p "$(dirname "$dest/$rel")"
            install -m "$mode" "$f" "$dest/$rel"
            printf '  install  %s\n' "$rel"
        fi
    done < <(find "$src" -type f | LC_ALL=C sort)
}

# Create-only install of a single file (the dir helper no-ops on a file arg).
install_file_create_only() {
    local src=$1 dest=$2
    if [[ -e $dest ]]; then
        printf '  keep     %s\n' "${dest##*/}"
    else
        mkdir -p "$(dirname "$dest")"
        install -m 0644 "$src" "$dest"
        printf '  install  %s\n' "${dest##*/}"
    fi
}

node_major_ok() {
    have node || return 1
    local v major minor
    v="$(node -v 2>/dev/null)"; v="${v#v}"
    major="${v%%.*}"; minor="${v#*.}"; minor="${minor%%.*}"
    (( major > 20 )) || { (( major == 20 )) && (( minor >= 12 )); }
}

echo "== codex =="
copy_create_only "$cfg/codex" "$HOME/.codex"

echo "== claude =="
copy_create_only "$cfg/claude" "$HOME/.claude"

echo "== opencode (profile: $profile) =="
if [[ $profile == opencode-go ]]; then
    copy_create_only "$cfg/opencode" "$HOME/.config/opencode"
else
    install_file_create_only "$cfg/opencode/AGENTS.md" "$HOME/.config/opencode/AGENTS.md"
    if ! node_major_ok; then
        echo "  Node >= 20.12 is required to configure a non-opencode-go profile." >&2
        echo "  Install Node and re-run, or use --profile opencode-go." >&2
        exit 1
    fi
    node "$here/vendor/fusion-setup/scripts/install.js" apply \
        --profile "$profile" \
        --config "$here/opencode-mcp-fragment.json" \
        --extras commands,plugin
fi

# rtk: the shipped Claude settings.json carries an `rtk hook claude` PreToolUse
# hook, so rtk must be on PATH or every Bash call fails with command-not-found.
echo "== rtk (bash-output token compressor) =="
if command -v rtk >/dev/null 2>&1; then
    echo "  keep     rtk $(rtk --version 2>/dev/null | awk '{print $2}')"
elif command -v brew >/dev/null 2>&1; then
    brew install rtk && echo "  installed rtk via brew"
else
    echo "  rtk is not installed. The Claude hook needs it -- install with:" >&2
    echo "    brew install rtk   # or:   curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/master/install.sh | sh" >&2
    echo "  Until then, remove the PreToolUse hook from ~/.claude/settings.json to avoid errors." >&2
fi

# Optional: write the context7 key file the opencode config references.
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
    printf %s 'YOUR_KEY' > ~/.config/opencode/context7-key && chmod 600 ~/.config/opencode/context7-key

Restart each CLI so it reloads config. Reset later with ./reset.sh (dry run) / ./reset.sh --force.
EOF
