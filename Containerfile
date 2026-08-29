# Personal Fedora bootc workstation.
#
# Built on ublue base-main rather than an opinionated desktop base: it ships
# Fedora with the codec stack, brew's sudoers path and flathub already sorted,
# has release discipline (release-please, a CHANGELOG, dated tags), and adds no
# compositor or greeter of its own -- so there is nothing to strip before
# adding niri and DankMaterialShell.
#
# Pin BASE_DIGEST, not just BASE_TAG. It pins the kernel, systemd, mesa and the
# whole negativo17 codec stack in one go, which is the overwhelming majority of
# this image by bytes and the only pin available that actually holds: the
# desktop stack comes from COPRs that prune superseded builds, so versionlock
# to an older NEVRA is impossible there. Bisectability via the NEVRA manifest
# in cleanup.sh is the substitute for pinning the parts that float.
ARG BASE_IMAGE=ghcr.io/ublue-os/base-main
ARG BASE_TAG=latest

# Build inputs travel in a scratch stage and are bind-mounted, never COPYd, so
# they cannot end up in a layer of the shipped image. This is base-main's own
# pattern.
FROM scratch AS ctx
COPY build_files /build_files
COPY packages    /packages
COPY repos       /repos
COPY src         /src

# Everything that is not packaged, compiled once into /staging. One builder
# stage rather than three: the compiler is pulled in once and the layer is
# discarded wholesale, so uninstalling build deps afterwards is wasted time.
FROM ${BASE_IMAGE}:${BASE_TAG} AS toolchain
ARG KEYD_VERSION=2.6.0
ARG KEYD_SHA256=697089681915b89d9e98caf93d870dbd4abce768af8a647d54650a6a90744e26
ARG FIRACODE_VERSION=3.5.1
ARG FIRACODE_SHA256=68e3bd6164864b8b514605bc34e3a87ac401c8c48682fcce6478c70263340207
RUN --mount=type=bind,from=ctx,src=/,dst=/ctx \
    --mount=type=cache,target=/var/cache/libdnf5,sharing=locked \
    --mount=type=tmpfs,dst=/tmp \
    KEYD_VERSION="${KEYD_VERSION}" KEYD_SHA256="${KEYD_SHA256}" \
    FIRACODE_VERSION="${FIRACODE_VERSION}" FIRACODE_SHA256="${FIRACODE_SHA256}" \
    /ctx/build_files/toolchain.sh

FROM ${BASE_IMAGE}:${BASE_TAG}

LABEL org.opencontainers.image.source="https://github.com/marcortola/workstation-os-image"
LABEL org.opencontainers.image.description="Personal Fedora bootc image with host-integrated tools"

# Repositories and packages in one cached unit -- the most expensive and most
# stable part of the build.
RUN --mount=type=bind,from=ctx,src=/,dst=/ctx \
    --mount=type=cache,target=/var/cache/libdnf5,sharing=locked \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build_files/repos.sh && /ctx/build_files/packages.sh

# Homebrew payload: the tarball, brew-setup/update/upgrade units and the preset.
# Before the rootfs overlay so our own files win on any collision. brew is
# never run during the build; brew-setup.service unpacks it on first boot.
COPY --from=ghcr.io/ublue-os/brew:latest /system_files/ /

COPY --from=toolchain /staging/ /

COPY rootfs/ /

RUN --mount=type=bind,from=ctx,src=/,dst=/ctx \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build_files/desktop.sh && \
    /ctx/build_files/services.sh && \
    /ctx/build_files/cleanup.sh && \
    /ctx/build_files/check-build.sh

RUN ["bootc", "container", "lint"]
