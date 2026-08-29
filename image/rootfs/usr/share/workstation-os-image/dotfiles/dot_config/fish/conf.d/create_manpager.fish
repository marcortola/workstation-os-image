if command -q bat
    set -gx MANPAGER 'sh -c "col -bx | bat -l man -p"'
    set -gx MANROFFOPT -c
end
