#!/usr/bin/bash
# Package installation, one dnf transaction per list so a failure names the
# group it came from rather than dumping one 200-package error.
set -ouex pipefail

# Hard excludes, applied to every transaction.
mapfile -t excludes < <(sed -E 's/#.*//' /ctx/build/packages/exclude.list | grep -vE '^\s*$' | awk '{print $1}')
exclude_args=()
for e in "${excludes[@]}"; do exclude_args+=(--exclude="$e"); done

for list in /ctx/build/packages/*.list; do
    [ "$(basename "$list")" = exclude.list ] && continue
    name="$(basename "$list" .list)"
    mapfile -t pkgs < <(sed -E 's/#.*//' "$list" | grep -vE '^\s*$' | awk '{print $1}')
    [ "${#pkgs[@]}" -gt 0 ] || continue
    echo ">>> installing ${name} (${#pkgs[@]} packages)"
    dnf5 -y install --setopt=install_weak_deps=False "${exclude_args[@]}" "${pkgs[@]}"
done
