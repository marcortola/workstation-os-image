set -gx SHELL /usr/bin/fish
set -gx ZELLIJ_AUTO_EXIT true

# Homebrew
if test -d /home/linuxbrew/.linuxbrew
    eval (/home/linuxbrew/.linuxbrew/bin/brew shellenv)
end

if status is-interactive; and command -q zellij
    eval (zellij setup --generate-auto-start fish | string collect)
end

if status is-interactive; and command -q starship
    set -gx STARSHIP_CONFIG ~/.config/starship.toml
    starship init fish | source
end

# Local binaries
fish_add_path ~/.local/bin

# Editor
set -gx EDITOR nvim
set -gx VISUAL nvim
