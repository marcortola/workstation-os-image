function dev --description "Run a command in the nearest Dev Container (no args = shell), starting it on demand"
    # realpath resolves symlinks (e.g. /home -> /var/home) so every path below
    # is compared against the same physical prefix.
    set -l start (realpath .)

    # Boundary for the upward search: never look above the repo root.
    set -l gitroot (git -C "$start" rev-parse --show-toplevel 2>/dev/null)
    if test -n "$gitroot"
        set gitroot (realpath "$gitroot")
    end

    # Walk from the current directory up to the repo root and pick the FIRST
    # (nearest) directory that defines a Dev Container.
    set -l root
    set -l dir $start
    while true
        if test -f "$dir/.devcontainer/devcontainer.json"; or test -f "$dir/.devcontainer.json"
            set root $dir
            break
        end
        test "$dir" = "$gitroot"; and break   # checked the repo root, stop
        set -l parent (dirname "$dir")
        test "$parent" = "$dir"; and break     # hit the filesystem root (no repo)
        set dir $parent
    end

    if test -z "$root"
        echo "dev: no .devcontainer found from (pwd) up to the repo root" >&2
        return 1
    end

    # devcontainer exec always starts in the workspace (root) folder, so mirror
    # the caller's subdirectory inside the container with a relative cd.
    set -l rel (realpath --relative-to="$root" .)

    # Idempotent: builds/starts on first call, fast no-op once running.
    if not devcontainer up --workspace-folder "$root" >/dev/null 2>&1
        echo "dev: failed to start devcontainer — retry verbosely with:" >&2
        echo "     devcontainer up --workspace-folder $root" >&2
        return 1
    end

    if test (count $argv) -eq 0
        devcontainer exec --workspace-folder "$root" bash -c 'cd "$1"; exec bash' -- "$rel"
    else
        devcontainer exec --workspace-folder "$root" bash -c 'cd "$1" || exit; shift; exec "$@"' -- "$rel" $argv
    end
end
