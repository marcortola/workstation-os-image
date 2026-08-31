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

# Every gate below that reads a file through process substitution needs this
# first. `while read ... done < <(sed FILE)` on a missing FILE iterates zero
# times and passes, so a rename silently disarms the check instead of
# breaking it -- exactly how the image/ restructure disabled two gates in
# tooling/validate without anything going red.
require_file() { test -f "$1" || fail "gate input is missing: $1"; }

# --- packages present ----------------------------------------------------
for p in \
    niri xwayland-satellite greetd greetd-selinux foot fish chezmoi \
    dms dms-cli dms-greeter quickshell dgop danksearch matugen \
    gnome-keyring gnome-keyring-pam gcr nautilus tesseract \
    plasma-breeze kf6-qqc2-desktop-style kf6-kirigami kf6-kimageformats \
    qt6-qtimageformats qt6-qtmultimedia qt6-qtdeclarative \
    uupd satty iio-niri \
    tuned tuned-ppd xdg-user-dirs \
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

# --- cross-package version cohesion --------------------------------------
# dms and dms-cli come from copr:avengemedia/dms; dms-greeter comes from
# copr:avengemedia/danklinux. They are released together but published to two
# separate COPRs, so a half-finished publish hands us dms at N and dms-greeter
# at N-1. Nothing else here would notice: assert_vendor only checks WHERE a
# package came from, and the desktop stack floats by design because COPR prunes
# superseded builds, so there is no version to pin it to.
#
# This is the most likely silent breakage in the whole image -- a shell that
# starts and then misbehaves, rather than a build that fails.
cohort_version=""
for p in dms dms-cli dms-greeter; do
    v="$(rpm -q --qf '%{VERSION}' "$p")"
    if [ -z "$cohort_version" ]; then
        cohort_version="$v"
    elif [ "$v" != "$cohort_version" ]; then
        echo "--- DMS stack versions ---" >&2
        rpm -q --qf '%{NAME} %{VERSION}-%{RELEASE} (%{VENDOR})\n' dms dms-cli dms-greeter >&2
        fail "DMS stack version skew: $p is $v, expected $cohort_version.
This usually means copr:avengemedia/dms and copr:avengemedia/danklinux are
mid-publish. Re-run the build once both have caught up."
    fi
done

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
# The sed in 30-desktop.sh is unguarded, exactly as upstream had it. Upstream
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
test -e /etc/systemd/system/timers.target.wants/rpm-ostreed-automatic.timer \
    && fail "rpm-ostreed-automatic.timer is still enabled and will race uupd"
# The flatpak update timers came from ublue-os-update-services. Asserting the
# package is absent is stronger than asserting its symlinks are: the package
# ships enable-at-priority-10 presets that would re-create them.
rpm -q ublue-os-update-services >/dev/null \
    && fail "ublue-os-update-services is installed; its presets re-enable the flatpak timers"
for t in brew-update.timer brew-upgrade.timer; do
    test -e "/etc/systemd/system/timers.target.wants/$t" \
        && fail "$t is still enabled; uupd is the single brew updater"
done
test -e /etc/systemd/system/timers.target.wants/dnf-makecache.timer \
    && fail "dnf-makecache.timer is still enabled; nothing installs from dnf at runtime"

test -L /etc/systemd/user/graphical-session.target.wants/dms.service || fail "dms.service not enabled"

# --- every preset `enable` line actually took effect ------------------------
# The preset files and the explicit `systemctl enable` argument lists in
# 50-services.sh are two copies of the same intent with nothing keeping them in
# sync. A unit added to a preset and forgotten in the script ships, passes
# systemd-analyze verify, and is simply never enabled -- silently. Asserting the
# effect rather than the arguments also catches a preset line naming a unit that
# does not exist at all.
#
# Matched by link target OR link name. Target, because greetd.service is
# enabled through its Alias=display-manager.service and produces no .wants
# entry at all. Name, because an instantiated template links to foo@.service,
# so a target-only match would miss `enable foo@bar.service` and fail with a
# message asserting the opposite of the truth.
require_file /usr/lib/systemd/system-preset/10-workstation-os-image.preset
while read -r unit; do
    find /etc/systemd/system -type l \( -lname "*/$unit" -o -name "$unit" \) \
        | grep . >/dev/null \
        || fail "system preset enables $unit but nothing links to it under /etc"
done < <(sed -n 's/^enable //p' \
    /usr/lib/systemd/system-preset/10-workstation-os-image.preset)

require_file /usr/lib/systemd/user-preset/10-workstation-os-image.preset
while read -r unit; do
    find /etc/systemd/user -type l \( -lname "*/$unit" -o -name "$unit" \) \
        | grep . >/dev/null \
        || fail "user preset enables $unit but nothing links to it under /etc"
done < <(sed -n 's/^enable //p' \
    /usr/lib/systemd/user-preset/10-workstation-os-image.preset)
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

# --- greeter theme links are image-owned and replaceable ------------------
# Derived from the tmpfiles file rather than a second hardcoded list, so the two
# cannot disagree. The type matters as much as the target: plain L creates only
# if absent, which leaves whatever `dms greeter sync` last pointed at in place --
# and that was a user-owned file DMS later rewrote as 0600, which killed the
# greeter under `set -e` with no log at all.
greeter_tmpfiles=/usr/lib/tmpfiles.d/99-workstation-dms-greeter.conf
require_file "$greeter_tmpfiles"
greeter_links=0
while read -r ltype lpath _ _ _ _ ltarget; do
    case "$lpath" in /var/cache/dms-greeter/*) ;; *) continue ;; esac
    greeter_links=$(( greeter_links + 1 ))
    [[ $ltype == "L+" ]] \
        || fail "greeter link $lpath is '$ltype', not L+; a runtime repoint would outlive the image"
    test -f "$ltarget" || fail "greeter link $lpath points at a missing $ltarget"
done < <(grep -E '^L' "$greeter_tmpfiles")
(( greeter_links == 4 )) \
    || fail "expected 4 greeter theme links in $greeter_tmpfiles, matched $greeter_links"

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

# Cambria is deliberately not installed -- see workstation-install-microsoft-fonts.
# Caladea stands in for it, so gate the whole substitution and not just the
# package: the font files, the alias rule that maps the Cambria family name, and
# the resolution that rule is there to produce.
rpm -q google-crosextra-caladea-fonts >/dev/null \
    || fail "Caladea is missing; Cambria has no metric-compatible substitute"
require_file /etc/fonts/conf.d/30-0-google-crosextra-caladea-fonts.conf
fc-list | grep 'Caladea' >/dev/null || fail "Caladea is installed but fc-list does not see it"
fc-match Cambria | grep 'Caladea' >/dev/null \
    || fail "Cambria does not resolve to Caladea: $(fc-match Cambria)"

# --- every niri spawn target resolves ------------------------------------
require_file /usr/share/workstation-os-image/niri/includes/binds.kdl
# `niri validate` parses the config but never checks that a spawned binary
# exists, so a bind pointing at a removed program stays silent until the key is
# pressed. This is how `spawn "zocr"` survived the base swap.
while read -r target; do
    [[ -z $target ]] && continue
    case "$target" in
        /*) test -x "$target" || fail "niri bind spawns a missing program: $target" ;;
        *)  command -v "$target" >/dev/null || fail "niri bind spawns a missing program: $target" ;;
    esac
done < <(grep -hoE 'spawn "[^"]+"' \
    /usr/share/workstation-os-image/niri/includes/*.kdl 2>/dev/null \
    | sed 's/spawn "//; s/"$//' | sort -u)

# --- signature verification is actually configured ------------------------
# Three pieces, and the third is the one that silently breaks the other two:
# a key, a policy entry that names it, and a registries.d entry telling
# containers/image to fetch the sigstore attachment at all.
# shellcheck source=/dev/null
source /usr/share/workstation-os-image/image.env
signing_scope="ghcr.io/${REPO_ORGANIZATION}"
test -f /etc/pki/containers/workstation-signing.pub || fail "signing pubkey missing"
grep -q 'BEGIN PUBLIC KEY' /etc/pki/containers/workstation-signing.pub || fail "signing pubkey is not a public key"

# The top-level default only. Every transport also carries a "" catch-all of
# insecureAcceptAnything, inherited from base-main and deliberately left alone:
# the docker one is what lets dev containers pull arbitrary images, and
# containers-storage is what makes `just build` output usable locally.
jq -e '.default[0].type == "reject"' /etc/containers/policy.json >/dev/null \
    || fail "policy.json default is not reject"
jq -e --arg scope "$signing_scope" '.transports.docker[$scope][0]
       | .type == "sigstoreSigned"
         and (.keyPaths | index("/etc/pki/containers/workstation-signing.pub") != null)' \
    /etc/containers/policy.json >/dev/null \
    || fail "policy.json does not require a signature for $signing_scope"
# Dropping ublue's entry would leave the machine unable to pull its own base.
jq -e '.transports.docker | has("ghcr.io/ublue-os")' /etc/containers/policy.json >/dev/null \
    || fail "policy.json lost the ublue-os entry"
# Resolve the key it names rather than assuming it. A base that moved or
# renamed this file breaks pulling any ublue image, including a rebase back to
# the base. Deliberately not pinning its hash: we do not control that key, so a
# legitimate rotation must not turn the build red.
while read -r p; do
    test -f "$p" || fail "policy.json points at a missing ublue key: $p"
done < <(jq -r '.transports.docker["ghcr.io/ublue-os"][0].keyPaths[]?,
                .transports.docker["ghcr.io/ublue-os"][0].keyPath? // empty' \
    /etc/containers/policy.json)
grep -q "^  ${signing_scope}:" /etc/containers/registries.d/workstation-signing.yaml \
    || fail "registries.d is not scoped to $signing_scope"
grep -q 'use-sigstore-attachments: true' /etc/containers/registries.d/workstation-signing.yaml \
    || fail "registries.d does not enable sigstore attachments; the signature would never be fetched"

# --- build-created accounts did not stay in /etc --------------------------
# base-main keeps /etc/passwd at the root line alone and /etc/group at root and
# wheel; scriptlets in our packages layer add four accounts between them.
# 90-cleanup.sh relocates those to /usr/lib. If that ever stops working they
# become machine-local /etc merge state on first boot, and a later uid change
# can no longer reach them.
if grep -vE '^root:' /etc/passwd >/dev/null; then
    grep -vE '^root:' /etc/passwd >&2
    fail "build-created accounts stayed in /etc/passwd"
fi
if grep -vE '^(root|wheel):' /etc/group >/dev/null; then
    grep -vE '^(root|wheel):' /etc/group >&2
    fail "build-created groups stayed in /etc/group"
fi
for u in greetd greeter wsdd; do
    grep -q "^$u:" /usr/lib/passwd || fail "account $u did not reach /usr/lib/passwd"
done
for g in greetd greeter wsdd docker; do
    grep -q "^$g:" /usr/lib/group || fail "group $g did not reach /usr/lib/group"
done
for f in /etc/.pwd.lock /etc/passwd- /etc/group- /etc/shadow- /etc/gshadow-; do
    test ! -e "$f" || fail "shadow-utils leftover shipped: $f"
done

# --- RPM trust anchors are vendored, not fetched --------------------------
# Vendoring the .repo files only put baseurl under review; the key that
# authenticates everything has to be on disk too. That the .repo files REFERENCE
# their key by file:// is asserted source-side in tooling/validate/image-build,
# because 90-cleanup.sh has already deleted them by the time this runs. What is
# still checkable here is that the keys themselves shipped.
#
# Scoped to the repos WE vendor. negativo17's repo file comes from base-main and
# still fetches its key over the network; we do not own that file, and rewriting
# a base-owned repo would collide with future base updates. The chain still has a
# defined root: base-main is digest-pinned and cosign-verified before we build on
# it, so that key is trusted transitively rather than unconditionally.
for k in copr-yalter-niri copr-avengemedia-dms copr-avengemedia-danklinux \
         terra docker-ce insync; do
    test -f "/etc/pki/rpm-gpg/$k.asc" || fail "vendored signing key missing: $k.asc"
done
# --- the shipped chezmoi source actually applies ---------------------------
# tooling/validate/repo dry-applies the source tree in the REPO. This proves the
# copy that shipped still applies, which is the only version the machine ever
# runs. Read-only: --dry-run into a throwaway HOME on the build's tmpfs.
# tooling/validate/image-build:75 exempts this file by name from the
# "no build step may touch the chezmoi source" rule, precisely so this can live
# here rather than only in CI.
test -d /usr/share/workstation-os-image/dotfiles \
    || fail "the chezmoi source tree did not ship"
HOME="$(mktemp -d)" chezmoi apply --dry-run --no-tty \
    -S /usr/share/workstation-os-image/dotfiles >/dev/null \
    || fail "the shipped chezmoi source does not apply cleanly"

# --- image identity reached os-release --------------------------------------
grep -q "^VARIANT_ID=${IMAGE_NAME}$" /usr/lib/os-release \
    || fail "VARIANT_ID in /usr/lib/os-release does not match image.env IMAGE_NAME"
# ID stays fedora on purpose; the niri/grub reasoning below depends on it.
grep -q '^ID=fedora$' /usr/lib/os-release || fail "os-release ID is no longer fedora"

# The OS name spans two files -- image.env declares it, 60-metadata.sh writes
# it -- so gate that they agree. A `sed` whose pattern stops matching a future
# base would otherwise leave the image calling itself "Fedora Linux" with
# nothing red.
grep -q "^NAME=\"${OS_NAME}\"$" /usr/lib/os-release \
    || fail "NAME in /usr/lib/os-release does not match image.env OS_NAME"
# PRETTY_NAME must carry the brand AND keep the base's per-deployment version,
# which is what the boot menu shows; a bare brand string would drop the only
# way to tell two entries apart.
grep -q "^PRETTY_NAME=\"${OS_NAME} .*[0-9]" /usr/lib/os-release \
    || fail "PRETTY_NAME is not '${OS_NAME} <version>'"
[ "$(grep -c '^NAME=' /usr/lib/os-release)" = 1 ] \
    || fail "/usr/lib/os-release carries more than one NAME= line"

# --- the update button's grant matches the command it runs -------------------
# The shell's updater command and the polkit rule that lets it run without a
# password are two halves of one mechanism in two files. If they drift, the
# button silently prompts for a password nobody can type into a GUI, which is
# the failure this replaced.
rule=/usr/share/polkit-1/rules.d/10-workstation-uupd.rules
test -f "$rule" || fail "the uupd polkit rule did not ship"
grep -q 'action.lookup("unit") == "uupd.service"' "$rule" \
    || fail "$rule no longer scopes to uupd.service"
grep -q 'action.lookup("verb") == "start"' "$rule" \
    || fail "$rule no longer scopes to the start verb"
# The seed is UI-owned after first boot, but what we SHIP must match the grant.
jq -e '.updaterCustomCommand == "systemctl start uupd.service"' \
    /usr/share/workstation-os-image/dms-settings.json >/dev/null \
    || fail "the DMS updater command does not match the unit the polkit rule grants"

# --- the base's compat symlinks survived every overlay ----------------------
# COPY lands each top-level path literally, and several of these are symlinks
# whose targets live outside /usr: /opt -> var/opt, /root -> var/roothome,
# /home -> var/home, /media -> run/media. A file shipped under any of them
# replaces the symlink with a real directory, and the content then lands in /var
# (written once at install, never on upgrade) or on a tmpfs. bootc container
# lint does not flag it, because the resulting path is legitimate.
#
# Asserted rather than prevented by construction, because no overlay mechanism
# prevents it: rsync --keep-dirlinks, which is what bluefin, aurora and main use
# instead of COPY, only preserves a symlink that resolves to an EXISTING
# directory -- and /var/opt does not exist on base-main, so their form clobbers
# it too. This also covers the two stage copies (COPY --from=brew,
# COPY --from=toolchain), which our own overlay allowlist would not.
for d in /opt /bin /sbin /lib /lib64 /media /root /home; do
    test -L "$d" \
        || fail "$d is a real directory; an overlay path under it replaced the base's compat symlink"
done

# --- the Terra key tracks the Fedora release the repo resolves to ------------
# terra.repo follows the release: `metalink=...repo=terra$releasever`. The key
# does not -- it is pinned to one release both in the URL
# (repos.fyralabs.com/terra44/key.asc) and in its own uid ("Terra 44"). The base
# is tagged :latest, so the day base-main moves to F45 the repo follows and the
# key does not, and nothing else in the repo would notice: renovate only manages
# the Containerfile, and the fingerprint check in tooling/validate/rpm-keys
# compares the key against the manifest, which would still agree with itself.
# shellcheck source=/dev/null
. /usr/lib/os-release
terra_release="$(GNUPGHOME="$(mktemp -d)" gpg --show-keys --with-colons \
    /etc/pki/rpm-gpg/terra.asc 2>/dev/null \
    | awk -F: '/^uid:/{print $10; exit}' | grep -oE '[0-9]+' | head -1)"
[ -n "$terra_release" ] || fail "could not read the Terra key uid"
[ "$terra_release" = "$VERSION_ID" ] \
    || fail "the Terra key is for Fedora $terra_release but this image is $VERSION_ID; re-vendor it from repos.fyralabs.com/terra${VERSION_ID}/key.asc and update build_files/keys/rpm-key-sources.json"

# --- every globally enabled third-party user unit skips system users ---------
# AGENTS.md: a user unit needs ConditionUser=!@system, or it also runs in the
# user manager pam_systemd creates for greetd's `greeter` account, whose home is
# read-only. Our own workstation-* units carry the condition inline; the RPM-owned
# ones we enable globally need a drop-in, and the drop-in is easy to forget
# because nothing fails loudly when it is missing -- xdg-user-dirs.service would
# just try to write the greeter's read-only home on every boot.
require_file /usr/lib/systemd/user-preset/10-workstation-os-image.preset
while read -r unit; do
    case "$unit" in workstation-*) continue ;; esac
    grep -rqs '^ConditionUser=!@system' "/usr/lib/systemd/user/$unit.d/" \
        || fail "user preset enables $unit but no drop-in gives it ConditionUser=!@system"
done < <(sed -n 's/^enable //p' \
    /usr/lib/systemd/user-preset/10-workstation-os-image.preset)

# --- the declared default terminal keeps the arguments the binds pass ---------
# The gate that would have caught the regression it now guards. Fedora's
# foot.desktop and footclient.desktop declare none of the Default Terminal
# Specification's X-TerminalArg* keys, so xdg-terminal-exec silently DROPS
# --app-id and --title: the herdr, dev-terminal and lazydocker binds all landed
# as app-id "foot", and the three matching desktop entries could never associate.
# Asserting which entry resolves is NOT enough -- that was the check that passed
# while the arguments were being thrown away. Assert the resulting command line.
#
# XDG_CONFIG_DIRS points at the factory copy because /etc/xdg/xdg-terminals.list
# is materialised by tmpfiles at boot and does not exist during the build.
require_file /usr/share/factory/etc/xdg/xdg-terminals.list
term_probe() {
    HOME=/root XDG_CONFIG_HOME=/nonexistent \
        XDG_CONFIG_DIRS=/usr/share/factory/etc/xdg \
        xdg-terminal-exec "$@"
}
term_id=$(term_probe --print-id -- /bin/true) \
    || fail "xdg-terminal-exec could not resolve a terminal"
test "$term_id" = workstation-footclient.desktop \
    || fail "default terminal resolved to $term_id, not workstation-footclient.desktop"
term_cmd=$(term_probe --print-cmd --app-id=probe-app --title=probe-title -- /bin/true)
for expected in footclient --app-id=probe-app --title=probe-title /bin/true; do
    printf '%s\n' "$term_cmd" | grep -Fxq -- "$expected" \
        || fail "the default terminal drops $expected; xdg-terminal-exec produced: $(echo "$term_cmd" | tr '\n' ' ')"
done

# --- launcher entries that are not applications are gone ---------------------
for entry in btop.desktop foot-server.desktop org.fcitx.Fcitx5.desktop; do
    test -e "/usr/share/applications/$entry" \
        && fail "$entry is back in the launcher; 30-desktop.sh should have removed it"
done
# The rest of the fcitx5 entries are hidden by Fedora rather than by us. If that
# ever changes they belong in the removal list above, so notice it here.
for entry in fcitx5-wayland-launcher org.fcitx.fcitx5-config-qt org.fcitx.fcitx5-qt6-gui-wrapper; do
    f="/usr/share/applications/$entry.desktop"
    test -e "$f" || continue
    grep -q '^NoDisplay=true' "$f" \
        || fail "$entry.desktop lost its NoDisplay=true and now pollutes the launcher"
done

# --- reinstalling this image reproduces this machine's filesystem ------------
# Without it `bootc install to-disk` refuses to run at all unless the operator
# remembers --filesystem, and the obvious guess is not what this workstation runs.
require_file /usr/lib/bootc/install/00-workstation.toml
grep -q '^type = "btrfs"' /usr/lib/bootc/install/00-workstation.toml \
    || fail "the bootc install default is no longer btrfs"

# --- input method and font rendering reach the graphical session -------------
# environment.d, not profile.d: the session is niri.service under the systemd
# user manager and never sources a login shell.
require_file /usr/lib/environment.d/50-workstation-input-method.conf
for v in QT_IM_MODULE=fcitx XMODIFIERS=@im=fcitx SDL_IM_MODULE=fcitx GLFW_IM_MODULE=fcitx; do
    grep -Fxq "$v" /usr/lib/environment.d/50-workstation-input-method.conf \
        || fail "$v is missing; fcitx5 is installed and enabled but XWayland and SDL clients cannot reach it"
done
grep -Fxq 'GTK_IM_MODULE=' /usr/lib/environment.d/50-workstation-input-method.conf \
    || fail "GTK_IM_MODULE must stay empty so GTK uses text-input-v3 rather than the legacy module"
require_file /usr/lib/environment.d/60-workstation-fonts.conf

# --- DMS cannot be talked into reinstalling the greeter ----------------------
# /etc/greetd/config.toml is image-owned and was clobbered by `dms greeter
# install` once already. dms reads this policy from /usr/share/dms first, which
# keeps /etc free for a local override.
require_file /usr/share/dms/cli-policy.json
for blocked in "greeter install" "greeter enable" "setup"; do
    jq -e --arg c "$blocked" '.blocked_commands | index($c)' \
        /usr/share/dms/cli-policy.json >/dev/null \
        || fail "the DMS CLI policy no longer blocks '$blocked'"
done

# --- config validators ---------------------------------------------------
dockerd --validate --config-file=/usr/share/factory/etc/docker/daemon.json
keyd check /usr/share/factory/etc/keyd/default.conf

# --- namespace -----------------------------------------------------------
# Scoped to files this image owns. Third-party packages are not our problem:
# DMS's own SystemLogo.qml hardcodes a Zirconium logo path, but it is guarded
# on $LOGO from os-release, which is "fedora-logo-icon" here, so that branch
# is dead.
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
