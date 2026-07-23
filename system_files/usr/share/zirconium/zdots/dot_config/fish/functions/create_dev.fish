function dev --description "Run a command in this project's Dev Container (no args = shell), starting it on demand"
    set -l root (git rev-parse --show-toplevel 2>/dev/null; or pwd)

    if not test -f "$root/.devcontainer/devcontainer.json"; and not test -f "$root/.devcontainer.json"
        echo "dev: no .devcontainer found under $root" >&2
        return 1
    end

    # devcontainer exec always starts in the workspace (repo) root, so mirror the
    # caller's subdirectory inside the container with a relative cd.
    set -l cwd (pwd)
    set -l rel .
    if test "$cwd" != "$root"
        set rel (string replace -- "$root/" "" "$cwd")
    end

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
