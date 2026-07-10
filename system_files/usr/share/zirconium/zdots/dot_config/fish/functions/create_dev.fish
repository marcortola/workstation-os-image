function dev --description "Choose a project and switch to it"
    set -l project (~/.local/bin/workstation-dev)
    or return

    if test -n "$project"
        cd "$project"
    end
end
