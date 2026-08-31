#!/usr/bin/bash
# Leave the shipped image with only Fedora's own repos plus the two the base
# already trusted. Every repo we added is build-time only.
set -ouex pipefail

find /etc/yum.repos.d -name '*.repo' \
    ! -name 'fedora*.repo' \
    ! -name 'negativo17*.repo' \
    -delete
dnf5 -y config-manager setopt fedora-multimedia.enabled=0

# NEVRA manifest. The desktop stack floats permanently (COPR prunes old
# builds, so versionlock to a superseded NEVRA is impossible), which makes
# bisectability the only realistic substitute for pinning: CI diffs this file
# against the previous :latest so "the desktop broke this week" becomes
# "niri went 26.04 -> 26.05 on Tuesday".
install -d /usr/share/workstation-os-image
rpm -qa --qf '%{NAME}-%{EPOCH}:%{VERSION}-%{RELEASE}.%{ARCH}\n' \
    | sed 's/-(none)://' | sort > /usr/share/workstation-os-image/package-manifest.txt

# The dms-greeter package backs up any existing /etc/greetd/config.toml under a
# timestamped name when it installs. One lands in every build, which makes the
# image non-reproducible and ships junk; on a running machine they accumulate.
# Ours is the config that matters and it is in the image already.
rm -f /etc/greetd/config.toml.backup-*

# --- build-created accounts belong in /usr, not /etc -----------------------
# RPM scriptlets in the packages layer add greetd, greeter and wsdd to
# /etc/passwd, and a docker group to /etc/group. base-main keeps /etc/passwd at
# the root line alone and puts its 45 accounts in /usr/lib/passwd, so leaving
# them in /etc is a regression against the base's own convention.
#
# /etc is a three-way ostree merge, so anything left here becomes machine-local
# on first boot: if a later image moves greeter off uid 966 or drops wsdd, the
# stale entry survives forever and can collide with a locally created account.
#
# passwd and group only -- deliberately NOT the /etc/shadow rows bazzite's
# finalize also deletes. /etc/nsswitch.conf here reads `shadow: files systemd`
# with no altfiles, and the base itself ships 44 /etc/shadow rows for accounts
# that live only in /usr/lib/passwd. Diverging from that touches the login path,
# which CI never boots.
relocate_accounts() {
    local etc="$1" lib="$2" keep="$3" reset="$4"
    local moved line
    [ -f "$etc" ] || return 0
    moved="$(grep -vE -- "$keep" "$etc")" || true
    [ -n "$moved" ] || return 0
    echo ">>> relocating to ${lib}:"
    echo "$moved"
    { cat "$lib" 2>/dev/null || true; echo "$moved"; } > "${lib}.new"
    mv -f "${lib}.new" "$lib"
    # Fail the build rather than ship an image where an account went missing.
    while IFS= read -r line; do
        grep -qxF -- "$line" "$lib" \
            || { echo "'${line}' did not persist in ${lib}" >&2; return 1; }
    done <<< "$moved"
    printf '%s\n' "$reset" > "$etc"
}

relocate_accounts /etc/passwd /usr/lib/passwd '^root:' \
    'root:x:0:0:root:/root:/bin/bash'
relocate_accounts /etc/group /usr/lib/group '^(root|wheel):' \
    'root:x:0:
wheel:x:10:'

# shadow-utils leaves these behind whenever a scriptlet adds an account.
rm -f /etc/.pwd.lock /etc/passwd- /etc/group- /etc/shadow- /etc/gshadow-

# The rpm-ostree base-rpmdb relink itself moved to 25-rpmdb.sh, into the layer
# dnf5 writes: `ln -f` against a lower-layer file makes overlayfs copy the whole
# 90 MB rpmdb.sqlite up, and doing that here put a second copy of it in this
# layer, which is why this layer used to be 31.6 MB.
#
# The journals stay, because they are the only rpmdb files a step after
# 25-rpmdb.sh still creates: an `rpm -q` read opens the database and leaves
# -shm/-wal beside it. They are kilobytes, so copying them up costs nothing,
# and leaving base-db paired with a stale journal -- or with one the newer
# database never wrote -- is the inconsistency the original loop existed to
# avoid.
base_db=/usr/lib/sysimage/rpm-ostree-base-db
if [ -d "$base_db" ]; then
    for f in rpmdb.sqlite-shm rpmdb.sqlite-wal; do
        if [ -f "/usr/share/rpm/$f" ]; then
            ln -f "/usr/share/rpm/$f" "$base_db/$f"
        else
            rm -f "$base_db/$f"
        fi
    done
fi

dnf5 clean all
rm -rf /var/cache/libdnf5 /var/lib/dnf /var/log/dnf5.log* \
       /run/dnf /run/selinux-policy /run/tuned

# A regular file in /var cannot be expressed as a tmpfiles entry, so bootc
# container lint rejects it outright. ldconfig regenerates this on demand.
rm -f /var/cache/ldconfig/aux-cache
