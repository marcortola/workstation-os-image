#!/usr/bin/bash
# Relink the rpm-ostree "base" rpmdb onto the real one, in the SAME layer that
# wrote the real one.
#
# rpm-ostree keeps a separate base rpmdb and it still holds the BASE image's
# package set: 1244 entries against 1705 in the real rpmdb, with niri absent
# entirely, so `rpm-ostree db list` and `db diff` misreport what this image
# contains. Relink it. Must be a hard link, not a symlink.
# See https://github.com/coreos/rpm-ostree/issues/4554
#
# This used to live at the end of 90-cleanup.sh, and that placement cost every
# machine 30 MB on every upgrade. `ln -f` writes into an overlay whose lower
# layer holds the 90 MB rpmdb.sqlite, so overlayfs copies the whole file up to
# create the link -- and the resulting layer was 31,610,223 B of which 98.6% was
# a second, byte-identical copy of a database the image already shipped one
# layer down. Running it here, in the layer dnf5 itself wrote, makes the link
# free: source and target are already in this layer's upper dir.
#
# 99-check-build.sh asserts the link survives to the end of the build; if a
# later step ever writes the rpmdb again, the copy-up comes back and that gate
# is what says so.
set -ouex pipefail

base_db=/usr/lib/sysimage/rpm-ostree-base-db
if [ -d "$base_db" ]; then
    for f in rpmdb.sqlite rpmdb.sqlite-shm rpmdb.sqlite-wal; do
        if [ -f "/usr/share/rpm/$f" ]; then
            ln -f "/usr/share/rpm/$f" "$base_db/$f"
        else
            # Stale journal files left over from the base would otherwise sit
            # beside a newer database. aurora leaves these; removing them keeps
            # the pair consistent.
            rm -f "$base_db/$f"
        fi
    done
fi
