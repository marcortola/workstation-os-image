function nv --description "Neovim in the project's Dev Container (`dev nvim`), or host Neovim if there is none"
    # Mirror `dev`'s search: the nearest .devcontainer from the current directory
    # up to the repo root. If one exists, run Neovim inside it (so LSP/DAP see the
    # project's real deps); otherwise fall back to host Neovim.
    set -l start (realpath .)
    set -l gitroot (git -C "$start" rev-parse --show-toplevel 2>/dev/null)
    test -n "$gitroot"; and set gitroot (realpath "$gitroot")
    set -l stopdir $gitroot
    test -z "$stopdir"; and set stopdir $start

    set -l dir $start
    while true
        if test -f "$dir/.devcontainer/devcontainer.json"; or test -f "$dir/.devcontainer.json"
            dev nvim $argv
            return
        end
        test "$dir" = "$stopdir"; and break
        set -l parent (dirname "$dir")
        test "$parent" = "$dir"; and break
        set dir $parent
    end

    nvim $argv
end
