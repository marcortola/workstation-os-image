# Desktop Session

The graphical session: greetd starting it, niri compositing it, DankMaterialShell
drawing it, and the three-way split of who owns which piece of its configuration.
Read this before you touch a keybind, the terminal, or anything under
`~/.config/niri/`.

**The image owns the compositor's system config, DMS owns every fragment it
generates, and `~/.config/niri/local.kdl` is the only file that outranks both.**

---

## The Stack

Every package below is added by this image. `build_files/packages/desktop.list`
opens with the reason: "Compositor, shell and session. None of this is in ublue
base-main."

| Component | Package(s) | Source | Role |
| --- | --- | --- | --- |
| niri | `niri` | `copr:yalter/niri` | Scrollable-tiling Wayland compositor. Runs as `niri.service` in the systemd user manager. |
| DankMaterialShell (DMS) | `dms`, `dms-cli` | `copr:avengemedia/dms` | The shell: bar, launcher, notifications, lock screen, settings UI. |
| dms-greeter | `dms-greeter` | `copr:avengemedia/danklinux` | The login UI greetd launches. Built in a different COPR from `dms` — see the version-skew gotcha below. |
| quickshell | `quickshell` | `copr:avengemedia/danklinux` | The Qt/QML runtime DMS is written against. |
| dgop | `dgop` | `copr:avengemedia/danklinux` | Declared dependency of `dms`: `rpm -qR dms` lists only `quickshell`, `dgop`, `dms-cli`, `accountsservice`, `python3` and `bash`. |
| matugen | `matugen` | `copr:avengemedia/danklinux` | Generates the Material You palette into per-application templates (the `matugenTemplate*` keys in the greeter defaults enumerate them: GTK, niri, qt5ct/qt6ct, foot, kitty, Firefox, …). |
| DankSearch | `danksearch` | `copr:avengemedia/danklinux` | Filesystem search. Ships `/usr/bin/dsearch` and `dsearch.service` — the unit is **not** named `danksearch.service` — and the user preset enables it. |
| DankCalendar | `com.danklinux.dankcalendar` | Flathub | Ships as a Flatpak, not an RPM. |
| xwayland-satellite | `xwayland-satellite` | Fedora | X11 for a compositor that has no built-in XWayland. |

`rpm -qR dms` declaring almost nothing is why `build_files/packages/qt-style.list`
exists and is explicit: "A missing one gives a compositor that starts and a shell
that silently dies, and no container gate can catch it."

### The stack floats, deliberately

The COPRs track HEAD and there is no pinning available.
`build_files/packages/copr.list` states why: "These float permanently: COPR prunes
superseded builds, so versionlock to an older NEVRA is impossible."

The substitute is a bisection record: `build_files/90-cleanup.sh` bakes a sorted
NEVRA manifest of everything installed into every image, and CI diffs it against
the published one. Each COPR is also fenced by an `includepkgs` allowlist so it
can contribute nothing else. Both mechanisms belong to
[packages.md](packages.md).

### DankCalendar

Three pieces, all declarative. The Brewfile seed declares the Flatpak
(`flatpak "com.danklinux.dankcalendar"`). A captured Flatpak override grants it
the DMS colour cache read-only:

```ini
[Context]
filesystems=xdg-cache/DankMaterialShell:ro;
```

Without that grant the calendar renders in its stock palette, because its
Flathub manifest grants no filesystem access at all and it follows the session
theme by live-watching `~/.cache/DankMaterialShell/dms-colors.json`. A captured
XDG autostart entry (`Exec=flatpak run --command=dcal com.danklinux.dankcalendar
run -d --hidden`) starts the daemon and its tray icon at login, so a new machine
does not have to repeat the portal grant.

---

## Login: greetd and the Greeter

`system_files/etc/greetd/config.toml` is the whole login path:

```ini
[terminal]
vt = 1

[default_session]
command = "/usr/bin/dms-greeter --command niri --cache-dir /var/cache/dms-greeter -C /etc/greetd/niri/config.kdl"
user = "greeter"
```

The greeter runs its own minimal niri config at `/etc/greetd/niri/config.kdl` —
`DMS_RUN_GREETER "1"`, a black background, hot corners off — not the user's.
Its theme comes from image-owned defaults symlinked into `/var/cache/dms-greeter`
by `system_files/usr/lib/tmpfiles.d/99-workstation-dms-greeter.conf`, using `L+`
(replace whatever is at the path) so every boot resets them. `dms greeter sync`
repoints those links at the logged-in user's real files, and plain `L` used to
let that stand. It must not: DMS rewrites
`~/.config/DankMaterialShell/settings.json` atomically and the new inode lands as
mode `0600`, at which point uid `greeter` cannot read it. `/usr/bin/dms-greeter`
runs `set -e` and reads the cursor theme with `theme=$(jq ... 2>/dev/null)`, so
jq exits 2, the greeter dies before starting niri, greetd hits its restart limit,
and the machine boots to a text console — with nothing logged, because the
greeter's stderr goes to its own VT. That is a 2026-08-29 file edit surfacing as
a failed login on 2026-08-31. `tooling/audit/greeter` now asserts the invariant
the links exist to hold: the login path resolves only to image-owned,
world-readable files.

Refresh the greeter's appearance by editing the three files under
`system_files/usr/share/workstation-os-image/greeter/`. Nothing captures them —
they are deliberately outside both the chezmoi seed tree and `just dms-capture`,
because DMS regenerates its own copies at runtime and a captured target would be
overwritten by the UI.

`build_files/30-desktop.sh` pins `default.target` at `graphical.target`
explicitly. It is a no-op on today's base, kept because greetd's only `[Install]`
directive is `Alias=display-manager.service` and `graphical.target` is what pulls
that in; a base that shipped a headless default would leave the greeter simply
never starting.

> greetd's config is one of the very few files this image ships **directly** into
> `/etc` rather than through `/usr/share/factory` plus a tmpfiles link, because
> the greetd RPM already owns that path as a `%config` file and the link never
> fired. That makes it subject to the `/etc` three-way merge: if `rpm -V greetd`
> reports the path as modified, the image version will not land on upgrade. Fix
> it by **replacing the file's contents** (`cp /usr/etc/greetd/config.toml
> /etc/greetd/config.toml`). Do not `rm` it expecting the image copy to take
> over — ostree records a deletion as a local modification too, greetd finds no
> config, and the boot lands on a text console with `i/o error: No such file or
> directory`. See [../conventions.md](../conventions.md) for the merge itself.

---

## Configuration Ownership and Include Order

Three owners, one load order, and a silent failure mode if you get it wrong.

| Layer | Path | Owner | Rewritten by |
| --- | --- | --- | --- |
| System config | `/usr/share/workstation-os-image/niri/` (`workstation.kdl` + `includes/`) | The image | Every image update |
| Entrypoint | `~/.config/niri/config.kdl` | The image, via chezmoi (`scaffold` manifest kind) | Every `chezmoi apply` |
| Fragment shim | `~/.config/niri/dms.kdl` | The image, via chezmoi (`scaffold`) | Every `chezmoi apply` |
| DMS fragments | `~/.config/niri/dms/*.kdl` | DMS, generated at runtime | DMS, whenever a setting changes |
| Personal overrides | `~/.config/niri/local.kdl` | You | Nothing — seeded create-only |

The shim is where image ownership stops. `dms.kdl` is ours and lists the nine
`dms/*.kdl` fragments as `include optional=true`, so a fresh account parses
before DMS has ever run; the fragments themselves are DMS's, and the audit only
compares the shim.

The entrypoint is three includes, in this order:

```kdl
// image-owned system configuration (binds, input, layout, window rules)
include "/usr/share/workstation-os-image/niri/workstation.kdl"

// DankMaterialShell's generated fragments
include "dms.kdl"

// personal overrides, last so they win
include optional=true "local.kdl"
```

**niri resolves duplicate binds last-definition-wins, silently.** A later `binds`
block drops every earlier bind on the same key and `niri validate` still exits 0.
Because `dms.kdl` is included *after* the system config, DMS owns every key its
generated `dms/binds.kdl` binds — anything the image bound on that key is dead
config. And because `local.kdl` is last, it is the only file that outranks the
DMS fragment.

So there are exactly two ways to reclaim a key DMS has taken:

1. **Rebind it in `~/.config/niri/local.kdl`** and drop it from
   `system_files/usr/share/workstation-os-image/niri/includes/binds.kdl`. Leaving
   it in both places leaves a line that reads as live and is not.
2. **Release it**, with `dms keybinds remove niri <key>`, which makes DMS stop
   generating that bind at all.

> Never hand-edit `~/.config/niri/dms/binds.kdl`. DMS regenerates it, and it is
> deliberately not a chezmoi source — shipping a source for a DMS-generated file
> is what once let a lost state database silently rewrite live config.

`tooling/audit/niri-binds` is what makes the shadowing visible, since
`niri validate` will not. It runs inside `tooling/audit/dotfiles`, so `just audit`
reaches it. It asserts three things: that `local.kdl` is still the last include,
that no key in the system `binds.kdl` also appears in the DMS-generated fragment,
and that something in `local.kdl` still binds `maximize-column`. On a shadowed
bind it names the keys and the fix:

```text
DMS silently overrides binds in the system binds.kdl (1).
  Mod+Space
  Drop them from binds.kdl, and reclaim the wanted ones in local.kdl
  or release the key with 'dms keybinds remove niri <key>'.
```

The image-owned scaffolding is also audited on the machine:
`tooling/audit/dotfiles` diffs the live `config.kdl` and `dms.kdl` against the
installed image defaults under the label `Managed Niri scaffolding`, at
**critical** severity. Divergence there fails `just audit`.

The system config is partly vendored from Zirconium's `zdots`; the NOTICE in that
directory records exactly which files and against which upstream commit. See
[upstream-zirconium.md](upstream-zirconium.md).

---

## Keybinds

The full set lives in
`system_files/usr/share/workstation-os-image/niri/includes/binds.kdl`, plus the
reclaims in the `local.kdl` seed; the ones worth learning are in
[../keybindings.md](../keybindings.md). Window, column, workspace and monitor
management, media keys and scroll bindings are conventional niri, so what
follows is only the launcher and utility half — the binds that reach this
image's own scripts, each with the reason it exists. That reason is what this
page owns; the key list is not.

| Key | Runs | Notes |
| --- | --- | --- |
| `Mod+Slash` | `dms ipc call keybinds toggle workstation` | The generated cheatsheet, in DMS's searchable modal. See below. |
| `Mod+T` | `xdg-terminal-exec` | A plain Foot window. |
| `Mod+Shift+T` | `herdr` in a terminal with `--app-id=herdr` | The coding multiplexer. Launched deliberately, never from a shell rc, because every attached client mirrors the others: a second window would be a clone of the first, not a second context. |
| `Mod+Shift+P` | `workstation-dev --herdr` with `--app-id=dev-terminal` | Project picker; hands the chosen repository to herdr. See [dev-environment.md](dev-environment.md). |
| `Mod+Shift+D` | `lazydocker` with `--app-id=lazydocker` | |
| `Mod+F` | `nautilus` | |
| `Mod+Shift+S` | `dms ipc call niri screenshot` | Region screenshot through DMS. |
| `Print` / `Ctrl+Print` / `Alt+Print` | `dms ipc call niri screenshot` / `screenshotScreen` / `screenshotWindow` | Hidden from the overlay. |
| `Mod+Print` | `workstation-ocr screenshot` | Screenshot, OCR through tesseract, result on the clipboard. |
| `Mod+Alt+Shift+S` | `workstation-ocr screenshot` | Same action, hidden from the overlay. |
| `Mod+Shift+R` | `/usr/libexec/workstation-screenrecord` | Toggles `wf-recorder`: first press picks a region with `slurp`, second press sends SIGINT so the file finalises. |
| `Mod+Shift+V` | `~/.local/bin/workstation-dictate` | Dictation. Records a complete WAV, then posts it with `--form model=gpt-transcribe --form response_format=json`. `tooling/validate/all` gates that contract literally and rejects the legacy `whisper-1` / `gpt-4o-transcribe` and `response_format=text` forms, because the completed-audio model and its JSON response are what the script parses. Repurposes niri's default `switch-focus-between-floating-and-tiling` key. |
| `Ctrl+Alt+Space` | `~/.local/bin/workstation-cycle-keyboard-layout` | Cycles the configured fcitx5 input methods. Replaces fcitx5's own `Ctrl+Space` trigger so that key stays free for Neovim's `<C-Space>`. |
| `Ctrl+Alt+U` | `/usr/libexec/workstation-switch-user` | See below. |
| `Mod+Escape` | `toggle-keyboard-shortcuts-inhibit` | `allow-inhibiting=false`, so it always works. |

Reclaimed from DMS in the `local.kdl` seed, and therefore absent from the system
`binds.kdl`:

| Key | Runs | Reclaimed because |
| --- | --- | --- |
| `Mod+M` | `maximize-column` | DMS binds it to its task manager; the process list stays reachable through the DMS panel. |
| `Mod+Space` | `dms ipc call spotlight toggle` | Same action as DMS's; reclaimed only to keep the fork's label. |
| `Ctrl+Alt+Delete` | `btop` in a Foot window | DMS binds it to its task manager. |
| `Mod+Y`, `Mod+Alt+L` | DMS's own wallpaper and lock actions | Reclaimed to re-hide them from the overlay. |

### Mod+Slash opens the generated cheatsheet, not niri's overlay

niri's own overlay orders itself (below), cannot be searched, and only ever
knows about niri — so it never showed the editor, the session multiplexer or the
terminal, which is most of what there is to forget. DMS renders any JSON
cheatsheet dropped in `~/.config/DankMaterialShell/cheatsheets/` in a
layer-shell modal that focuses a search box on open, so `Mod+Slash` spawns
`dms ipc call keybinds toggle workstation` instead.

`tooling/keybindings/build-cheatsheet.py` generates that sheet, wired into
`just sync` with `--check` in `tooling/validate/all`. It is in two halves.

The **digest** is the first screen. The three `###` blocks of the "Every Day"
section of [../keybindings.md](../keybindings.md) become the three columns --
`Desktop (Mod)`, `Herdr (Ctrl+G)`, `Nvim (Space)` -- and their `####` headings
become the groups inside each.

The **reference** is everything below it: the rest of that page for the in-app
layers, and `binds.kdl` plus the `local.kdl` seed for the desktop, which is
rebuilt from the KDL rather than the doc so it is complete rather than curated.
`tooling/data/cheatsheet-layout` groups it into topic-sized categories.

#### Why the digest stays on top

DMS ignores the order categories appear in the JSON. `KeybindsContent.qml`
sorts them by estimated height, descending, then greedy-packs each into the
shortest column:

```js
const sorted = [...categoryKeys].sort(
    (a, b) => estimateCategoryHeight(b) - estimateCategoryHeight(a));
```

With three empty columns, the three *tallest* categories therefore land at the
top of the three columns. That is the only lever over what sits above the fold,
and the digest wins it by being taller than every reference category. Three
numbers make that hold, and the generator asserts all three rather than trusting
them:

| Assertion | Why |
| --- | --- |
| a digest column is at most 28 rows-plus-headings | measured, not derived: a calibration sheet of numbered rows shows 25 rows plus 3 group headings per column before the fold at the overlay's 900px, and DMS bills a heading the same 28px as a bind |
| every reference category is shorter than the shortest digest column | otherwise DMS packs it at the top of a column and pushes a digest column out of view |
| no digest key exceeds 16 characters | DMS renders a key as `Mod + Shift + H`, spaces and all, in a narrow column. `Mod+Ctrl+Up/Down` (16) fits on one line; `Mod+Shift+H/J/K/L` (17) wraps onto two and costs a row the fold arithmetic has not budgeted for |

The fold is the *overlay's*. The icon beside the search box switches to a
floating window 80px shorter, where the last rows of each digest column need a
scroll. That is a deliberate trade: sizing for the floating window would cost
nine rows of the sheet people actually read.

#### Where the labels come from

Descriptions for the desktop come from each bind's `hotkey-overlay-title`, and
group headings from the `// ── Section ──` comments `binds.kdl` is already
organised by -- so that curation stays load-bearing, just for a different
reader, and the section comments are structure now rather than decoration. A
bind with no title has no label to borrow, so it must be named in
`tooling/data/niri-bind-descriptions`; that file is asserted in both
directions, and adding an untitled bind without describing it fails the build
instead of dropping it from the sheet. `hotkey-overlay-title=null` still means
hidden.

Two keys are real on a running session but appear in no file this repo owns:
`Mod+N` and `Mod+Shift+N` live only in the DMS-generated fragment. They are
declared in the same file with a leading `+`, which marks an addition rather
than a description, and the generator rejects one that collides with a bind the
repo already defines. `Mod+Y` and `Mod+Alt+L` are DMS's too, but `local.kdl`
rebinds them `hotkey-overlay-title=null`, and that decision is honoured.

Keys are shortened on the way in -- `Mod+H` / `Mod+L` becomes `Mod+H/L`,
`WheelScrollDown` becomes `Wheel↓`. The doc's backticks are read before they
are stripped, since `` `Space` `/` `` is a sequence while `` `Mod+H` / `Mod+L` ``
is an alternation and the two are indistinguishable afterwards.

### niri's own overlay does not follow file order

Nothing binds `show-hotkey-overlay` now, but the annotations that shaped it are
still what labels the generated sheet, so the ordering rules stay documented.
niri emits three tiers: a fixed compiled block of "important" actions, always in the
same sequence; then every bind carrying a custom `hotkey-overlay-title` whose
action is not already in that block, in file order; then any untitled `Mod`/`Super`
`spawn` bind. A custom title on a fixed-block action only *relabels* its row; it
cannot move it. That is why `binds.kdl` is grouped the way it is, and why
directional pairs give one half a title and the other `hotkey-overlay-title=null`
so niri collapses them into a single row. The reclaimed binds in `local.kdl`
resolve last, so their rows land at the end of the titled section — except
`Mod+M`, whose `maximize-column` is a fixed-block action and stays pinned to
niri's slot.

### What the build gate does and does not check

`niri validate` parses the config but never checks that a spawned binary exists,
so a bind pointing at a removed program stays silent until the key is pressed —
that is how `spawn "zocr"` survived the base swap. `build_files/99-check-build.sh` closes
that by resolving every spawn target:

```bash
done < <(grep -hoE 'spawn "[^"]+"' \
    /usr/share/workstation-os-image/niri/includes/*.kdl 2>/dev/null \
    | sed 's/spawn "//; s/"$//' | sort -u)
```

Note the shape of that grep: it matches `spawn "..."` only. A `spawn-sh` bind, or
a bind in `local.kdl`, is not covered.

---

## The Default Terminal

The terminal is `footclient` against a socket-activated `foot` server. The user
preset enables both halves, because "without the socket the first footclient has
nothing to connect to". Both carry a `ConditionUser=!@system` drop-in so they do
not also start in the greeter's user manager against a read-only home.

Which terminal that is gets declared exactly once, in
`/etc/xdg/xdg-terminals.list`, so the niri binds and anything else asking for "a
terminal" agree. That file does **not** ship at `system_files/etc/`. It ships at
`system_files/usr/share/factory/etc/xdg/xdg-terminals.list` and is materialised
by an `L+` line in
`system_files/usr/lib/tmpfiles.d/10-workstation-terminal.conf` — the
factory-plus-tmpfiles mechanism defined in [../conventions.md](../conventions.md),
which is what lets a user edit in `/etc` survive an image update.

The declaration has to sit in `/etc/xdg` rather than replace the package's own
list. `/etc/xdg` is an `XDG_CONFIG_DIRS` entry, so it outranks the
`xdg-terminal-exec` package's fallback list in `/usr/share` — including that
list's `-footclient.desktop` exclusion line, because an explicit entry read at
higher precedence pre-empts a later fallback exclusion. Overwriting the package
file instead, which the previous base did, would have discarded its
`execarg_default` table along with it. A user overrides the whole thing with
`~/.config/xdg-terminals.list`, which is read first.

The entry it names is the image's own,
`system_files/usr/share/applications/workstation-footclient.desktop`, and it
exists because Fedora's `foot.desktop` and `footclient.desktop` declare none of
the Default Terminal Specification's `X-TerminalArg*` keys, so `xdg-terminal-exec`
accepts `--app-id` and `--title` and then silently discards them. The herdr,
dev-terminal and lazydocker binds all landed as app-id `foot`, so
`herdr.desktop`, `dev-terminal.desktop` and `lazydocker.desktop` — which exist
purely to give those app-ids an icon and a name in the overview — could never
associate with a window. The keys and the gate that now asserts the resulting
command line are described in [../conventions.md](../conventions.md); check a
live session with:

```bash
xdg-terminal-exec --print-cmd --app-id=herdr --title=herdr -- /bin/true
```

### The prompt and the palette

The shell inside that terminal is Fish, and the prompt is **Starship**. It is a
Brewfile formula (`brew "starship"`); its configuration is a create-only chezmoi
template, `dot_config/create_starship.toml.tmpl`, authored in the repository
rather than captured from live; and `dot_config/fish/create_config.fish`
initialises it behind a guard, so a machine where the formula is not installed
still gets a working shell instead of an error on every prompt:

```fish
if status is-interactive; and command -q starship
    set -gx STARSHIP_CONFIG ~/.config/starship.toml
    starship init fish | source
end
```

**Tokyo Night is the palette everywhere it can be chosen, deliberately.** It is
the DMS theme (`dot_config/DankMaterialShell/themes/tokyoNightDark/`), foot's
colours (`dot_config/foot/create_tokyo-night.ini`, included by the personal
`workstation.ini` layer), `color_theme = "tokyo-night"` in
`dot_config/btop/create_btop.conf`, `name = "tokyo-night"` in
`dot_config/herdr/create_config.toml`, and `colorscheme = "tokyonight-night"` in
`dot_config/nvim/lua/plugins/create_theme.lua`. The shell, the terminal, the
multiplexer pane, the editor and the system monitor therefore render one palette,
so nothing inside a full-screen session looks borrowed from somewhere else. The
exception is foot's `dank-colors.ini`, which DMS/matugen regenerates from the
live Material You palette: that file follows the wallpaper, not this theme.

---

## Switch User

greetd runs one graphical session at a time, so a second user logs in on a spare
virtual terminal and you hop between them:

1. Press `Ctrl+Alt+F3` to reach a free console and log in as the other user.
2. Run `run-ui` there to start their desktop. It is an easy-to-remember front for
   `niri-session`, which it simply execs; it refuses if `WAYLAND_DISPLAY` or
   `DISPLAY` is already set.
3. Move between sessions with `Ctrl+Alt+F1` and `Ctrl+Alt+F3`, or press
   `Ctrl+Alt+U` to jump straight to the other running session. The power menu's
   **Switch User** entry lists the same sessions.

`Ctrl+Alt+U` runs `/usr/libexec/workstation-switch-user`, which walks
`loginctl list-sessions`, skips the current session and anything whose `Class` is
not `user` or whose `State` is `closing`, and `loginctl activate`s the first
match. With nobody else logged in it does not fail silently — it fires a
notification telling you to do step 1.

To go back to a single session, log out from the power menu.

---

## Session Environment

Session-wide variables go in `/usr/lib/environment.d`, never `/etc/profile.d` —
the rule and its failure are in [../conventions.md](../conventions.md). Three
files under `system_files/usr/lib/environment.d/` carry it, and what each one
sets is the part specific to this session:

| File | Sets | Because |
| --- | --- | --- |
| `40-workstation-editor.conf` | `EDITOR`, `VISUAL` (absolute paths into Homebrew) | herdr is launched from a niri keybind and never sources `config.fish`, so its "open this pane's scrollback in `$EDITOR`" binding would have no editor to reach for. |
| `50-workstation-input-method.conf` | `QT_IM_MODULE`, `XMODIFIERS`, `SDL_IM_MODULE`, `GLFW_IM_MODULE`, … | fcitx5 is installed and enabled, but Wayland-native toolkits reach it over `text-input-v3` while XWayland clients, SDL and GLFW all have to be told. `GTK_IM_MODULE` is deliberately **empty**: setting it to `fcitx` forces GTK down the legacy module path and breaks the Wayland protocol it would otherwise use. |
| `60-workstation-fonts.conf` | `FREETYPE_PROPERTIES` | Turns stem darkening back on for the CFF and autofit drivers; Fedora builds it off, which leaves the shell and terminal noticeably lighter at the same size and DPI. |

`PATH` is the exception, and it cannot use this mechanism. `niri --session`
imports its own environment into the systemd user manager and the D-Bus
activation environment, overwriting whatever `environment.d` set. So Homebrew's
bin directory is prepended in a drop-in on `niri.service` itself
(`system_files/usr/lib/systemd/user/niri.service.d/10-homebrew-path.conf`) —
which is why a GUI application niri spawns can find a brew tool such as `node`.
systemd replaces `PATH` wholesale, so that drop-in restates niri's default
session PATH alongside the brew entries, and `%h` expands to the user home so no
username is hardcoded.

---

## XWayland Interop

niri has no built-in XWayland; it routes X11 clients through
`xwayland-satellite`. Two cross-boundary interactions do not come along for the
ride.

**Clipboard** is bridged. `workstation-x11-clipsync.service` (enabled in the user
preset, `Restart=always`) runs `/usr/libexec/workstation-x11-clipsync`, which
mirrors the Xwayland CLIPBOARD selection into the Wayland clipboard. It is not a
shipped script: it is compiled from `build_files/src/workstation-x11-clipsync.c`
in the toolchain stage, so look there rather than under `system_files/`.

**Drag-and-drop cannot be bridged by a helper.** The workaround is to remove the
boundary instead: `workstation-flatpak-wayland.service` runs, at every login,

```bash
/usr/bin/flatpak override --user --socket=wayland --env=ELECTRON_OZONE_PLATFORM_HINT=auto
```

No app id, so it applies to every Flatpak; `--user`, so it goes through
`flatpak override` into the user installation rather than editing the base-owned
`overrides/global` file. `--socket=wayland` grants the Wayland socket to apps
whose manifest omits it (Postman ships `sockets=x11` only), and
`ELECTRON_OZONE_PLATFORM_HINT=auto` then makes Electron pick Wayland — so
Electron/Chromium Flatpaks run as native Wayland clients and never cross the
boundary at all. The unit is `Type=oneshot`, `RemainAfterExit=yes` and
idempotent, re-asserted every login so it survives a base rewrite.

Genuinely X11-only applications — ones with no Wayland backend to switch to —
still cannot drag-and-drop with Wayland apps. Tracked upstream at
[Supreeeme/xwayland-satellite#133](https://github.com/Supreeeme/xwayland-satellite/issues/133),
which the unit carries as a second `Documentation=` line.

---

## Power Profiles

DMS ships `Services/PowerProfileWatcher.qml` and `Modals/PowerProfileModal.qml`,
which talk to the D-Bus name `net.hadess.PowerProfiles`. Nothing on base-main
provides that name, so the widget had no backend at all. `build_files/packages/desktop.list`
installs `tuned` and `tuned-ppd` as the provider; `power-profiles-daemon` is the
other implementation and the two conflict, so only one can be present.

---

## The herdr Bar Widget

`herdrJobs` is a DMS plugin, sitting in the centre of the bar just after the
notification button. It carries two counts — spaces that are `blocked` in red
and `done` in green, each hidden at zero — and opens a popout listing every open
space with its state, the same rows the `prefix+s` space picker draws. Clicking a
row focuses that space and raises the herdr window; the popout closes behind it.

The counts are `done` rather than the picker's `*` freshness mark, deliberately:
herdr keeps calling a space `done` until it goes back to work, so the count
survives until it is dealt with, where the mark expires after
`AGENT_FRESH_SECONDS` whether or not anyone looked.

`Mod+S` opens the same popout without the mouse, mirroring herdr's own
`prefix+s`. The bind is `dms ipc call widget toggle herdrJobs` — `widget` is
DMS's generic bar-widget popout IPC, and it treats a plugin id like any built-in
one. It is in the full reference in [../keybindings.md](../keybindings.md) but
not in the one-screen digest, which is at its 28-row cap.

It is the first QML this repository ships, and it is a **view, not a second
source**. Every row comes from `spaces.sh --json`, the picker's own row builder:

```
~/.config/herdr/plugins/dev-flow/spaces.sh --json
```

The picker renders those objects as padded TSV, the widget parses them as JSON,
and neither recomputes state, the just-finished `*` mark or the attention
ordering. That matters more than it looks: herdr times nothing, so freshness can
only come from the stamp `agent-freshness.sh` writes — see
[dev-environment.md](dev-environment.md) and
[../design-records/agent-recency.md](../design-records/agent-recency.md).

`--json` lists **open spaces only**, unlike the picker, so it runs no `git` at
all: two herdr socket reads and a `jq` pass, polled every three seconds. The
widget is the ambient indicator; the picker stays the navigator. Focusing is
`focus-space.sh`, which scopes the session over the socket and then raises the
window — the picker never needs the second half, because it is already running
inside the window it would raise.

Four files have to agree, and every way they can disagree is silent:

| File | What it carries |
| --- | --- |
| `.../dotfiles/dot_config/DankMaterialShell/plugins/herdrJobs/plugin.json` | The id, the component path, and `capabilities` |
| `.../plugins/herdrJobs/HerdrJobsWidget.qml` | The pill, the popout, the poll |
| `.../dotfiles/dot_config/DankMaterialShell/create_plugin_settings.json` | The enablement seed. Create-only, because DMS owns that file afterwards for every other plugin |
| `system_files/usr/share/workstation-os-image/dms-settings.json` | The bar entry, in `barConfigs[].centerWidgets` |

A plugin with no bar entry loads and renders nothing; a bar entry with no
enablement seed renders nothing either; a `launcher` capability routes the widget
off the bar entirely. `tooling/validate/sources` asserts all four agree.

What it cannot assert is the QML. Nothing on this machine lints QML — there is
no `qmllint` — so a syntax error passes `just validate` and shows up only as a
missing widget. The check is a reload:

```
dms ipc call plugins reload herdrJobs    # PLUGIN_RELOAD_SUCCESS, or a component error
```

An error anywhere in the file, including inside the popout that is only built on
click, fails that reload rather than waiting for the click.

## DMS Settings Ownership

DMS settings are **UI-owned after a one-time seed**. On first login
`workstation-dms-settings.service` runs `workstation-apply-dms-settings
--initialize`, which merges the tracked overlay at
`/usr/share/workstation-os-image/dms-settings.json` into the live
`settings.json` and then writes a marker under `$XDG_STATE_HOME`; a later
`--initialize` sees the marker and exits 0 without touching anything. This is the
one deliberate exception to the rule that a re-runnable seed keys on a hash of
its own script rather than a bare marker — after first run, the UI owns the file
and re-seeding would fight the user.

Promoting a GUI preference into the tracked overlay, and restoring the overlay
into a live account, is the capture workflow, owned by
[../capturing-changes.md](../capturing-changes.md). Do not improvise around it.

---

## Gotchas and tech debt

| Gotcha | Consequence | Handling |
| --- | --- | --- |
| DMS shadows a system bind | `niri validate` passes; the key silently does DMS's thing | `tooling/audit/niri-binds` fails on it. Reclaim in `local.kdl` and drop from `includes/binds.kdl`, or `dms keybinds remove niri <key>` |
| `/etc/greetd/config.toml` locally modified | The image's version never lands on upgrade | Replace the file's contents; never `rm` it, which boots to a text console |
| `dms` and `dms-greeter` ship from two COPRs | A half-finished publish gives a shell that starts and then misbehaves | `99-check-build.sh` compares `%{VERSION}` across `dms`, `dms-cli`, `dms-greeter` and fails the build on skew. Re-run once both COPRs have caught up |
| The desktop stack floats on COPR HEAD | No pinning is possible; a bad upstream day reaches the next build | `package-manifest.txt` in each image, diffed by CI against the published `:latest` resolved by digest |
| A terminal entry without `X-TerminalArg*` | `xdg-terminal-exec` silently drops `--app-id` and `--title`; app-id-matched desktop entries stop associating | The image ships `workstation-footclient.desktop`; the build gate asserts the resulting command line, not just the resolved entry |
| The niri spawn-target gate greps `spawn "..."` | A `spawn-sh` target, or anything in `local.kdl`, is not resolved at build time | Known gap. Prefer `spawn "..."` for a bare binary; `spawn-sh` only where `$HOME` expansion is genuinely needed |
| `local.kdl` is seeded create-only | Editing `create_local.kdl.tmpl` in the repo never re-seeds an account that already has the file | Change the live file, then run `just sync` to refresh the seed |
| A plugin directory created while DMS runs | `PluginService` binds its watcher once at startup, and a watcher aimed at a missing folder never fires when it appears, so the plugin is invisible | `dms ipc call plugin-scan scan`, once. On a fresh account there is no gap: chezmoi runs at `graphical-session-pre.target`, before `dms.service` |
| `just dms-capture` on `barConfigs` | The recipe takes the live array wholesale and the apply side replaces arrays rather than merging them, so capturing while `herdrJobs` is absent from live deletes it from the overlay | Capture `barConfigs` only from a session that already has the widget on the bar |
| DnD with genuinely X11-only apps | Still broken, and not fixable here | Upstream `xwayland-satellite#133` |
| `dsearch.service` in the greeter's user manager | Crash-loops on a read-only home for as long as the login screen is up | A `10-skip-system-users.conf` drop-in setting `ConditionUser=!@system` — the same treatment given to `dms`, `fcitx5`, `foot-server`, `gcr-ssh-agent`, `iio-niri`, `udiskie` and `xdg-user-dirs`. `99-check-build.sh` fails the build if the user preset enables a non-`workstation-*` unit without one |

---

## Where to go next

The vendored half of the niri config, the NOTICE that records what came from
where, and the workflow for reviewing upstream changes are in
[upstream-zirconium.md](upstream-zirconium.md). The mechanisms this page keeps
citing as instances — the `/etc` merge, factory-plus-tmpfiles, `ConditionUser`,
`environment.d`, `X-TerminalArg` — are defined once in
[../conventions.md](../conventions.md). To see which gate would have caught a
given mistake, and which of them CI can reach without a live workstation, see
[../validation-and-gates.md](../validation-and-gates.md).
