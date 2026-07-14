#!/usr/bin/env bash

workstation_seed_path() {
    local source_root=$1 source_dir=$2 relative=$3
    local parent basename
    parent=${relative%/*}
    basename=${relative##*/}
    [[ $parent == "$relative" ]] && parent=
    printf '%s/%s%s/create_%s\n' \
        "$source_root" "$source_dir" "${parent:+/$parent}" "$basename"
}

workstation_live_relative() {
    local relative=$1 parent basename
    parent=${relative%/*}
    basename=${relative##*/}
    [[ $parent == "$relative" ]] && parent=
    basename=${basename#create_}
    printf '%s%s%s\n' "$parent" "${parent:+/}" "$basename"
}

# Portable JetBrains settings that should feel identical across every IDE:
# shortcuts, colours, fonts and product-neutral editor/UI behaviour. These are
# maintained once in config/jetbrains-settings/_shared/ (the single canonical
# source) and applied into each IDE by scripts/apply-jetbrains-settings. Each
# entry is a path relative to a product configuration directory; directories are
# handled recursively.
workstation_jetbrains_shared_allowlist() {
    printf '%s\n' \
        keymaps/custom.xml \
        templates \
        options/editor.xml \
        options/editor-font.xml \
        options/terminal-font.xml \
        options/laf.xml \
        options/ui.lnf.xml \
        options/vcs.xml \
        options/ignore.xml \
        options/colors.scheme.xml \
        options/keymapFlags.xml \
        options/linux/keymap.xml
}

# Portable but product-specific JetBrains settings that legitimately differ per
# IDE (a language code style and file/live templates). Captured per product into
# config/jetbrains-settings/<Product>/ by sync-dotfiles and layered on top of the
# shared canonical during apply.
workstation_jetbrains_product_allowlist() {
    printf '%s\n' \
        codestyles/custom.xml \
        fileTemplates \
        options/code.style.schemes.xml \
        options/php.xml
}

# The full capturable/portable set: the union of the shared and product lists.
# options/ is allow-listed one file at a time because it is otherwise dominated
# by telemetry, AI, licensing and per-machine state that must never enter Git.
workstation_jetbrains_allowlist() {
    workstation_jetbrains_shared_allowlist
    workstation_jetbrains_product_allowlist
}

# Files embedded in _shared/ from upstream or authored by hand rather than captured
# from a live IDE, so promote-jetbrains-shared must preserve them: the colour
# schemes vendored from upstream, and the shared plugin list. apply writes the
# colour schemes into the IDEs; plugins.list drives apply-jetbrains-plugins and is
# never written into an IDE configuration directory.
workstation_jetbrains_vendored() {
    printf '%s\n' \
        'colors/Photon - Light.icls' \
        'colors/Photon - Dark.icls' \
        plugins.list
}

# Map a JetBrains config product (the manifest source path, e.g. IntelliJIdea) to
# its Toolbox app directory and launcher/process basename, printed as
# "<app-dir> <launcher>". Most products match their lowercase name; IntelliJ IDEA
# is the exception (app "intellij-idea", launcher and process "idea").
workstation_jetbrains_launcher() {
    case "$1" in
        IntelliJIdea) printf '%s %s\n' 'intellij-idea' 'idea' ;;
        *) printf '%s %s\n' "${1,,}" "${1,,}" ;;
    esac
}

# Detect a running IDE for a product by its launcher process name (e.g.
# IntelliJIdea -> "idea", PhpStorm -> "phpstorm"). Matching the exact comm avoids
# false positives from background helpers (embeddings-server, fsnotifier) that
# merely reference the config directory.
workstation_jetbrains_ide_running() {
    local comm
    read -r _ comm < <(workstation_jetbrains_launcher "$1")
    pgrep -x "$comm" >/dev/null 2>&1
}

# Emit the shared plugin IDs from a plugins.list file, one per line, skipping
# comments (# to end of line) and blank lines, trimming surrounding whitespace.
workstation_jetbrains_plugins() {
    local list=$1
    [[ -f $list ]] || return 0
    sed 's/#.*//' "$list" | awk '{gsub(/^[ \t]+|[ \t]+$/, "")} NF'
}

# Names that must never appear in the captured JetBrains backup tree. Enforced
# by scripts/validate-jetbrains-settings as a backstop to the allow-list. A file
# entry matches a basename glob; a bare name also matches any path segment so a
# denied directory is caught anywhere in the tree.
workstation_jetbrains_denylist() {
    printf '%s\n' \
        '*.key' \
        'dataSources*' \
        'security.xml' \
        'recentProjects.xml' \
        'trusted-paths.xml' \
        'settingsSyncLocal.xml' \
        'usage.statistics.xml' \
        'ssl' \
        'settingsSync' \
        'workspace' \
        'tasks' \
        'dataSourcesHistory' \
        'jdbc-drivers'
}

# Resolve the newest installed product directory for a version-globbed manifest
# live path such as ".config/JetBrains/PhpStorm*". Prints the absolute path of
# the highest-versioned match, or nothing when the product is not installed.
workstation_jetbrains_newest_dir() {
    local live_path=$1 parent pattern name
    parent="$HOME/${live_path%/*}"
    pattern="${live_path##*/}"
    [[ -d $parent ]] || return 0
    name="$(find "$parent" -mindepth 1 -maxdepth 1 -type d -name "$pattern" \
        -printf '%f\n' 2>/dev/null | sort -V | tail -n1)"
    [[ -n $name ]] && printf '%s\n' "$parent/$name"
}
