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
    # Which checkout this store belongs to, so `just dev-nvim-gc` can tell an
    # abandoned store from a live one exactly rather than by hashing candidates.
    echo "$root" >"$store/.root"
    # The nvim binary, fd and rg are the same bytes in every store (measured:
    # identical in all 14 copies, across both base-image fingerprints), so they
    # live once per fingerprint under toolchain/ instead of once per checkout --
    # which, with a store per worktree, meant re-downloading 15 MB for every new
    # branch. The whole toolchain/ directory is mounted rather than one
    # fingerprint's: the fingerprint is only knowable inside the container, and
    # the boot script links the right one into the store, so the launch command
    # below still spells /nvimdata/nvim and the fingerprint lives in one place.
    set -l toolchain "$HOME/.local/share/dev-nvim/toolchain"
    mkdir -p "$toolchain"
    set -l mounts \
        --mount "type=bind,source=$HOME/.config/nvim,target=/nvimconf-src" \
        --mount "type=bind,source=$HOME/.local/share/nvim/lazy,target=/nvim-plugins" \
        --mount "type=bind,source=$toolchain,target=/nvimtoolchain" \
        --mount "type=bind,source=$store,target=/nvimdata"

    # lazygit is LazyVim's <leader>gg, and LazyVim only creates that keymap
    # where the binary exists -- which is the container, not the host, once
    # nvim runs inside one. It is a static Go binary, so the host copy runs in
    # any base image: mount it rather than downloading a second one into every
    # project store. Its config rides along so the theme and nerd-font icons
    # match the host, copied (not mounted) into place below because lazygit
    # writes state beside it.
    if type -q lazygit
        set -a mounts --mount \
            "type=bind,source="(realpath (command -v lazygit))",target=/usr/local/bin/lazygit"
    end
    if test -d "$HOME/.config/lazygit"
        set -a mounts --mount \
            "type=bind,source=$HOME/.config/lazygit,target=/lazygitconf-src"
    end

    # A linked worktree's `.git` is a FILE pointing at the main repo, so the
    # checkout alone is not a repository once bind-mounted. This flag mounts the
    # common `.git` beside it -- but only where the worktree records a relative
    # path, which is why the git config sets `worktree.useRelativePaths`. On a
    # normal checkout, and on a worktree with an absolute path, it is inert.
    # Every `exec` needs it too: the remote workspace folder is derived the
    # same way, so omitting it there chdirs to a path the container lacks.
    set -l dcflags --mount-git-worktree-common-dir

    # Idempotent: builds/starts on first call, fast no-op once running. The
    # output is captured rather than discarded so a failure can report the CLI's
    # own message: a rejected flag or a broken build is otherwise invisible.
    set -l uplog (mktemp)
    if not devcontainer up --workspace-folder "$root" $dcflags $mounts >$uplog 2>&1
        echo "dev: failed to start devcontainer:" >&2
        tail -n 20 $uplog >&2
        echo "dev: retry verbosely with:" >&2
        echo "     devcontainer up --workspace-folder $root $dcflags $mounts" >&2
        rm -f $uplog
        return 1
    end
    rm -f $uplog

    if test "$argv[1]" = nvim
        # A container created earlier WITHOUT these mounts (e.g. by JetBrains
        # Gateway or an older `dev`) is reused by `up` with the mounts absent;
        # recreate it once so the config/store are actually present. The probe
        # is a bare `test`, so it rides inside the provisioning script below
        # rather than paying its own `devcontainer exec`: a round trip measured
        # 370-484 ms on every launch (docs/design-records/dev-nvim-store.md).
        set -l ready 'test -f /nvimconf-src/init.lua -a -d /nvimdata -a -d /nvim-plugins -a -d /nvimtoolchain'
        # A worktree recorded RELATIVELY also needs the common `.git` mounted,
        # which a container created before that flag lacks. Resolve the pointer
        # with sed rather than git: a base image without git, or one that trips
        # over `dubious ownership`, would otherwise fail this check forever and
        # recreate the container on every launch. An absolute pointer is skipped
        # because the flag is inert there and recreating would fix nothing.
        if test -f "$root/.git"; and string match -qr '^gitdir: [^/]' (head -n1 "$root/.git")
            set ready "$ready && test -e \"\$(sed -n 's/^gitdir: *//p' .git)\""
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
            # Shared across every checkout on this base image. The install
            # guards are test-then-act and the destination is now shared, so
            # each artifact is staged privately and renamed into place: two cold
            # launches at once then produce one good copy and one discarded
            # download, never a half-extracted binary. There is no lock.
            tc=/nvimtoolchain/$fp
            mkdir -p "$tc/bin"
            ver=0.12.4
            if [ ! -x "$tc/nvim/bin/nvim" ]; then
                echo "dev nvim: installing Neovim $ver in container" >&2
                b="https://github.com/neovim/neovim/releases/download/v$ver"
                curl -fsSL "$b/nvim-linux-x86_64.tar.gz" -o /tmp/nvim.tgz
                if curl -fsSL "$b/shasum.txt" -o /tmp/nvim.sha 2>/dev/null; then
                    want=$(grep nvim-linux-x86_64.tar.gz /tmp/nvim.sha | cut -d" " -f1)
                    got=$(sha256sum /tmp/nvim.tgz | cut -d" " -f1)
                    if [ -n "$want" ] && [ "$want" != "$got" ]; then echo "dev nvim: nvim checksum mismatch" >&2; exit 1; fi
                fi
                stage=$(mktemp -d "$tc/.nvim.XXXXXX")
                tar xzf /tmp/nvim.tgz -C "$stage" --strip-components=1
                if ! mv -T "$stage" "$tc/nvim" 2>/dev/null; then
                    rm -rf "$stage"
                    if [ ! -x "$tc/nvim/bin/nvim" ]; then
                        echo "dev nvim: could not install Neovim into the shared toolchain" >&2
                        exit 1
                    fi
                fi
            fi
            # A store from before the toolchain was shared holds a real
            # directory here; replace it with the link rather than nesting into
            # it. `rm -rf` on the link itself never touches the shared copy.
            if [ -d /nvimdata/nvim ] && [ ! -L /nvimdata/nvim ]; then rm -rf /nvimdata/nvim; fi
            ln -sfn "$tc/nvim" /nvimdata/nvim
            if ! command -v node >/dev/null 2>&1 && [ ! -x /nvimdata/node/bin/node ]; then
                echo "dev nvim: installing Node.js in container (for LSP servers)" >&2
                nver=22.11.0
                curl -fsSL "https://nodejs.org/dist/v$nver/node-v$nver-linux-x64.tar.gz" -o /tmp/node.tgz
                mkdir -p /nvimdata/node && tar xzf /tmp/node.tgz -C /nvimdata/node --strip-components=1
            fi
            # fd + ripgrep for the file/grep pickers and venv-selector (the slim
            # container bases usually ship neither).
            # One file at a time, each renamed over its final name, so a missing
            # rg is installed without re-staging a working fd.
            if [ ! -x "$tc/bin/fd" ]; then
                echo "dev nvim: installing fd in container (pickers)" >&2
                fdv=10.2.0
                curl -fsSL "https://github.com/sharkdp/fd/releases/download/v$fdv/fd-v$fdv-x86_64-unknown-linux-gnu.tar.gz" | tar xz -C /tmp \
                    && cp "/tmp/fd-v$fdv-x86_64-unknown-linux-gnu/fd" "$tc/bin/.fd.$$" \
                    && mv -f "$tc/bin/.fd.$$" "$tc/bin/fd"
            fi
            if [ ! -x "$tc/bin/rg" ]; then
                echo "dev nvim: installing ripgrep in container (pickers)" >&2
                rgv=14.1.1
                curl -fsSL "https://github.com/BurntSushi/ripgrep/releases/download/$rgv/ripgrep-$rgv-x86_64-unknown-linux-musl.tar.gz" | tar xz -C /tmp \
                    && cp "/tmp/ripgrep-$rgv-x86_64-unknown-linux-musl/rg" "$tc/bin/.rg.$$" \
                    && mv -f "$tc/bin/.rg.$$" "$tc/bin/rg"
            fi
            if [ -d /nvimdata/bin ] && [ ! -L /nvimdata/bin ]; then rm -rf /nvimdata/bin; fi
            ln -sfn "$tc/bin" /nvimdata/bin
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
            if [ -d /lazygitconf-src ]; then
                rm -rf /nvimdata/config/lazygit
                cp -a /lazygitconf-src /nvimdata/config/lazygit
            fi
        '
        # The mount probe runs first, inside the same script, and answers 97 --
        # a status no tool in the body returns, so a `curl`/`tar`/`grep` failure
        # under `set -e` is never mistaken for "recreate me". `set -e` starts
        # after it, since a failing probe is an answer rather than an error.
        # Prepended by literal concatenation, NOT `(string join ...)`: fish
        # splits command substitution on newlines, which would turn $boot into a
        # list and flatten the whole script onto one line when it is quoted.
        set -l boot "$ready || exit 97
$boot"

        devcontainer exec --workspace-folder "$root" $dcflags bash -c "$boot"
        set -l provisioned $status
        if test $provisioned -eq 97
            echo "dev nvim: container is missing a mount; recreating..." >&2
            set -l relog (mktemp)
            if not devcontainer up --workspace-folder "$root" $dcflags $mounts \
                    --remove-existing-container >$relog 2>&1
                echo "dev nvim: recreating the container failed:" >&2
                tail -n 20 $relog >&2
                rm -f $relog
                return 1
            end
            rm -f $relog
            if not devcontainer exec --workspace-folder "$root" $dcflags bash -c "$boot"
                echo "dev nvim: provisioning failed" >&2
                return 1
            end
        else if test $provisioned -ne 0
            echo "dev nvim: provisioning failed" >&2
            return 1
        end

        # Detect the project's languages (host-side, from the bind-mounted
        # source) so `dev nvim` scopes the in-container LSP/parser/tool install to
        # what the project actually uses, not every language. Consumed by
        # lua/config/lazy.lua (NVIM_MASON_LANGS gates which lang extras import).
        set -l mlangs
        test -f "$root/composer.json"; and set -a mlangs php twig
        if test -f "$root/package.json"
            set -a mlangs ts
            grep -qE '"tailwindcss"|"@tailwindcss/' "$root/package.json" 2>/dev/null; and set -a mlangs tailwind
            grep -q '"astro"' "$root/package.json" 2>/dev/null; and set -a mlangs astro
        end
        # Python: manifests OR any top-level *.py (covers pipenv/conda/pyenv and
        # bare-script repos with no manifest).
        set -l pyhit (find "$root" -maxdepth 1 \( -iname 'pyproject.toml' -o -iname 'requirements*.txt' -o -iname 'setup.py' -o -iname 'setup.cfg' -o -iname 'Pipfile' -o -iname 'environment.yml' -o -iname '.python-version' -o -iname '*.py' \) -print -quit 2>/dev/null)
        test -n "$pyhit"; and set -a mlangs python
        # Docker: any Dockerfile/Containerfile or compose file, including the
        # common docker-compose.dev.yml / compose.yaml / Dockerfile.<stage> variants.
        set -l dockerhit (find "$root" -maxdepth 1 \( -iname 'Dockerfile*' -o -iname 'Containerfile*' -o -iname 'compose*.y*ml' -o -iname 'docker-compose*.y*ml' \) -print -quit 2>/dev/null)
        test -n "$dockerhit"; and set -a mlangs docker

        # Inject the intelephense premium licence (if configured) so the
        # in-container PHP LSP unlocks premium features. Machine-local file, set
        # with `just intelephense-licence`; never seeded into the image.
        set -l iph_env
        set -l iph_file "$HOME/.config/intelephense/licence.key"
        if test -r "$iph_file"
            set iph_env --remote-env "INTELEPHENSE_LICENCE_KEY="(string trim <"$iph_file")
        end

        # Committing from the in-container lazygit needs an identity. Forward the
        # host's instead of mounting ~/.config/git/config, which sets `pager =
        # delta` and a gh credential helper that do not exist in the container.
        set -l git_env
        set -l git_name (git config --get user.name)
        set -l git_email (git config --get user.email)
        if test -n "$git_name" -a -n "$git_email"
            set git_env \
                --remote-env "GIT_AUTHOR_NAME=$git_name" \
                --remote-env "GIT_AUTHOR_EMAIL=$git_email" \
                --remote-env "GIT_COMMITTER_NAME=$git_name" \
                --remote-env "GIT_COMMITTER_EMAIL=$git_email"
        end

        devcontainer exec --workspace-folder "$root" $dcflags \
            $iph_env \
            $git_env \
            --remote-env "NVIM_MASON_LANGS=$mlangs" \
            --remote-env XDG_CONFIG_HOME=/nvimdata/config \
            --remote-env XDG_DATA_HOME=/nvimdata/data \
            --remote-env XDG_STATE_HOME=/nvimdata/state \
            --remote-env XDG_CACHE_HOME=/nvimdata/cache \
            --remote-env NVIM_IN_CONTAINER=1 \
            --remote-env COLORTERM=truecolor \
            --remote-env TERM=xterm-256color \
            bash -c 'export PATH=/nvimdata/node/bin:/nvimdata/bin:$PATH; cd "$1" || exit; shift; exec /nvimdata/nvim/bin/nvim "$@"' -- "$rel" $argv[2..-1]
    else if test (count $argv) -eq 0
        devcontainer exec --workspace-folder "$root" $dcflags bash -c 'cd "$1" || exit; exec bash' -- "$rel"
    else
        devcontainer exec --workspace-folder "$root" $dcflags bash -c 'cd "$1" || exit; shift; exec "$@"' -- "$rel" $argv
    end
end
