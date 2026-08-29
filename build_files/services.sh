#!/usr/bin/bash
# Unit enablement.
set -ouex pipefail

# base-main uses `systemctl enable`, not presets, for its update timers, which
# writes real symlinks into /etc. A preset file CANNOT undo an existing
# enablement symlink, so a `disable` line in our preset is not enough on its
# own: without these three explicit calls they keep running alongside uupd and
# two system-update paths race every night at 04:00.
systemctl disable rpm-ostreed-automatic.timer flatpak-system-update.timer
systemctl --global disable flatpak-user-update.timer

# getty@tty1 stays enabled on purpose. greetd carries
# Conflicts=getty@tty1.service so it is displaced at runtime, and it is the
# only escape hatch if the greeter fails to start.

# Explicit lists, never `preset-all`: base-main configured units deliberately
# and re-evaluating all of them would undo that.
systemctl preset \
    greetd.service \
    uupd.timer \
    docker.service containerd.service \
    keyd.service \
    brew-setup.service brew-update.timer brew-upgrade.timer \
    workstation-brew-trust.service \
    workstation-user-groups.service

systemctl --global preset \
    dms.service \
    dsearch.service \
    fcitx5.service \
    iio-niri.service \
    udiskie.service \
    workstation-chezmoi-init.service \
    workstation-chezmoi-update.timer \
    workstation-bootstrap.service \
    workstation-claude-mcp-seed.service \
    workstation-dms-settings.service \
    workstation-flatpak-wayland.service \
    workstation-invoice-bookmarks.timer \
    workstation-microsoft-fonts.service \
    workstation-x11-clipsync.service
