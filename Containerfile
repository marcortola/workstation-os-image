# Personal Fedora bootc workstation.
#
# Built on ublue base-main rather than an opinionated desktop base: it ships
# Fedora with the codec stack, brew's sudoers path and flathub already sorted,
# has release discipline (release-please, a CHANGELOG, dated tags), and adds no
# compositor or greeter of its own -- so there is nothing to strip before
# adding niri and DankMaterialShell.
#
# Pin the base by digest, not just by tag. The digest pins the kernel, systemd,
# mesa and the whole negativo17 codec stack in one go -- the overwhelming
# majority of this image by bytes, and the only pin available that actually
# holds: the desktop stack comes from COPRs that prune superseded builds, so
# versionlock to an older NEVRA is impossible there. Bisectability via the NEVRA
# manifest in 90-cleanup.sh is the substitute for pinning the parts that float.
#
# One knob holding a full image reference -- the same shape the CI repository
# variable and the Justfile pass. Splitting it into image + tag invited
# `${BASE_IMAGE}:${BASE_TAG}` to become `...:latest:latest` the moment CI passed
# a tagged reference, which is exactly what happened.
#
# tooling/validate/source-images cosign-verifies both pinned digests against
# ublue's public key before any build runs. This one is bumped by Renovate
# (.github/renovate.json5); Dependabot's docker parser only reads literal FROM
# lines, so it maintains the brew stage below and never sees this ARG.
ARG BASE_IMAGE=ghcr.io/ublue-os/base-main:latest@sha256:9b43dba0dea1987005cbf8cbc64727564b40ec5a162f7c51e3c6f7f36b6d3863

# build_files travels in a scratch stage and is bind-mounted, never COPYd, so
# the scripts and their data cannot end up in a layer of the shipped image.
# This is base-main's own pattern.
#
# system_files is deliberately NOT in here: it has a single source and needs
# no merge, so it is COPYd straight to / below. Putting it in ctx would also
# re-key the package layer on every overlay edit, because a bind mount from a
# stage keys on the stage result rather than on the files actually read.
FROM ghcr.io/ublue-os/brew:latest@sha256:bed056871da6edd8c6ee455a274283ae83bf269461dcad758a7729aaad018401 AS brew

FROM scratch AS ctx
COPY build_files /build_files

# Everything that is not packaged, compiled once into /staging. One builder
# stage rather than three: the compiler is pulled in once and the layer is
# discarded wholesale, so uninstalling build deps afterwards is wasted time.
FROM ${BASE_IMAGE} AS toolchain
ARG KEYD_VERSION=2.6.0
ARG KEYD_SHA256=697089681915b89d9e98caf93d870dbd4abce768af8a647d54650a6a90744e26
ARG FIRACODE_VERSION=3.5.1
ARG FIRACODE_SHA256=68e3bd6164864b8b514605bc34e3a87ac401c8c48682fcce6478c70263340207
RUN --mount=type=bind,from=ctx,src=/,dst=/ctx \
    --mount=type=cache,target=/var/cache/libdnf5,sharing=locked \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build_files/00-toolchain.sh

FROM ${BASE_IMAGE}

# Identity comes from image.env, the single place a fork edits. It is also
# COPYd below so runtime consumers resolve the same values.
ARG IMAGE_NAME=workstation-os-image
ARG REPO_ORGANIZATION=marcortola
ARG IMAGE_DESC="Personal Fedora bootc image with host-integrated tools"
LABEL org.opencontainers.image.title="${IMAGE_NAME}"
LABEL org.opencontainers.image.description="${IMAGE_DESC}"
LABEL org.opencontainers.image.vendor="${REPO_ORGANIZATION}"
LABEL org.opencontainers.image.source="https://github.com/${REPO_ORGANIZATION}/${IMAGE_NAME}"
LABEL org.opencontainers.image.url="https://github.com/${REPO_ORGANIZATION}/${IMAGE_NAME}"
LABEL org.opencontainers.image.licenses="MIT"

# Repositories and packages in one cached unit -- the most expensive and most
# stable part of the build.
#
# 25-rpmdb.sh belongs to this RUN and not to the cleanup chain below: it hard
# links the rpm-ostree base rpmdb onto the real one, and `ln -f` across a layer
# boundary makes overlayfs copy the whole 90 MB database up into whichever layer
# runs it.
RUN --mount=type=bind,from=ctx,src=/,dst=/ctx \
    --mount=type=cache,target=/var/cache/libdnf5,sharing=locked \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build_files/10-repos.sh && /ctx/build_files/20-packages.sh && \
    /ctx/build_files/25-rpmdb.sh

# Homebrew payload: the tarball, brew-setup/update/upgrade units and the preset.
# Before the system_files overlay so our own files win on any collision. brew is
# never run during the build; brew-setup.service unpacks it on first boot.
#
# A named stage rather than `COPY --from=<image>`: dependabot updates FROM
# lines and cannot see an image reference buried in a COPY.
COPY --from=brew /system_files/ /

COPY --from=toolchain /staging/ /

COPY system_files/ /
COPY image.env /usr/share/workstation-os-image/image.env

# --network=none: every script in this chain works from the overlay and the
# ctx mount. Making the cut structural means the day someone adds a fetch here
# it fails in the build rather than becoming an unpinned input nobody notices.
RUN --network=none \
    --mount=type=bind,from=ctx,src=/,dst=/ctx \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build_files/30-desktop.sh && \
    /ctx/build_files/40-signing.sh && \
    /ctx/build_files/50-services.sh && \
    /ctx/build_files/60-metadata.sh && \
    /ctx/build_files/90-cleanup.sh && \
    /ctx/build_files/99-check-build.sh

# The sweep cannot live in 90-cleanup.sh: 99-check-build.sh runs systemd-analyze
# immediately after it and recreates /run/systemd, so the last write to /run has
# to be here, in the layer the lint actually reads.
RUN --network=none rm -rf /run/systemd && \
    bootc container lint --fatal-warnings
