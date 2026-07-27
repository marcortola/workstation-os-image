#!/usr/bin/env bash
# Portable reset: restore live codex / claude / opencode config to this bundle's
# canonical. Dry-run by default; --force writes after a timestamped backup and
# refuses while a target CLI is running. The three mixed files are merged so
# canonical portable keys are restored while machine state is preserved (codex
# trust tables, the live context7 key, claude's env/plugin blocks); --replace
# hard-overwrites instead. Never touches auth stores, histories, or databases.
# Requires jq. Mirrors the workstation repo's tooling/ai/reset-ai-cli.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cfg="$here/config"

force=false
diff_only=false
replace=false
tools=()

usage() {
    cat <<'EOF'
Usage: ./reset.sh [--diff] [--force] [--replace] [--tool codex|claude|opencode]...
  (default)  dry run: print what would change, write nothing
  --force    apply (timestamped backup first)
  --diff     report drift, read-only
  --replace  hard-overwrite the mixed files, dropping preserved machine state
  --tool T   limit to one tool (repeatable); default all three
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --force) force=true ;;
        --diff) diff_only=true ;;
        --replace) replace=true ;;
        --tool) shift; [[ $# -gt 0 ]] || { echo "--tool needs a value" >&2; exit 2; }; tools+=("$1") ;;
        codex | claude | opencode) tools+=("$1") ;;
        -h | --help) usage; exit 0 ;;
        *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
    esac
    shift
done
[[ ${#tools[@]} -eq 0 ]] && tools=(codex claude opencode)

command -v jq >/dev/null 2>&1 || { echo "reset needs jq installed." >&2; exit 1; }

live_root() {
    case "$1" in
        codex) printf '%s' "$HOME/.codex" ;;
        claude) printf '%s' "$HOME/.claude" ;;
        opencode) printf '%s' "$HOME/.config/opencode" ;;
    esac
}

is_mixed() {
    case "$1/$2" in
        codex/config.toml | claude/settings.json | opencode/opencode.json) return 0 ;;
        *) return 1 ;;
    esac
}

tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT

backup_root=""
ensure_backup_root() {
    [[ -n $backup_root ]] && return
    local state_home="${XDG_STATE_HOME:-$HOME/.local/state}"
    backup_root="$state_home/ai-cli-setup/reset-backup/$(date +%Y%m%d-%H%M%S)"
}

merge_seed() {
    local id=$1 live=$2 seed=$3
    case "$id" in
        codex/config.toml)
            # Per-table copy of the machine tables (symmetric with capture); do
            # not copy the whole tail, or a portable table after them redefines
            # and breaks the TOML.
            cat "$seed"
            awk '
                /^\[(projects|tui)([.]|\])/ { k = 1; print; next }
                /^\[/                       { k = 0 }
                k                           { print }
            ' "$live"
            ;;
        claude/settings.json)
            jq -s '.[0] * .[1]' "$live" "$seed"
            ;;
        opencode/opencode.json)
            jq -s '
                .[0] as $live | .[1] as $seed
                | ($live.mcp.context7.headers.CONTEXT7_API_KEY // "") as $k
                | $seed
                | if $k != "" and ($k | startswith("{file:") | not)
                  then .mcp.context7.headers.CONTEXT7_API_KEY = $k
                  else . end
            ' "$live" "$seed"
            ;;
    esac
}

status=0
apply_content() {
    local live=$1 disp=$2 src=$3
    if $diff_only; then
        if [[ ! -f $live ]]; then printf '  %-9s %s\n' absent "$disp"; status=1
        elif ! cmp -s "$src" "$live"; then printf '  %-9s %s\n' drift "$disp"; status=1
        fi
        return
    fi
    [[ -f $live ]] && cmp -s "$src" "$live" && return 0
    printf '  %-9s %s\n' reset "$disp"
    if $force; then
        local mode
        if [[ -f $live ]]; then
            ensure_backup_root
            # GNU stat -c / BSD stat -f; fall back to 0644.
            mode="$(stat -c %a "$live" 2>/dev/null \
                || stat -f %Lp "$live" 2>/dev/null || echo 644)"
            mkdir -p "$(dirname "$backup_root/$disp")"
            install -m "$mode" "$live" "$backup_root/$disp"
        fi
        mkdir -p "$(dirname "$live")"
        install -m 0644 "$src" "$live"
    fi
}

if ! $diff_only && [[ -z ${RESET_AI_CLI_SKIP_PROC_GUARD:-} ]]; then
    for t in "${tools[@]}"; do
        if pgrep -x "$t" >/dev/null 2>&1; then
            echo "Refusing: $t is running (it rewrites its config on exit). Quit it and retry." >&2
            exit 1
        fi
    done
fi

if $diff_only; then echo "AI CLI config drift vs bundle canonical (tools: ${tools[*]}):"
elif $force; then echo "Resetting AI CLI config to bundle canonical (tools: ${tools[*]}):"
else echo "AI CLI config reset -- DRY RUN, pass --force to write (tools: ${tools[*]}):"
fi

for t in "${tools[@]}"; do
    tool_cfg="$cfg/$t"
    [[ -d $tool_cfg ]] || continue
    root="$(live_root "$t")"
    while IFS= read -r seed; do
        rel="${seed#"$tool_cfg/"}"
        live="$root/$rel"
        src="$tmp/${t}_${rel//\//_}"
        if is_mixed "$t" "$rel" && [[ -f $live ]] && ! $replace; then
            merge_seed "$t/$rel" "$live" "$seed" > "$src"
        else
            cp "$seed" "$src"
        fi
        apply_content "$live" "$t/$rel" "$src"
    done < <(find "$tool_cfg" -type f | LC_ALL=C sort)
done

if $force && [[ -n $backup_root ]]; then echo "Backup written to $backup_root"; fi
if ! $diff_only && ! $force; then echo "(dry run -- nothing written; pass --force to apply)"; fi
exit "$status"
