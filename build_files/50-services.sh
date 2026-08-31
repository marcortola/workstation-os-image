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

# Fedora enables dnf-makecache.timer and base-main leaves it that way. Nothing
# installs from dnf at runtime on an image-mode system, so it is pure wakeups
# against repos we never read. Again a real /etc symlink, so the preset line
# alone cannot undo it.
systemctl disable dnf-makecache.timer

# getty@tty1 stays enabled on purpose. greetd carries
# Conflicts=getty@tty1.service so it is displaced at runtime, and it is the
# only escape hatch if the greeter fails to start.

# Named units, never `preset-all`: base-main configured units deliberately and
# re-evaluating all of them would undo that.
#
# The names come from the preset files themselves rather than a second list
# here. They used to be two copies of the same intent with nothing keeping them
# in sync, so a unit added to a preset and forgotten here would ship, pass
# systemd-analyze verify, and simply never be enabled. tooling/audit/units reads
# the same two files as its manifest, so all three now agree by construction.
system_preset=/usr/lib/systemd/system-preset/10-workstation-os-image.preset
user_preset=/usr/lib/systemd/user-preset/10-workstation-os-image.preset
for f in "$system_preset" "$user_preset"; do
    # An empty list would silently enable nothing at all.
    test -f "$f" || { echo "preset file is missing: $f" >&2; exit 1; }
done

mapfile -t system_units < <(sed -n 's/^enable //p' "$system_preset")
mapfile -t user_units < <(sed -n 's/^enable //p' "$user_preset")
(( ${#system_units[@]} && ${#user_units[@]} )) \
    || { echo "a preset file yielded no enable lines" >&2; exit 1; }

systemctl preset "${system_units[@]}"
systemctl --global preset "${user_units[@]}"
