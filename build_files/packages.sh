#!/usr/bin/bash
# Package installation, one dnf transaction per list so a failure names the
# group it came from rather than dumping one 200-package error.
set -ouex pipefail

for list in /ctx/packages/*.list; do
    name="$(basename "$list" .list)"
    mapfile -t pkgs < <(sed -E 's/#.*//' "$list" | grep -vE '^\s*$' | awk '{print $1}')
    [ "${#pkgs[@]}" -gt 0 ] || continue
    echo ">>> installing ${name} (${#pkgs[@]} packages)"
    dnf5 -y install --setopt=install_weak_deps=False "${pkgs[@]}"
done
