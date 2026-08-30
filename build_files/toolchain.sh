#!/usr/bin/bash
# Builder stage. Compiles everything that is not packaged, into /staging.
#
# One stage, not three: the compiler is pulled in once and the whole layer is
# discarded, so there is no point uninstalling anything or cleaning dnf caches
# here -- that work never reaches the final image.
set -ouex pipefail

dnf5 -y install --setopt=install_weak_deps=False \
    gcc make curl tar libX11-devel libXfixes-devel

install -d /staging/usr/libexec /staging/usr/bin \
           /staging/usr/lib/systemd/system /staging/usr/lib/sysusers.d \
           /staging/usr/share/fonts

# --- X11 clipboard bridge -----------------------------------------------
# Watches the X11 CLIPBOARD selection under Xwayland and mirrors it into the
# Wayland clipboard. Needed because some XWayland clients (1Password) do not
# hand over the selection on their own.
gcc -O2 -Wall -Wextra \
    -o /staging/usr/libexec/workstation-x11-clipsync \
    /ctx/build_files/src/workstation-x11-clipsync.c \
    -lX11 -lXfixes

# --- keyd ---------------------------------------------------------------
# Not packaged in Fedora and not in ublue base-main. Built from pinned source
# with a checksum, which makes it the one fully reproducible input in this
# build. Only the daemon, its unit and its sysusers group are kept; the docs,
# man pages and stock layouts that `make install` would add are omitted.
KEYD_VERSION="${KEYD_VERSION:?}"
KEYD_SHA256="${KEYD_SHA256:?}"
curl -fsSL -o /tmp/keyd.tar.gz \
    "https://github.com/rvaiya/keyd/archive/refs/tags/v${KEYD_VERSION}.tar.gz"
echo "${KEYD_SHA256}  /tmp/keyd.tar.gz" > /tmp/keyd.sha256
sha256sum -c /tmp/keyd.sha256
tar -xzf /tmp/keyd.tar.gz -C /tmp
make -C "/tmp/keyd-${KEYD_VERSION}" COMMIT="v${KEYD_VERSION}" PREFIX=/usr
install -Dm755 "/tmp/keyd-${KEYD_VERSION}/bin/keyd" /staging/usr/bin/keyd
sed 's#@PREFIX@#/usr#' "/tmp/keyd-${KEYD_VERSION}/keyd.service.in" \
    > /staging/usr/lib/systemd/system/keyd.service
install -Dm644 "/tmp/keyd-${KEYD_VERSION}/data/sysusers.d" \
    /staging/usr/lib/sysusers.d/keyd.conf

# --- FiraCode Nerd Font -------------------------------------------------
# Referenced by fontconfig/fonts.conf and by dms-settings.json monoFontFamily,
# but shipped by no image: on the pre-rebuild machine fc-list resolved it from
# ~/.local/share/fonts, owned by no package, so a fresh account silently fell
# back to a default monospace and every Nerd Font glyph rendered as tofu.
# Pinned by checksum so it adds no repo and stays reproducible.
FIRACODE_VERSION="${FIRACODE_VERSION:?}"
FIRACODE_SHA256="${FIRACODE_SHA256:?}"
curl -fsSL -o /tmp/firacode.tar.xz \
    "https://github.com/ryanoasis/nerd-fonts/releases/download/v${FIRACODE_VERSION}/FiraCode.tar.xz"
echo "${FIRACODE_SHA256}  /tmp/firacode.tar.xz" > /tmp/firacode.sha256
sha256sum -c /tmp/firacode.sha256
install -d /staging/usr/share/fonts/firacode-nerd-fonts
tar -xJf /tmp/firacode.tar.xz -C /staging/usr/share/fonts/firacode-nerd-fonts \
    --wildcards '*.ttf'
