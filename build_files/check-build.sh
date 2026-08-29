#!/usr/bin/bash
# Build-time gates. Mutates nothing.
#
# The existing checks verify that files parse. These verify that the build's
# DECISIONS took effect -- which repo a package came from, whether a preset
# actually enabled a unit, whether a sed matched anything. That is where silent
# regressions live, and none of it is visible to `bootc container lint`.
set -ouex pipefail

# NOTE: never use `grep -q` in a pipeline here. It exits on the first match,
# SIGPIPEs the writer, and `pipefail` turns that into a non-zero pipeline --
# so the gate fails precisely when the thing it checks for IS present.
# Use `grep ... >/dev/null`, which reads the whole stream.

fail() { echo "check-build: $*" >&2; exit 1; }

# --- packages present ----------------------------------------------------
for p in \
    niri xwayland-satellite greetd greetd-selinux foot fish chezmoi \
    dms dms-cli dms-greeter quickshell dgop danksearch matugen \
    gnome-keyring gnome-keyring-pam gcr nautilus tesseract \
    plasma-breeze kf6-qqc2-desktop-style kf6-kirigami kf6-kimageformats \
    qt6-qtimageformats qt6-qtmultimedia qt6-qtdeclarative \
    uupd satty iio-niri \
    docker-ce containerd.io \
    pipewire wireplumber systemd firewalld accountsservice
do
    rpm -q "$p" >/dev/null || fail "missing package: $p"
done

# --- vendor assertions ---------------------------------------------------
# The includepkgs regression guard. On the previous base, Terra shipped
# sdbus-cpp.terra and it satisfied libsdbus-c++.so.2 for dnf5 itself -- a
# third-party repo replaced a library the package manager links against. These
# assertions turn a recurrence into a failed build instead of a mystery.
assert_vendor() {
    local pkg="$1" want="$2" got
    got="$(rpm -q --qf '%{VENDOR}' "$pkg")"
    [[ "$got" =~ $want ]] || fail "$pkg came from '$got', expected /$want/"
}
assert_vendor niri       'yalter'
assert_vendor dms        'avengemedia'
assert_vendor quickshell 'avengemedia'
assert_vendor uupd       'Terra'
assert_vendor systemd    'Fedora Project'
assert_vendor dnf5       'Fedora Project'
rpm -q libavcodec-freeworld >/dev/null 2>&1 \
    && fail "libavcodec-freeworld is installed: RPM Fusion is meant to be gone and it file-conflicts with negativo17's libavcodec"

# --- niri parses ---------------------------------------------------------
# A transcription error in the vendored includes produces a subtly wrong
# desktop that still boots, so parse both chains here.
niri validate -c /etc/greetd/niri/config.kdl
niri validate -c /usr/share/workstation-os-image/niri/workstation.kdl

# --- greetd chain --------------------------------------------------------
grep -q 'dms-greeter --command niri' /etc/greetd/config.toml \
    || fail "greetd config does not launch dms-greeter"
grep -q 'user = "greeter"' /etc/greetd/config.toml || fail "greetd greeter user not set"
grep -q 'DMS_RUN_GREETER' /etc/greetd/niri/config.kdl || fail "greeter niri config missing DMS_RUN_GREETER"
grep -Eq '^u!?[[:space:]]+greeter' /usr/lib/sysusers.d/dms-greeter.conf \
    || fail "greeter sysusers entry missing"

# --- PAM keyring ---------------------------------------------------------
# The sed in desktop.sh is unguarded, exactly as upstream had it. Upstream
# would silently no-op if Fedora reformatted the file; this fails the build.
grep -Eq '^auth[[:space:]]+optional[[:space:]]+pam_gnome_keyring\.so' /etc/pam.d/greetd \
    || fail "pam_gnome_keyring auth line not normalised"
grep -Eq '^session[[:space:]]+optional[[:space:]]+pam_gnome_keyring\.so' /etc/pam.d/greetd \
    || fail "pam_gnome_keyring session line not normalised"
grep -q '^-.*pam_gnome_keyring' /etc/pam.d/greetd \
    && fail "a dashed pam_gnome_keyring line survived the sed"
# The genuinely load-bearing half: the leading '-' only suppresses a
# missing-module warning, so what actually unlocks the keyring is the module
# being installed at all.
test -e /usr/lib64/security/pam_gnome_keyring.so || fail "pam_gnome_keyring.so absent"

# --- preset effects ------------------------------------------------------
# Highest-value class here: preset composition is where regressions hide, and
# a preset file cannot undo an enablement symlink another layer already wrote.
readlink /etc/systemd/system/display-manager.service | grep greetd.service >/dev/null \
    || fail "greetd is not the display manager"
test -L /etc/systemd/system/timers.target.wants/uupd.timer || fail "uupd.timer not enabled"
for t in rpm-ostreed-automatic.timer flatpak-system-update.timer; do
    test -e "/etc/systemd/system/timers.target.wants/$t" \
        && fail "$t is still enabled and will race uupd"
done
test -e /etc/systemd/user/timers.target.wants/flatpak-user-update.timer \
    && fail "flatpak-user-update.timer is still enabled and will race uupd"
test -L /etc/systemd/user/graphical-session.target.wants/dms.service || fail "dms.service not enabled"
readlink /usr/lib/systemd/system/default.target | grep graphical.target >/dev/null \
    || fail "default.target is not graphical.target"

# --- unit syntax ---------------------------------------------------------
systemd-analyze verify \
    /usr/lib/systemd/system/workstation-*.service \
    /usr/lib/systemd/user/workstation-*.service \
    /usr/lib/systemd/user/workstation-*.timer \
    /usr/lib/systemd/user/fcitx5.service \
    /usr/lib/systemd/user/iio-niri.service \
    /usr/lib/systemd/user/udiskie.service \
    /usr/lib/systemd/user/dsearch.service

# Catches a malformed L/d line, which otherwise silently does nothing at boot
# -- the exact failure mode of the previous base's greeter tmpfiles.
systemd-tmpfiles --dry-run --create >/dev/null
systemd-sysusers --dry-run >/dev/null

# --- greeter symlink targets exist ---------------------------------------
for f in settings.json session.json dms-colors.json; do
    test -f "/usr/share/workstation-os-image/greeter/$f" || fail "greeter default $f missing"
done

# --- Homebrew ------------------------------------------------------------
test -s /usr/share/homebrew.tar.zst || fail "homebrew payload missing"
test -f /usr/lib/systemd/system/brew-setup.service || fail "brew-setup.service missing"

# --- fonts ---------------------------------------------------------------
# fonts.conf and the DMS mono font setting both name this family. It was
# shipped by no image before, resolving from an untracked ~/.local/share/fonts.
if ! fc-list | grep 'FiraCode Nerd Font Mono' >/dev/null; then
    echo "--- font diagnostics ---" >&2
    ls -la /usr/share/fonts/ >&2 || true
    find /usr/share/fonts/firacode-nerd-fonts/ -type f -printf '%f\n' 2>&1 | head -5 >&2 || true
    echo "fc-list entries: $(fc-list | wc -l)" >&2
    fc-list | grep -i fira >&2 || echo "(no fira in fc-list)" >&2
    fail "FiraCode Nerd Font Mono not installed"
fi

# --- config validators ---------------------------------------------------
dockerd --validate --config-file=/usr/share/factory/etc/docker/daemon.json
keyd check /usr/share/factory/etc/keyd/default.conf

# --- namespace -----------------------------------------------------------
# Scoped to files this image owns. Third-party packages are not our problem:
# DMS's own SystemLogo.qml hardcodes a Zirconium logo path, but it is guarded
# on $LOGO from os-release, which is "fedora" here, so that branch is dead.
#
# Attribution prose is fine. So is the single deliberate reference to the
# legacy per-user chezmoi dir in workstation-chezmoi-apply, which is the
# migration source -- hence matching the image tree path specifically.
stale=$(grep -rlI '/usr/share/zirconium' \
    /usr/share/workstation-os-image /usr/libexec /etc/greetd \
    /usr/lib/systemd /usr/lib/tmpfiles.d 2>/dev/null || true)
if [ -n "$stale" ]; then
    echo "$stale" >&2
    fail "a reference to the removed /usr/share/zirconium tree survived into image-owned files"
fi
test ! -e /usr/share/zirconium || fail "/usr/share/zirconium still exists in the image"

echo "check-build: all gates passed"
