#!/usr/bin/bash
# Session: greetd, the greeter, PAM, and session-wide environment.
set -ouex pipefail

# --- PAM: keyring unlock at login ---------------------------------------
# Fedora ships pam_gnome_keyring with a leading '-' on the type field, which
# only suppresses a warning when the module is missing; it does not change the
# 'optional' control. Zirconium sed'd the dashes off, so we do too for parity,
# but unguarded -- as upstream had it -- a Fedora reformat silently turns this
# into a no-op. check-build.sh asserts the result instead of trusting it.
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

# --- font cache ----------------------------------------------------------
# toolchain.sh drops FiraCode Nerd Font into /usr/share/fonts, but fontconfig
# only sees a font once its cache has been rebuilt, so without this fc-list
# finds nothing and every consumer silently falls back to a default monospace.
fc-cache --force --really-force --system-only

# --- OCR -----------------------------------------------------------------
# binds.kdl calls this on Mod+Print and Mod+Alt+Shift+S. It replaces
# Zirconium's /usr/bin/zocr, which disappears with that base. niri validate
# does not check that a spawn target exists, so losing this would be silent.
install -Dm755 /ctx/build_files/workstation-ocr /usr/bin/workstation-ocr
