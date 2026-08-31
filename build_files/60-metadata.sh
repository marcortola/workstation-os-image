#!/usr/bin/bash
# Identify this image in /usr/lib/os-release.
#
# Three keys, all sourced from image.env so identity stays declared in one file:
#   - VARIANT_ID, the machine-readable handle for this image.
#   - NAME and PRETTY_NAME, what the system calls itself. The base is
#     base-main, so without this the workstation introduces itself as plain
#     "Fedora Linux" in the boot menu, in every fetch tool and in the shell's
#     about panel, which says nothing about which image is actually deployed.
#
# PRETTY_NAME is rebuilt from $VERSION rather than replaced with a fixed brand
# string: the base's value carries the per-deployment version
# ("Fedora Linux 44.20260830.0 (Forty Four)") and that is a real signal, so the
# result keeps it and only swaps the stem -- "Custom Fedora 44.20260830.0
# (Forty Four)".
#
# Deliberately NOT rewritten, the way bazzite's image-info does:
#   - ID=fedora is load-bearing here; 99-check-build.sh asserts it, and
#     rebranding it forces a follow-up patch of grub2-switch-to-blscfg.
#   - LOGO: DMS's SystemLogo.qml carries a Zirconium branch guarded on it, and
#     "fedora-logo-icon" is what keeps that branch dead.
#   - BUILD_ID, IMAGE_ID: `rpm-ostree status` already reports the signed image
#     reference and digest, which is a stronger identity than any string here.
set -ouex pipefail

# shellcheck source=/dev/null
source /usr/share/workstation-os-image/image.env

# VERSION comes from the base and is what PRETTY_NAME is rebuilt around; an
# empty one would silently produce "Custom Fedora " with a trailing space.
# shellcheck source=/dev/null
. /usr/lib/os-release
[ -n "${VERSION:-}" ] || { echo "os-release carries no VERSION" >&2; exit 1; }

sed -i -e "/^VARIANT_ID=/d" -e "/^NAME=/d" -e "/^PRETTY_NAME=/d" /usr/lib/os-release
{
    echo "NAME=\"${OS_NAME}\""
    echo "PRETTY_NAME=\"${OS_NAME} ${VERSION}\""
    echo "VARIANT_ID=${IMAGE_NAME}"
} >> /usr/lib/os-release
