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

dnf5 clean all
rm -rf /var/cache/libdnf5 /var/lib/dnf /var/log/dnf5.log* \
       /run/dnf /run/selinux-policy

# A regular file in /var cannot be expressed as a tmpfiles entry, so bootc
# container lint rejects it outright. ldconfig regenerates this on demand.
rm -f /var/cache/ldconfig/aux-cache
