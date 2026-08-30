#!/usr/bin/bash
# Identify this image in /usr/lib/os-release.
#
# VARIANT_ID only. Deliberately NOT rewriting ID, PRETTY_NAME, BUILD_ID or
# IMAGE_ID the way bazzite's image-info does:
#   - ID=fedora is load-bearing here; 99-check-build.sh asserts it, and
#     rebranding it forces a follow-up patch of grub2-switch-to-blscfg.
#   - PRETTY_NAME drives the boot-menu title, and the base's carries the
#     per-deployment version ("Fedora Linux 44.20260830.0"). Replacing it with a
#     fixed brand string deletes a signal rather than adding one.
#   - `rpm-ostree status` already reports the signed image reference and digest,
#     which is a stronger identity than any string in this file.
set -ouex pipefail

# shellcheck source=/dev/null
source /usr/share/workstation-os-image/image.env

sed -i "/^VARIANT_ID=/d" /usr/lib/os-release
echo "VARIANT_ID=${IMAGE_NAME}" >> /usr/lib/os-release
