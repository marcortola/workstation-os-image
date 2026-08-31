#!/usr/bin/bash
# Session: greetd, the greeter, PAM, and session-wide environment.
set -ouex pipefail

# --- PAM: keyring unlock at login ---------------------------------------
# Fedora ships pam_gnome_keyring with a leading '-' on the type field, which
# only suppresses a warning when the module is missing; it does not change the
# 'optional' control. Zirconium sed'd the dashes off, so we do too for parity,
# but unguarded -- as upstream had it -- a Fedora reformat silently turns this
# into a no-op. 99-check-build.sh asserts the result instead of trusting it.
#
# /usr/lib/pam.d/ is NOT usable here: PAM searches /etc/pam.d first and the
# greetd RPM owns /etc/pam.d/greetd, so a /usr drop-in would be inert.
sed -i -E '/pam_gnome_keyring\.so/ s/^-(auth|session)/\1/' /etc/pam.d/greetd

# --- default target ------------------------------------------------------
# base-main already points default.target at graphical.target, so this is a
# no-op today. Kept explicit because greetd's only [Install] directive is
# Alias=display-manager.service, which graphical.target is what pulls in; if a
# future base ships a headless default, the greeter would simply never start.
ln -snf graphical.target /usr/lib/systemd/system/default.target

# --- launcher hygiene ----------------------------------------------------
# Three RPM-owned entries reach the DMS launcher without being applications a
# person can usefully start: btop is a TUI with no terminal of its own,
# foot-server is a daemon, and fcitx5 runs as a user unit. Every other fcitx5
# entry already ships NoDisplay=true; these three do not.
#
# Removal rather than `desktop-file-edit --set-key=NoDisplay`: none of the three
# carries metadata worth keeping -- btop's window belongs to whichever terminal
# spawned it, and the other two never map a window at all. Asserting each one
# was there first keeps a Fedora rename from turning this into silent dead code.
for entry in btop.desktop foot-server.desktop org.fcitx.Fcitx5.desktop; do
    test -f "/usr/share/applications/$entry" \
        || { echo "expected desktop entry is gone: $entry" >&2; exit 1; }
    rm -f "/usr/share/applications/$entry"
done

# --- font cache ----------------------------------------------------------
# 00-toolchain.sh drops FiraCode Nerd Font into /usr/share/fonts, but fontconfig
# only sees a font once its cache has been rebuilt, so without this fc-list
# finds nothing and every consumer silently falls back to a default monospace.
fc-cache --force --really-force --system-only
