#!/usr/bin/bash
# Unit enablement.
set -ouex pipefail

# base-main uses `systemctl enable`, not presets, for its update timers, which
# writes real symlinks into /etc. A preset file CANNOT undo an existing
# enablement symlink, so a `disable` line in our preset is not enough on its
# own: without these three explicit calls they keep running alongside uupd and
# two system-update paths race every night at 04:00.
# rpm-ostreed-automatic.timer is rpm-ostree's own unit and still needs an
# explicit disable. The two flatpak timers came from ublue-os-update-services,
# which 20-packages.sh removes outright.
systemctl disable rpm-ostreed-automatic.timer

# The ublue brew layer's own preset enables brew-update.timer (every 6h) and
# brew-upgrade.timer (every 8h). On the previous base these were inert because
# brew-proxy broke them; dropping brew-proxy revives them, which would give us
# three brew update paths counting uupd's brew module. uupd is the single
# updater, so disable them explicitly -- 01-homebrew.preset sorts before ours,
# so a preset line alone would not win.
systemctl disable brew-update.timer brew-upgrade.timer

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
    brew-setup.service \
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
