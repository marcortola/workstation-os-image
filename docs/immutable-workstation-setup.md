# Immutable workstation setup

System: Fedora bootc (Zirconium), Niri, and DMS.

The base image is immutable. The custom bootc image is the reproducible
workstation definition: it contains host-integrated packages, extends
Zirconium's chezmoi source with create-only personal defaults, and restores
user tools and fonts on first login. Existing home-directory files remain
authoritative and are never reset by an image update.

## Homebrew and the user package manifest

The image's first-login bootstrap installs Homebrew in its standard Linux
prefix and applies the embedded `~/dotfiles/Brewfile`. These commands remain
the manual recovery procedure:

```bash
/bin/bash -c "$(curl -fsSL \
  https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
```

Fish loads Homebrew from `~/.config/fish/config.fish`:

```fish
if test -d /home/linuxbrew/.linuxbrew
    eval (/home/linuxbrew/.linuxbrew/bin/brew shellenv)
end

fish_add_path ~/.local/bin
set -gx EDITOR nvim
set -gx VISUAL nvim
```

Keep the reproducible package list at `~/dotfiles/Brewfile`. Generate or
refresh it after deliberate package changes, review the diff, and restore it
on another installation with:

```bash
brew bundle dump --file ~/dotfiles/Brewfile --force
brew bundle install --file ~/dotfiles/Brewfile
```

The workstation's Homebrew tools include Bat, Devcontainer, direnv,
dysk, eza, fd, GitHub/GitLab CLIs, HTTPie, jq, Lazydocker,
Lazygit, Neovim, ripgrep, ShellCheck, Starship, tealdeer, tmux, trash-cli,
Tree-sitter, watch, yq, Zellij, and Zoxide. Codex and Claude Code are Homebrew
casks. Add these direct dependencies to the Brewfile rather than relying on a
package that happened to pull them in transitively.

Zirconium supplies btop, Chezmoi, Git, fzf, and Just in the OS image; do not
duplicate those packages through Homebrew.

## Custom workstation OS image

Host-integrated packages and configuration are built into the public bootc
image maintained at `marcortola/workstation-os-image`:

```text
ghcr.io/marcortola/workstation-os-image:latest
```

The image contains Fish, keyd, Docker Engine, containerd, Buildx, and Compose.
It enables their systemd services and provides `/etc/docker/daemon.json` and
`/etc/keyd/default.conf`. On a fresh machine, switch to it once; routine updates
then use `bootc upgrade` rather than rpm-ostree package layering:

```bash
skopeo inspect docker://ghcr.io/marcortola/workstation-os-image:latest
sudo bootc switch ghcr.io/marcortola/workstation-os-image:latest
sudo bootc status --verbose
systemctl reboot
```

On an already-tracking workstation, use `sudo bootc upgrade` instead. Before
rebooting, verify that `sudo bootc status --verbose` reports the intended image
digest under `staged`.

Docker remains rootful. Before graphical login, the workstation image adds
interactive local users with homes under `/home` or `/var/home` to the
root-equivalent `docker` group, so Docker commands work without `sudo` without
hardcoding a username.

```bash
docker run --rm hello-world
```

After reboot and graphical login, verify that the deployment contains the
requested packages and that host services, Docker access, user provisioning,
and effective desktop configuration are ready:

```bash
rpm -q containerd.io docker-buildx-plugin docker-ce docker-ce-cli \
  docker-compose-plugin fish keyd
test -x /usr/bin/fish
systemctl is-enabled containerd.service docker.service keyd.service
systemctl is-active containerd.service docker.service keyd.service
systemctl show workstation-docker-users.service --property=Result
test -S /run/docker.sock
id -nG | tr ' ' '\n' | grep -Fx docker
docker run --rm hello-world
sudo keyd check /etc/keyd/default.conf

systemctl --user is-enabled workstation-bootstrap.service \
  workstation-microsoft-fonts.service
systemctl --user show workstation-bootstrap.service \
  workstation-microsoft-fonts.service --property=Result
test -f ~/.local/state/workstation-os-image/bootstrap-complete
test -f ~/.local/share/fonts/.workstation-fonts-installed
test -x /home/linuxbrew/.linuxbrew/bin/brew
test -L ~/.local/bin/jetbrains-toolbox
test -f ~/.config/foot/workstation.ini
chezmoi managed -S /usr/share/zirconium/zdots | \
  grep -E '^(\.config/niri/local\.kdl|dotfiles/Brewfile)$'
foot --check-config -c ~/.config/foot/foot.ini
niri validate -c ~/.config/niri/config.kdl
```

The user provisioning services are `oneshot` units and normally become
inactive after completion. Check for `Result=success` and the marker files; if
either failed, inspect its user journal before retrying it.

Docker's image-provided `json-file` policy bounds logs so long-running
containers cannot consume the host filesystem:

```json
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "5"
  }
}
```

Validate the effective configuration after boot:

```bash
dockerd --validate --config-file=/etc/docker/daemon.json
docker info --format '{{.LoggingDriver}}'
```

Do not install a second copy of Fish through Homebrew; Foot intentionally uses
`/usr/bin/fish` from the workstation image. User defaults are carried in the
image as create-only Zirconium chezmoi entries. They seed a new account but
remain user-owned because bootc preserves `/var/home` and chezmoi does not
overwrite existing targets.

## Fonts

### Effective defaults

- Monospace and terminal: FiraCode Nerd Font Mono, 12 pt
- Sans-serif and applications: Noto Sans, 11 pt
- Serif: Noto Serif
- Emoji: Noto Color Emoji

The defaults are configured in:

- `~/.config/fontconfig/fonts.conf`
- `~/.config/gtk-3.0/settings.ini`
- `~/.config/gtk-4.0/settings.ini`
- `~/.config/DankMaterialShell/settings.json`
- `~/.config/foot/foot.ini`

Noto Sans, Noto Serif, Noto Color Emoji, FiraCode Nerd Font, and JetBrains
Mono Nerd Font are supplied by the image or existing user-local installation.
The workstation image supplies and globally enables a first-login Microsoft
font installer. The owner's standing EULA acceptance is encoded in the user
service; proprietary font binaries are downloaded directly from their original
distributors into persistent user storage rather than redistributed in the
public image. Run or retry it immediately with:

```bash
systemctl --user start workstation-microsoft-fonts.service
```

The enabled first-login font service installs both the open fonts below and
the Microsoft set. The following documents its underlying recovery procedure.

### Install helper and download fonts

```bash
brew install cabextract

curl -fL --retry 3 -o /tmp/CascadiaMono.tar.xz \
  https://github.com/ryanoasis/nerd-fonts/releases/latest/download/CascadiaMono.tar.xz
curl -fL --retry 3 -o /tmp/ia-fonts.zip \
  https://github.com/iaolo/iA-Fonts/archive/refs/heads/master.zip
curl -fL --retry 3 -o /tmp/font-awesome.zip \
  https://github.com/FortAwesome/Font-Awesome/archive/refs/heads/6.x.zip
curl -fL --retry 3 -o /tmp/msttcore-fonts-installer.rpm \
  https://downloads.sourceforge.net/project/mscorefonts2/rpms/msttcore-fonts-installer-2.6-1.noarch.rpm
```

### Install open fonts under the home directory

```bash
mkdir -p ~/.local/share/fonts/{CaskaydiaMono,iAWriterMono,FontAwesome,Microsoft}

tar -xJf /tmp/CascadiaMono.tar.xz \
  -C ~/.local/share/fonts/CaskaydiaMono
unzip -j -o /tmp/ia-fonts.zip \
  '*/iA Writer Mono/Static/*.ttf' \
  -d ~/.local/share/fonts/iAWriterMono
unzip -j -o /tmp/font-awesome.zip \
  '*/otfs/*.otf' \
  -d ~/.local/share/fonts/FontAwesome
```

### Install Microsoft core and Vista fonts

The small RPM is unpacked rather than installed, keeping the immutable image
unchanged. Its helper downloads the Microsoft cabinets, verifies them against
the bundled SHA-256 list, accepts the Microsoft font EULA through use, and
extracts Arial, Times New Roman, Verdana, Calibri, Cambria, Consolas, Candara,
Corbel, Constantia, and the other included families user-locally.

```bash
rm -rf /tmp/msttcore-extract
mkdir -p /tmp/msttcore-extract
cd /tmp/msttcore-extract
rpm2cpio /tmp/msttcore-fonts-installer.rpm | cpio -idm

./usr/lib/msttcore-fonts-installer/refresh-msttcore-fonts.sh \
  -F "$HOME/.local/share/fonts/Microsoft" \
  -S "$PWD/usr/lib/msttcore-fonts-installer/cabfiles.sha256sums" \
  -I "$HOME/.local/share/fonts/Microsoft/installed-list.txt" \
  -L "$HOME/.local/share/fonts/Microsoft"

# The helper's TTF filter skips regular Cambria, which is a TTC collection.
curl -fL --retry 3 -o /tmp/PowerPointViewer.exe \
  https://downloads.sourceforge.net/project/mscorefonts2/cabs/PowerPointViewer.exe
rm -rf /tmp/ppviewer-extract
mkdir -p /tmp/ppviewer-extract
cabextract -q -d /tmp/ppviewer-extract -F 'ppviewer.cab' \
  /tmp/PowerPointViewer.exe
cabextract -q --lowercase -F 'cambria.ttc' \
  -d "$HOME/.local/share/fonts/Microsoft" \
  /tmp/ppviewer-extract/ppviewer.cab

fc-cache -f "$HOME/.local/share/fonts"
```

Warnings about `mkfontscale`, `mkfontdir`, `xset`, or writing under
`/etc/fonts` can be ignored here: those are legacy X11/system-wide integration
steps. The final user-level `fc-cache` command is the relevant Wayland setup.

### Verification

```bash
fc-match monospace
fc-match sans-serif
fc-match serif
fc-match emoji
fc-match Arial
fc-match 'Times New Roman'
fc-match Verdana
fc-match Calibri
fc-match Cambria
fc-match Consolas
fc-match 'CaskaydiaMono Nerd Font Mono'
fc-match 'iA Writer Mono S'
fc-match 'Font Awesome 6 Free'
```

Log out and back in after changing shell/application fonts so every process
reloads Fontconfig and GTK settings.

## Copilot key: map to Right Ctrl

`keyd` performs this remapping below the Wayland compositor, so no Niri or
DMS configuration is required. The configuration lives in `/etc`, which is
persistent machine state and survives normal bootc image updates.

## Configuration installed

```ini
[ids]
*

[main]
# Remap the Copilot key chord to Right Ctrl.
leftshift+leftmeta+f23 = rightcontrol
```

## Installation commands

```bash
sudo install -d -m 0755 /etc/keyd
sudo install -m 0644 keyd-default.conf /etc/keyd/default.conf
sudo keyd check /etc/keyd/default.conf
sudo systemctl enable --now keyd.service
sudo keyd reload
```

## Omarchy-style Starship prompt for Fish

Fish is provided by the workstation OS image. Foot launches it with
`shell=/usr/bin/fish` in `~/.config/foot/foot.ini`.

The account login shell remains `/bin/bash`, so the terminal-to-multiplexer
handoff must not rely on the inherited `$SHELL`. Make the Fish/Zellij chain
explicit in three places:

```ini
# ~/.config/foot/foot.ini
[main]
shell=/usr/bin/fish
```

```fish
# At the start of ~/.config/fish/config.fish
set -gx SHELL /usr/bin/fish
set -gx ZELLIJ_AUTO_EXIT true

if test -d /home/linuxbrew/.linuxbrew
    eval (/home/linuxbrew/.linuxbrew/bin/brew shellenv)
end

if status is-interactive; and command -q zellij
    eval (zellij setup --generate-auto-start fish | string collect)
end
```

```kdl
// ~/.config/zellij/config.kdl
default_shell "/usr/bin/fish"
```

Without these settings, Foot or Zellij can open Bash after login. Bash then
shows Starship's default prompt and bypasses the Fish Zoxide/fzf integrations,
even though the Fish configuration itself is correct.

Install Starship through Homebrew so the immutable base image remains
unchanged:

```bash
brew install starship
```

Create `~/.config/starship.toml` based on Omarchy's upstream configuration,
with Fedora Atomic path normalization and a compact single-line layout:

```toml
add_newline = false
command_timeout = 200
format = "$directory$git_branch$git_status$character"

[character]
error_symbol = "[✗](bold cyan)"
success_symbol = "[❯](bold cyan)"

[directory]
truncation_length = 2
truncation_symbol = "…/"
repo_root_style = "bold cyan"
repo_root_format = "[$repo_root]($repo_root_style)[$path]($style)[$read_only]($read_only_style) "
substitutions = [{ from = "^/var/home/marc", to = "~", regex = true }]

[git_branch]
format = "[$branch]($style) "
style = "italic cyan"

[git_status]
format = '[$all_status]($style)'
style = "cyan"
ahead = "⇡${count} "
diverged = "⇕⇡${ahead_count}⇣${behind_count} "
behind = "⇣${count} "
conflicted = " "
up_to_date = " "
untracked = "? "
modified = " "
stashed = ""
staged = ""
renamed = ""
deleted = ""
```

Initialize Starship after the Homebrew environment block in
`~/.config/fish/config.fish`:

```fish
if status is-interactive; and command -q starship
    set -gx STARSHIP_CONFIG ~/.config/starship.toml
    starship init fish | source
end
```

Remove any existing `~/.config/fish/functions/fish_prompt.fish` override so it
does not compete with Starship. Validate the configuration and open a new Fish
shell:

```bash
starship prompt --path "$HOME" --logical-path "$HOME"
fish --no-execute ~/.config/fish/config.fish
```

This omits username and hostname, displays at most two directory components,
shows Git branch and status when applicable, and uses the terminal's cyan
palette entry. The explicit `STARSHIP_CONFIG` prevents another startup layer
from selecting Starship's default two-line prompt. `add_newline = false` keeps
prompts compact, and the directory substitution maps Fedora Atomic's physical
`/var/home/marc` path to the conventional `~`. These are workstation-specific
adaptations of [Omarchy's upstream Starship configuration](https://github.com/basecamp/omarchy/blob/dev/config/starship.toml).

Start a fresh Fish process after changing prompt initialization:

```fish
exec fish
```

At home, the prompt should render as `~ ❯` on one line. If Starship's default
two-line prompt appears instead, verify the active configuration:

```fish
echo $STARSHIP_CONFIG
starship prompt --path $PWD --logical-path $PWD
```

The first command should print `/home/marc/.config/starship.toml`.

## Tokyo Night theme for Foot and Zellij

These are user-level configuration changes and do not modify the immutable
base image. Foot and Zellij use the same Tokyo Night dark palette.

### Foot

Create `~/.config/foot/tokyo-night.ini`:

```ini
[colors-dark]
foreground=c0caf5
background=1a1b26
selection-foreground=c0caf5
selection-background=33467c
cursor=1a1b26 c0caf5

regular0=15161e
regular1=f7768e
regular2=9ece6a
regular3=e0af68
regular4=7aa2f7
regular5=bb9af7
regular6=7dcfff
regular7=a9b1d6

bright0=414868
bright1=f7768e
bright2=9ece6a
bright3=e0af68
bright4=7aa2f7
bright5=bb9af7
bright6=7dcfff
bright7=c0caf5

dim-blend-towards=black
```

In the `[main]` section of `~/.config/foot/foot.ini`, load the palette:

```ini
[main]
include=/home/marc/.config/foot/tokyo-night.ini
```

Keep transparency in the main Foot configuration so it can be adjusted
independently of the palette:

```ini
[colors-dark]
alpha=0.9
```

Validate the result and then open a new Foot window:

```bash
foot --check-config -c ~/.config/foot/foot.ini
```

### Zellij

Add the following top-level settings to `~/.config/zellij/config.kdl`:

```kdl
theme "tokyo-night"

themes {
    tokyo-night {
        fg 192 202 245
        bg 26 27 38
        black 21 22 30
        red 247 118 142
        green 158 206 106
        yellow 224 175 104
        blue 122 162 247
        magenta 187 154 247
        cyan 125 207 255
        white 169 177 214
        orange 255 158 100
    }
}
```

Validate the configuration:

```bash
zellij setup --check
```

The check should report `CONFIG FILE: Well defined.` Restart existing Zellij
sessions to apply the theme.

### Omarchy-style Zellij controls

The Zellij configuration keeps its native floating panes, stacked panes,
automatic layouts, plugins, and session restoration, while borrowing the
most useful navigation conventions from Omarchy's tmux configuration.

`Ctrl+b` enters Zellij's built-in command/prefix mode, whose internal KDL name
is `tmux`. This is only the name of a Zellij keybinding mode: the running
multiplexer remains Zellij, and these controls neither launch nor depend on
tmux. `Ctrl+Space` is deliberately not used because Fcitx5 owns it as the
keyboard-input/layout switcher.

| Shortcut | Action |
| --- | --- |
| `Ctrl+b`, `v` | Split pane to the right |
| `Ctrl+b`, `h` | Split pane below |
| `Ctrl+b`, `x` | Close the focused pane |
| `Ctrl+b`, `z` | Toggle focused-pane fullscreen |
| `Ctrl+b`, `c` | Create a tab |
| `Ctrl+b`, `k` | Close the current tab |
| `Ctrl+b`, `r` | Rename the current tab |
| `Ctrl+b`, `s` | Open the session manager |
| `Ctrl+b`, `d` | Detach from the session |
| `Alt+1` through `Alt+9` | Select a tab directly |
| `Alt+Left/Right` | Select the previous/next tab |
| `Alt+h/j/k/l` | Move between panes |
| `Ctrl+Alt+Arrows` | Move between panes |
| `Ctrl+Alt+Shift+Arrows` | Resize the focused pane |

Horizontal arrow navigation is deliberately reserved for tabs, while
`Alt+h/j/k/l` and `Ctrl+Alt+Arrows` are reserved for panes. This avoids the
previous `MoveFocusOrTab` behavior unexpectedly crossing a tab boundary when
the focused pane was at the edge of the screen.

The original Zellij modes remain available: `Ctrl+p` for panes, `Ctrl+t` for
tabs, `Ctrl+n` for resizing, `Ctrl+h` for moving panes, `Ctrl+s` for
scrollback, and `Ctrl+o` for sessions. Native conveniences such as `Alt+f`
for floating panes, `Alt+n` for a new pane, and `Alt+[`/`Alt+]` for swap
layouts are unchanged.

Validate after changing the bindings:

```bash
zellij setup --check
```

From the `workstation-os-image` checkout, audit drift from Zirconium's current
managed Niri/DMS defaults while treating `local.kdl` as intentional:

```bash
scripts/audit-dotfiles
```

DMS preference differences are informational because DMS writes that state at
runtime. Use `scripts/audit-dotfiles --strict` to make them fail the audit.

Existing sessions retain the configuration with which they were started, so
restart them before testing the new controls.

Set `default_layout "default"` in `~/.config/zellij/config.kdl` to load both
the tab bar and Zellij's contextual status-bar help. The `compact` layout only
shows its smaller compact bar. The shortcut audit also confirmed that Niri
uses `Super` (`Mod`) for its desktop, workspace, and window bindings, so the
Zellij `Alt` and `Ctrl+Alt` controls above do not overlap compositor bindings.

## Verification commands

```bash
echo "=== /etc/keyd/default.conf ==="
sudo cat /etc/keyd/default.conf

echo "=== keyd configuration check ==="
sudo keyd check /etc/keyd/default.conf

echo "=== keyd service state ==="
systemctl is-enabled keyd.service
systemctl is-active keyd.service
systemctl status keyd.service --no-pager
```

Expected service results are `enabled` and `active`.

## Installation result (2026-07-10)

- Configuration parsed successfully: `No errors found.`
- `keyd.service` was enabled for `multi-user.target`.
- The daemon started and matched the laptop keyboard.
- Final state was verified after startup.

To inspect the physical Copilot key event, run `sudo keyd monitor`, press the
key once, and then press Ctrl+C. This mapping assumes the key emits
`leftshift+leftmeta+f23`.

## Removal

```bash
sudo rm /etc/keyd/default.conf
sudo keyd reload
```

## Omarchy-inspired shell and TUI workflow

User-facing CLI additions in this section are installed through Homebrew and
their configuration is user-local. Host-integrated packages remain in the
workstation OS image documented at the start of this guide.

Install the integrations used below if they are not already present through
the Brewfile:

```bash
brew install direnv fzf lazydocker lazygit neovim starship zellij zoxide
```

### direnv project environments

Create `~/.config/fish/conf.d/direnv.fish`:

```fish
if command -q direnv
    direnv hook fish | source
end
```

After reviewing a project's `.envrc`, authorize it with `direnv allow`.

### Zoxide as a smarter `cd`

```bash
brew install zoxide
```

Create `~/.config/fish/conf.d/zoxide.fish`:

```fish
if status is-interactive; and command -q zoxide
    zoxide init --cmd cd fish | source
end
```

Normal paths continue to work with `cd`; non-path keywords are resolved from
Zoxide's history. Use `cdi` for an interactive directory picker.

### fzf file and history search

Create `~/.config/fish/conf.d/fzf.fish` with Tokyo Night colors and load fzf's
official Fish integration:

```fish
if status is-interactive; and command -q fzf
    set -gx FZF_DEFAULT_OPTS "
        --color=bg+:#283457,bg:#1a1b26,spinner:#7dcfff,hl:#f7768e
        --color=fg:#a9b1d6,header:#f7768e,info:#bb9af7,pointer:#7dcfff
        --color=marker:#9ece6a,fg+:#c0caf5,prompt:#bb9af7,hl+:#f7768e
        --border=rounded --height=60% --layout=reverse
    "
    fzf --fish | source
end
```

Add the Omarchy-style file finder to `~/.config/fish/conf.d/aliases.fish`:

```fish
alias ff="fzf --preview 'bat --style=numbers --color=always {}'"
```

`ff` searches files with a highlighted preview. `Ctrl+R` searches Fish command
history; `Ctrl+T` searches files and `Alt+C` searches directories.

### Fish utility functions

Fish autoloads one function per file from `~/.config/fish/functions/`. The
installed functions are:

- `compress <path>`: create `<path>.tar.gz`.
- `decompress <archive.tar.gz>`: extract an archive.
- `fip <host> <port> [port2 ...]`: open background SSH port forwards.
- `dip <port> [port2 ...]`: stop matching forwards.
- `lip`: list active forwards.

The source files are `compress.fish`, `decompress.fish`, `fip.fish`,
`dip.fish`, and `lip.fish` in the function directory. Destructive Omarchy
drive helpers are intentionally not installed. `fip` and `dip` reject anything
outside the numeric port range `1..65535`; this also prevents special regular-
expression characters from broadening `dip`'s process match.

### TUI shortcuts

The user-owned `~/.config/niri/local.kdl` defines:

- `Mod+Shift+G`: Lazygit
- `Mod+Shift+D`: Lazydocker
- `Mod+Shift+T`: btop activity monitor

Each launches directly in Foot. Niri's main configuration already includes
this optional local override file and reloads it automatically. The Foot
commands explicitly start in `/home/marc`, rather than inheriting an
implementation-dependent working directory from Niri. They also use absolute
executable paths because Niri's graphical environment does not necessarily
inherit Fish's Homebrew `PATH`:

```text
/home/linuxbrew/.linuxbrew/bin/lazygit
/home/linuxbrew/.linuxbrew/bin/lazydocker
/usr/bin/btop
```

### Screen OCR

Zirconium already supplies the complete OCR workflow through `/usr/bin/zocr`:
Niri's screenshot selector writes the chosen region, Tesseract extracts the
text, and `wl-copy` places it on the clipboard.

- `Mod+Print`: select a region and copy its text.
- `Mod+Alt+Shift+S`: alternate binding for the same action.

No additional package or configuration is required.

### Tokyo Night cohesion

The following user-level files keep terminal tools aligned with Tokyo Night:

- `~/.config/btop/btop.conf`: built-in `tokyo-night` theme.
- `~/.config/lazygit/config.yml`: Tokyo Night terminal palette and Nerd Font 3 icons.
- `~/.config/lazydocker/config.yml`: matching terminal palette and rounded borders.
- `~/.config/nvim/lua/plugins/theme.lua`: explicit `tokyonight-night` colorscheme.
- `~/.config/fish/conf.d/fzf.fish`: explicit Tokyo Night picker colors.

Foot, Zellij, Starship, DMS, and Fastfetch already inherit or explicitly use
the same palette.

### Validation

```bash
fish --no-execute ~/.config/fish/config.fish \
  ~/.config/fish/conf.d/*.fish \
  ~/.config/fish/functions/*.fish
niri validate -c ~/.config/niri/config.kdl
lazygit --use-config-file ~/.config/lazygit/config.yml --config
lazydocker --config
nvim --headless '+lua print(vim.g.colors_name)' +qa
```

The expected Neovim colorscheme is `tokyonight-night`.

## Neovim with LazyVim

Back up any existing Neovim state before installing the LazyVim starter. Do
not delete the backups until the new setup has been verified.

```bash
mv ~/.config/nvim ~/.config/nvim.bak 2>/dev/null || true
mv ~/.local/share/nvim ~/.local/share/nvim.bak 2>/dev/null || true
mv ~/.local/state/nvim ~/.local/state/nvim.bak 2>/dev/null || true
mv ~/.cache/nvim ~/.cache/nvim.bak 2>/dev/null || true
git clone https://github.com/LazyVim/starter ~/.config/nvim
rm -rf ~/.config/nvim/.git
nvim
```

The Tokyo Night override described above selects `tokyonight-night`. Verify it
non-interactively with the validation command in the preceding section.

## JetBrains Toolbox under the home directory

Install Toolbox user-locally instead of layering IDEs or keeping duplicate
Flatpak IDE installations. The release API supplies the current Linux archive:

```fish
mkdir -p ~/.local/opt ~/.local/bin
set TOOLBOX_URL (curl -fsSL \
  'https://data.services.jetbrains.com/products/releases?code=TBA&latest=true&type=release' \
  | jq -r '.TBA[0].downloads.linux.link')
curl -fL $TOOLBOX_URL -o /tmp/jetbrains-toolbox.tar.gz
tar -xzf /tmp/jetbrains-toolbox.tar.gz -C ~/.local/opt
set TOOLBOX_BIN (find ~/.local/opt -path '*/bin/jetbrains-toolbox' \
  -type f | sort | tail -n 1)
chmod +x $TOOLBOX_BIN
ln -sfn $TOOLBOX_BIN ~/.local/bin/jetbrains-toolbox
jetbrains-toolbox
```

Toolbox manages IDE versions beneath the home directory. Remove old JetBrains
Flatpaks only after confirming that projects and IDE settings have migrated.

## Updates, deployment inspection, and Flatpak recovery

Use the image-native update path for the operating system, Homebrew for user
tools, and Flatpak for desktop applications:

```bash
sudo bootc update
brew update
brew upgrade
flatpak update
```

Reboot when `bootc status` reports a staged deployment. Inspect the deployment
and package-layer state before and after image changes:

```bash
bootc status
rpm-ostree status -v
ostree admin status
```

`bootc switch ghcr.io/marcortola/workstation-os-image:latest` changes the
tracked source to the customized image and is required only once. Routine
updates use `bootc upgrade`. Pinning, undeploying, or cleaning deployments is
recovery work, not normal maintenance, and should only be done after checking
`ostree admin status` and retaining a known-good deployment.

Zirconium normally provisions system Flatpaks itself. Check its service and
Flathub remote if preinstallation failed:

```bash
systemctl status flatpak-preinstall.service --no-pager
journalctl -b -u flatpak-preinstall.service --no-pager
flatpak remotes --system --show-details
```

Repair only when those checks show a problem:

```bash
flatpak repair --user
sudo flatpak repair --system
flatpak uninstall --user --unused
sudo flatpak uninstall --system --unused
```

If the system Flathub remote itself is absent, restore it from the image's
shipped descriptor and rerun preinstallation:

```bash
sudo flatpak remote-add --system --if-not-exists flathub \
  /usr/share/flatpak/remotes.d/flathub.flatpakrepo
sudo flatpak preinstall --system -y
```

Do not remove `/var/lib/zirconium/preinstall-finished` unless diagnosing a
confirmed incomplete preinstall; it is the service's completion marker.
