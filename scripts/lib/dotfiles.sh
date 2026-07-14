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
        keymaps \
        colors \
        templates \
        options/editor.xml \
        options/editor-font.xml \
        options/console-font.xml \
        options/terminal-font.xml \
        options/laf.xml \
        options/ui.lnf.xml \
        options/colors.scheme.xml \
        options/keymap.xml \
        options/keymapFlags.xml
}

# Portable but product-specific JetBrains settings that legitimately differ per
# IDE (language code styles, file/live templates, inspections, product toolbars).
# Captured per product into config/jetbrains-settings/<Product>/ by sync-dotfiles
# and layered on top of the shared canonical during apply.
workstation_jetbrains_product_allowlist() {
    printf '%s\n' \
        codestyles \
        fileTemplates \
        inspection \
        options/code.style.schemes.xml \
        options/customization.xml \
        options/filetypes.xml
}

# The full capturable/portable set: the union of the shared and product lists.
# options/ is allow-listed one file at a time because it is otherwise dominated
# by telemetry, AI, licensing and per-machine state that must never enter Git.
workstation_jetbrains_allowlist() {
    workstation_jetbrains_shared_allowlist
    workstation_jetbrains_product_allowlist
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
