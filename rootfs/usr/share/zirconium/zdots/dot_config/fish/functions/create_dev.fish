function dev --description "Run a command in the nearest Dev Container (no args = shell; `dev nvim` = Neovim in-container), starting it on demand"
    # realpath resolves symlinks (e.g. /home -> /var/home) so every path below
    # is compared against the same physical prefix.
    set -l start (realpath .)

    # Boundary for the upward search: never look above the repo root. Outside a
    # git repo there is no root to anchor to, so only the current directory is
    # considered — otherwise a stray ancestor .devcontainer (e.g. in $HOME) would
    # hijack resolution for any unrelated non-git subtree beneath it.
    set -l gitroot (git -C "$start" rev-parse --show-toplevel 2>/dev/null)
    if test -n "$gitroot"
        set gitroot (realpath "$gitroot")
    end
    set -l stopdir $gitroot
    test -z "$stopdir"; and set stopdir $start

    # Walk from the current directory up to the boundary and pick the FIRST
    # (nearest) directory that defines a Dev Container.
    set -l root
    set -l dir $start
    while true
        if test -f "$dir/.devcontainer/devcontainer.json"; or test -f "$dir/.devcontainer.json"
            set root $dir
            break
        end
        test "$dir" = "$stopdir"; and break    # reached the boundary, stop
        set -l parent (dirname "$dir")
        test "$parent" = "$dir"; and break     # hit the filesystem root
        set dir $parent
    end

    if test -z "$root"
        if test -n "$gitroot"
            echo "dev: no .devcontainer found from (pwd) up to the repo root ($gitroot)" >&2
        else
            echo "dev: no .devcontainer in (pwd), and not inside a git repo to search upward from" >&2
        end
        return 1
    end

    # devcontainer exec always starts in the workspace (root) folder, so mirror
    # the caller's subdirectory inside the container with a relative cd.
    set -l rel (realpath --relative-to="$root" .)

    # `dev nvim` runs the host Neovim CONFIG inside the container so LSP/DAP see
    # the project's real dependencies (vendor/, node_modules, site-packages).
    # Two bind mounts are attached to EVERY `up` (idempotent, so a plain `dev`
    # and `dev nvim` share one container with no rebuild): the host nvim config
    # (read-only by convention: it is copied into the store, never written), and
    # a per-project store that holds the in-container nvim binary, a private
    # Node, Mason servers and compiled treesitter parsers, persisted across
    # rebuilds. Host and container both run as uid 1000, so the store is
    # writable and its native artifacts match the container libc.
    set -l store "$HOME/.local/share/dev-nvim/"(echo -n "$root" | sha256sum | cut -c1-12)
    mkdir -p "$store/data" "$store/state" "$store/cache" "$store/config"
    set -l mounts \
        --mount "type=bind,source=$HOME/.config/nvim,target=/nvimconf-src" \
        --mount "type=bind,source=$store,target=/nvimdata"

    # Idempotent: builds/starts on first call, fast no-op once running.
    if not devcontainer up --workspace-folder "$root" $mounts >/dev/null 2>&1
        echo "dev: failed to start devcontainer — retry verbosely with:" >&2
        echo "     devcontainer up --workspace-folder $root $mounts" >&2
        return 1
    end

    if test "$argv[1]" = nvim
        # A container created earlier WITHOUT these mounts (e.g. by JetBrains
        # Gateway or an older `dev`) is reused by `up` with the mounts absent;
        # recreate it once so the config/store are actually present.
        if not devcontainer exec --workspace-folder "$root" bash -c 'test -f /nvimconf-src/init.lua -a -d /nvimdata'
            echo "dev nvim: container lacks the nvim mounts; recreating..." >&2
            devcontainer up --workspace-folder "$root" $mounts --remove-existing-container >/dev/null 2>&1
        end

        # Provision (idempotent): reset the store if the base image changed
        # (native artifacts are libc-bound), install a pinned+checksummed nvim,
        # a private Node for the node-based LSP servers, a C toolchain when the
        # base lacks it and passwordless sudo is available, then copy the host
        # config into the store so the container never writes back to it.
        set -l boot '
            set -e
            fp=$( (cat /etc/os-release 2>/dev/null; ldd --version 2>/dev/null | head -1; uname -m) | sha256sum | cut -c1-16)
            if [ "$(cat /nvimdata/.builtfor 2>/dev/null)" != "$fp" ]; then
                echo "dev nvim: base image changed — resetting store artifacts" >&2
                rm -rf /nvimdata/nvim /nvimdata/node /nvimdata/data /nvimdata/state /nvimdata/cache /nvimdata/config
                mkdir -p /nvimdata/data /nvimdata/state /nvimdata/cache /nvimdata/config
                echo "$fp" > /nvimdata/.builtfor
            fi
            ver=0.12.4
            if [ ! -x /nvimdata/nvim/bin/nvim ]; then
                echo "dev nvim: installing Neovim $ver in container" >&2
                b="https://github.com/neovim/neovim/releases/download/v$ver"
                curl -fsSL "$b/nvim-linux-x86_64.tar.gz" -o /tmp/nvim.tgz
                if curl -fsSL "$b/shasum.txt" -o /tmp/nvim.sha 2>/dev/null; then
                    want=$(grep nvim-linux-x86_64.tar.gz /tmp/nvim.sha | cut -d" " -f1)
                    got=$(sha256sum /tmp/nvim.tgz | cut -d" " -f1)
                    if [ -n "$want" ] && [ "$want" != "$got" ]; then echo "dev nvim: nvim checksum mismatch" >&2; exit 1; fi
                fi
                mkdir -p /nvimdata/nvim && tar xzf /tmp/nvim.tgz -C /nvimdata/nvim --strip-components=1
            fi
            if ! command -v node >/dev/null 2>&1 && [ ! -x /nvimdata/node/bin/node ]; then
                echo "dev nvim: installing Node.js in container (for LSP servers)" >&2
                nver=22.11.0
                curl -fsSL "https://nodejs.org/dist/v$nver/node-v$nver-linux-x64.tar.gz" -o /tmp/node.tgz
                mkdir -p /nvimdata/node && tar xzf /tmp/node.tgz -C /nvimdata/node --strip-components=1
            fi
            if ! command -v cc >/dev/null 2>&1 || ! command -v git >/dev/null 2>&1; then
                if command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
                    echo "dev nvim: installing build toolchain" >&2
                    sudo apt-get update -qq && sudo apt-get install -y -qq build-essential git curl >/dev/null
                else
                    echo "dev nvim: WARNING missing cc/git and no passwordless sudo; treesitter may fail" >&2
                fi
            fi
            rm -rf /nvimdata/config/nvim
            cp -a /nvimconf-src /nvimdata/config/nvim
            export XDG_CONFIG_HOME=/nvimdata/config XDG_DATA_HOME=/nvimdata/data XDG_STATE_HOME=/nvimdata/state XDG_CACHE_HOME=/nvimdata/cache NVIM_IN_CONTAINER=1
            export PATH=/nvimdata/node/bin:$PATH
            n=/nvimdata/nvim/bin/nvim
            if [ ! -f /nvimdata/data/.warmed ]; then
                echo "dev nvim: installing plugins (first run in this container)..." >&2
                for i in 1 2 3; do
                    if "$n" --headless "+Lazy! sync" +qa 2>&1 | grep -q "checkout failed"; then
                        echo "dev nvim: repairing plugin clones (attempt $i)" >&2
                    else
                        touch /nvimdata/data/.warmed; break
                    fi
                done
            else
                "$n" --headless "+Lazy! install" +qa >/dev/null 2>&1 || true
            fi
        '
        if not devcontainer exec --workspace-folder "$root" bash -c "$boot"
            echo "dev nvim: provisioning failed" >&2
            return 1
        end

        devcontainer exec --workspace-folder "$root" \
            --remote-env XDG_CONFIG_HOME=/nvimdata/config \
            --remote-env XDG_DATA_HOME=/nvimdata/data \
            --remote-env XDG_STATE_HOME=/nvimdata/state \
            --remote-env XDG_CACHE_HOME=/nvimdata/cache \
            --remote-env NVIM_IN_CONTAINER=1 \
            --remote-env COLORTERM=truecolor \
            --remote-env TERM=xterm-256color \
            bash -c 'export PATH=/nvimdata/node/bin:$PATH; cd "$1" || exit; shift; exec /nvimdata/nvim/bin/nvim "$@"' -- "$rel" $argv[2..-1]
    else if test (count $argv) -eq 0
        devcontainer exec --workspace-folder "$root" bash -c 'cd "$1" || exit; exec bash' -- "$rel"
    else
        devcontainer exec --workspace-folder "$root" bash -c 'cd "$1" || exit; shift; exec "$@"' -- "$rel" $argv
    end
end
