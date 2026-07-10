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
