# Seed a brand-new per-project store from one already built on the same base
# image, by HARDLINK. Every checkout is its own store -- the key is a hash of the
# checkout path, so a linked worktree IS its own root -- and each new branch
# therefore re-downloads its Mason packages and recompiles its treesitter parsers
# from scratch. Measured on the surviving worktree stores: 150-359 MB and 3-16
# Mason packages each, every byte of which already exists on this disk.
#
# Hardlinks rather than copies, and only into an EMPTY store. That combination is
# what makes it safe:
#   - the target has never been opened, so there is no second writer to race;
#   - mason promotes a package by renaming its staging directory into packages/
#     (mason-core/installer/context/init.lua:95 `fs.sync.rename(cwd, install_path)`),
#     so anything already in packages/ is complete even while the donor installs
#     something else right now;
#   - nvim-treesitter renames a freshly built parser into place, and renames an
#     in-use one OUT of the way rather than overwriting it
#     (nvim-treesitter/install.lua:290 and :328), so a shared inode is replaced,
#     never mutated.
# Neither tool edits an installed file in place, which is the single property
# that would make sharing an inode wrong.
#
# staging/ is deliberately dropped: it holds mason's lockfiles
# (InstallLocation:lockfile -> staging/<name>.lock), and inheriting one would
# make a fresh store believe an install is already running in another process.
function __dev_seed_store --argument-names store
    set -l fp (cat "$store/.builtfor" 2>/dev/null)
    test -n "$fp"; or return 1
    # Seed only what is untouched; never merge into a populated store.
    test -e "$store/data/nvim/mason"; and return 1
    test -e "$store/data/nvim/site"; and return 1

    set -l root (path dirname "$store")
    set -l best
    set -l best_n 0
    # `ls` rather than a glob: an unmatched wildcard is a hard error in fish, and
    # this runs on a machine that may legitimately have no other store yet.
    for name in (ls -1 "$root" 2>/dev/null)
        set -l cand "$root/$name"
        test "$cand" = "$store"; and continue
        test -d "$cand/data/nvim/mason/packages"; or continue
        # Same base image, by the fingerprint the provisioner already computes.
        # A store with no .builtfor (toolchain/, a stray directory) never matches.
        set -l cand_fp (cat "$cand/.builtfor" 2>/dev/null)
        test "$cand_fp" = "$fp"; or continue
        set -l n (ls -1 "$cand/data/nvim/mason/packages" 2>/dev/null | wc -l | string trim)
        if test "$n" -gt "$best_n"
            set best "$cand"
            set best_n "$n"
        end
    end
    test -n "$best"; or return 1

    mkdir -p "$store/data/nvim"
    # -a keeps symlinks as symlinks -- mason's bin/ entries are RELATIVE
    # (`../packages/...`), so they stay correct in the new store -- and -l
    # hardlinks the regular files. Same filesystem by construction: donor and
    # target are siblings under the same store root.
    if not cp -al "$best/data/nvim/mason" "$store/data/nvim/mason" 2>/dev/null
        rm -rf "$store/data/nvim/mason"
        return 1
    end
    rm -rf "$store/data/nvim/mason/staging"
    mkdir -p "$store/data/nvim/mason/staging"
    if test -d "$best/data/nvim/site"
        cp -al "$best/data/nvim/site" "$store/data/nvim/site" 2>/dev/null
        or rm -rf "$store/data/nvim/site"
    end
    echo "dev nvim: seeded store from "(path basename "$best")" -- $best_n mason packages, hardlinked" >&2
end

# Resolve the already-running Dev Container for a workspace root, printing its
# id, the workspace path inside it, and the user to exec as -- or nothing at all
# when any of the three is unavailable, which is the signal to use the CLI.
#
# Each value is read back off the container the devcontainer CLI itself built,
# never recomputed: the container by the CLI's own `devcontainer.local_folder`
# label, the workspace path from the bind mount whose source is $root (which is
# what makes a linked worktree's rewritten /workspaces/<repo>__worktrees/<slug>
# come out right), and remoteUser from the `devcontainer.metadata` label --
# `.Config.User` is `root` on every container here, so reading that instead
# would exec as root and leave root-owned files in the store and the checkout.
function __dev_fast_probe --argument-names root
    set -q DEV_NO_FAST_EXEC; and return 1
    type -q docker; or return 1
    type -q jq; or return 1
    set -l cid (docker ps -q \
        --filter "label=devcontainer.local_folder=$root" 2>/dev/null | head -n1)
    test -n "$cid"; or return 1
    set -l ws (docker inspect \
        -f "{{range .Mounts}}{{if eq .Source \"$root\"}}{{.Destination}}{{end}}{{end}}" \
        "$cid" 2>/dev/null)
    set -l user (docker inspect \
        -f '{{index .Config.Labels "devcontainer.metadata"}}' "$cid" 2>/dev/null \
        | jq -r '[.[]?|.remoteUser//empty]|last // empty' 2>/dev/null)
    # All three or none. A container missing the workspace mount or the metadata
    # label is not one `devcontainer exec` would have driven the same way.
    test -n "$ws" -a -n "$user"; or return 1
    printf '%s\n%s\n%s\n' "$cid" "$ws" "$user"
end

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
    # a per-project store that holds the Mason servers and compiled treesitter
    # parsers, persisted across rebuilds. The nvim binary, fd, rg and Node are
    # NOT per project -- they live once per base-image fingerprint under
    # toolchain/ and are linked into the store. Host and container both run as uid 1000, so the store is
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

    # Fast path for a container that is already running. `devcontainer exec`
    # measures 514-610 ms against an up container, versus 39-50 ms for the
    # `docker exec` it ultimately performs -- and `dev nvim` pays it twice, for
    # the provisioning script and for the launch. The difference is Node process
    # start plus a full devcontainer.json and features resolution, recomputed on
    # every call and entirely wasted once the container exists.
    #
    # Nothing below re-derives what the CLI knows. Each value is read back off
    # the container the CLI itself built:
    #   - the container, by the CLI's own `devcontainer.local_folder` label, so
    #     it is exactly the one `exec` would have chosen;
    #   - the workspace path, from the bind mount whose source is $root. That is
    #     what makes a linked worktree's rewritten
    #     /workspaces/<repo>__worktrees/<slug> come out right instead of being
    #     reconstructed by hand -- reconstructing it is precisely what lost in
    #     docs/design-records/worktree-dev-containers.md;
    #   - remoteUser, from the `devcontainer.metadata` label. Not optional:
    #     `.Config.User` is `root` on every container here while remoteUser is
    #     `vscode` or `node`, so a `docker exec` without `-u` would run as root
    #     and leave root-owned files in the store and the checkout -- the mess
    #     the worktree-removal tail exists to clean up with `sudo rm -rf`.
    # Missing any of the three, or DEV_NO_FAST_EXEC set, and the CLI runs.
    #
    # `bash -lc`, not `bash -c`: the CLI's default userEnvProbe is
    # loginInteractiveShell, so the exec'd command expects a login shell's PATH.
    # The provisioning script below decides whether to download a 181 MB Node
    # into the store from `command -v node`, so losing a profile-managed PATH
    # there is not cosmetic -- it silently re-downloads Node for every project.
    set -l fast_cid
    set -l fast_ws
    set -l fast_user
    set -l probe (__dev_fast_probe "$root")
    if test (count $probe) -eq 3
        set fast_cid $probe[1]
        set fast_ws $probe[2]
        set fast_user $probe[3]
    end

    # `devcontainer up` is unconditional no longer. It measures 375-404 ms warm
    # -- against ~50 ms for the docker exec that follows it -- so on a project
    # whose definition has not changed it is most of the launch. The CLI offers
    # no cheaper mode: `--expect-existing-container` only changes what happens
    # when the container is absent, and `--skip-post-create` measured inside the
    # noise (384/372/369 ms against 498/394/377 ms) while silently dropping
    # postStartCommand and postAttachCommand.
    #
    # The stamp is a CONTENT hash, not an mtime. git rewrites mtimes on
    # checkout, so mtime does not track content: growwer's own
    # .devcontainer/Dockerfile reads 2026-09-14 20:05 against a last commit of
    # 2026-09-11 on a clean tree. An mtime test would call every project changed
    # and never skip anything. The stamp carries the container id too, so a
    # container recreated behind our back costs one `up` and no more.
    #
    # It fails CLOSED by construction: no hash, no stamp, no running container,
    # a mismatch, or DEV_FORCE_UP set, and `up` runs.
    #
    # What it cannot see: a Dockerfile or compose file referenced from OUTSIDE
    # the Dev Container definition, and an upstream feature that has published a
    # new version since. DEV_FORCE_UP=1 is the escape hatch for both.
    set -l cfg_files
    test -f "$root/.devcontainer.json"; and set -a cfg_files "$root/.devcontainer.json"
    test -d "$root/.devcontainer"; and set -a cfg_files \
        (find "$root/.devcontainer" -type f 2>/dev/null | sort)
    set -l cfg_hash
    if test (count $cfg_files) -gt 0
        # Paths as well as contents, so adding or removing a file counts.
        set cfg_hash (begin
            for cfg in $cfg_files
                string replace "$root/" "" -- "$cfg"
                cat "$cfg"
            end
        end | sha256sum | cut -c1-16)
    end
    set -l cfg_stamp "$store/.upconfig"

    set -l skip_up 0
    if test -n "$fast_cid" -a -n "$cfg_hash"; and not set -q DEV_FORCE_UP
        # Read into a variable first: an absent stamp makes the command
        # substitution expand to nothing, and `test a = ` is a usage error, not
        # a false -- which fish reports as a stack trace on every cold run.
        set -l stamped (cat "$cfg_stamp" 2>/dev/null)
        test "$cfg_hash $fast_cid" = "$stamped"; and set skip_up 1
    end

    if test $skip_up -eq 0
        # Idempotent: builds/starts on first call, fast no-op once running. The
        # output is captured rather than discarded so a failure can report the
        # CLI's own message: a rejected flag or a broken build is otherwise
        # invisible.
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

        # `up` may have created or replaced the container, so the values probed
        # before it can be stale. Re-probe, then stamp what this configuration
        # resolved to so the next launch can skip straight past the CLI.
        set probe (__dev_fast_probe "$root")
        set fast_cid ""
        set fast_ws ""
        set fast_user ""
        if test (count $probe) -eq 3
            set fast_cid $probe[1]
            set fast_ws $probe[2]
            set fast_user $probe[3]
            test -n "$cfg_hash"; and echo "$cfg_hash $fast_cid" >"$cfg_stamp"
        end
    end

    # docker refuses -t without a terminal, which `dev <cmd> | cat` does not have.
    set -l dtty -i
    isatty stdin; and isatty stdout; and set dtty -it

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
            # Node belongs in the SHARED toolchain for exactly the reason nvim
            # does: it is one 181,811,945 B tree, byte-identical wherever it
            # lands. Five stores were each carrying their own copy -- 909 MB of
            # pure duplication -- and every new worktree paid the 181 MB
            # download again. The record measured "no store has a node/
            # directory" and that has since expired. Staged and renamed like the
            # rest, so two cold launches at once yield one good copy and one
            # discarded download rather than a half-extracted interpreter.
            if ! command -v node >/dev/null 2>&1 && [ ! -x "$tc/node/bin/node" ]; then
                echo "dev nvim: installing Node.js in container (for LSP servers)" >&2
                nver=22.11.0
                curl -fsSL "https://nodejs.org/dist/v$nver/node-v$nver-linux-x64.tar.gz" -o /tmp/node.tgz
                stage=$(mktemp -d "$tc/.node.XXXXXX")
                tar xzf /tmp/node.tgz -C "$stage" --strip-components=1
                if ! mv -T "$stage" "$tc/node" 2>/dev/null; then
                    rm -rf "$stage"
                    if [ ! -x "$tc/node/bin/node" ]; then
                        echo "dev nvim: could not install Node into the shared toolchain" >&2
                        exit 1
                    fi
                fi
            fi
            # A store from before Node was shared holds a real directory here;
            # replace it with the link rather than nesting into it. `rm -rf` on
            # the link itself never touches the shared copy. The link is only
            # made when a shared Node exists -- where the base image ships its
            # own, nothing is installed and /nvimdata/node stays absent, exactly
            # as before (a missing PATH entry is inert).
            if [ -d /nvimdata/node ] && [ ! -L /nvimdata/node ]; then rm -rf /nvimdata/node; fi
            [ -d "$tc/node" ] && ln -sfn "$tc/node" /nvimdata/node
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

        set -l provisioned
        if test -n "$fast_cid"
            docker exec -u "$fast_user" -w "$fast_ws" "$fast_cid" bash -lc "$boot"
            set provisioned $status
        else
            devcontainer exec --workspace-folder "$root" $dcflags bash -c "$boot"
            set provisioned $status
        end
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
            # --remove-existing-container built a NEW container, so the id, the
            # mount set and the user probed above all belong to one that no
            # longer exists. Drop back to the CLI for the rest of this launch
            # rather than re-probing a container this call has just created.
            set fast_cid
            if not devcontainer exec --workspace-folder "$root" $dcflags bash -c "$boot"
                echo "dev nvim: provisioning failed" >&2
                return 1
            end
        else if test $provisioned -ne 0
            echo "dev nvim: provisioning failed" >&2
            return 1
        end

        # Host-side, and only now: the base-image fingerprint the seed keys on is
        # written by the provisioning script above, and the store is mounted at
        # /nvimdata inside the container where no donor is visible. A no-op for
        # every store that already has one.
        __dev_seed_store "$store"

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
        # Collected as plain KEY=VALUE and spelled two ways below, because the
        # CLI takes `--remote-env K=V` and docker takes `-e K=V`. One list, so
        # the two paths cannot drift in what they forward.
        set -l envs
        set -l iph_file "$HOME/.config/intelephense/licence.key"
        if test -r "$iph_file"
            set -a envs "INTELEPHENSE_LICENCE_KEY="(string trim <"$iph_file")
        end

        # Committing from the in-container lazygit needs an identity. Forward the
        # host's instead of mounting ~/.config/git/config, which sets `pager =
        # delta` and a gh credential helper that do not exist in the container.
        set -l git_name (git config --get user.name)
        set -l git_email (git config --get user.email)
        if test -n "$git_name" -a -n "$git_email"
            set -a envs \
                "GIT_AUTHOR_NAME=$git_name" \
                "GIT_AUTHOR_EMAIL=$git_email" \
                "GIT_COMMITTER_NAME=$git_name" \
                "GIT_COMMITTER_EMAIL=$git_email"
        end

        set -a envs \
            "NVIM_MASON_LANGS=$mlangs" \
            XDG_CONFIG_HOME=/nvimdata/config \
            XDG_DATA_HOME=/nvimdata/data \
            XDG_STATE_HOME=/nvimdata/state \
            XDG_CACHE_HOME=/nvimdata/cache \
            NVIM_IN_CONTAINER=1 \
            COLORTERM=truecolor \
            TERM=xterm-256color
        set -l remote_env
        set -l docker_env
        for pair in $envs
            set -a remote_env --remote-env "$pair"
            set -a docker_env -e "$pair"
        end

        # One command string for both paths: `--` is $0 and $rel is $1, so the
        # relative cd is identical whichever launcher runs it.
        set -l nvim_cmd 'export PATH=/nvimdata/node/bin:/nvimdata/bin:$PATH; cd "$1" || exit; shift; exec /nvimdata/nvim/bin/nvim "$@"'
        if test -n "$fast_cid"
            docker exec $dtty -u "$fast_user" -w "$fast_ws" $docker_env "$fast_cid" \
                bash -lc "$nvim_cmd" -- "$rel" $argv[2..-1]
        else
            devcontainer exec --workspace-folder "$root" $dcflags $remote_env \
                bash -c "$nvim_cmd" -- "$rel" $argv[2..-1]
        end
    else if test (count $argv) -eq 0
        if test -n "$fast_cid"
            docker exec $dtty -u "$fast_user" -w "$fast_ws" "$fast_cid" \
                bash -lc 'cd "$1" || exit; exec bash' -- "$rel"
        else
            devcontainer exec --workspace-folder "$root" $dcflags bash -c 'cd "$1" || exit; exec bash' -- "$rel"
        end
    else
        if test -n "$fast_cid"
            docker exec $dtty -u "$fast_user" -w "$fast_ws" "$fast_cid" \
                bash -lc 'cd "$1" || exit; shift; exec "$@"' -- "$rel" $argv
        else
            devcontainer exec --workspace-folder "$root" $dcflags bash -c 'cd "$1" || exit; shift; exec "$@"' -- "$rel" $argv
        end
    end
end
