ARG BASE_IMAGE=ghcr.io/zirconium-dev/zirconium:latest
FROM ${BASE_IMAGE} AS workstation-x11-clipsync-builder

COPY system_files/usr/src/workstation-x11-clipsync.c /usr/src/workstation-x11-clipsync.c

RUN dnf -y install --setopt=install_weak_deps=False \
      libX11-devel \
      libXfixes-devel && \
    gcc -O2 -Wall -Wextra \
      -o /usr/libexec/workstation-x11-clipsync \
      /usr/src/workstation-x11-clipsync.c \
      -lX11 -lXfixes && \
    dnf -y remove libX11-devel libXfixes-devel && \
    dnf clean all && \
    rm -rf /var/cache/libdnf5 /var/lib/dnf

FROM ${BASE_IMAGE} AS keyd-builder

# keyd (keyboard remapper) is not packaged in Fedora, and the Zirconium base
# dropped the Terra repo that used to provide it, so build it from pinned
# upstream source. Only the daemon, its unit, and its sysusers group are kept;
# the docs/man/layouts that `make install` would add are intentionally omitted.
ARG KEYD_VERSION=2.6.0
ARG KEYD_SHA256=697089681915b89d9e98caf93d870dbd4abce768af8a647d54650a6a90744e26
RUN curl -fsSL -o /tmp/keyd.tar.gz \
      "https://github.com/rvaiya/keyd/archive/refs/tags/v${KEYD_VERSION}.tar.gz" && \
    echo "${KEYD_SHA256}  /tmp/keyd.tar.gz" > /tmp/keyd.sha256 && \
    sha256sum -c /tmp/keyd.sha256 && \
    tar -xzf /tmp/keyd.tar.gz -C /tmp && \
    make -C "/tmp/keyd-${KEYD_VERSION}" COMMIT="v${KEYD_VERSION}" PREFIX=/usr && \
    install -Dm755 "/tmp/keyd-${KEYD_VERSION}/bin/keyd" /staging/usr/bin/keyd && \
    sed 's#@PREFIX@#/usr#' "/tmp/keyd-${KEYD_VERSION}/keyd.service.in" \
      > /tmp/keyd.service && \
    install -Dm644 /tmp/keyd.service \
      /staging/usr/lib/systemd/system/keyd.service && \
    install -Dm644 "/tmp/keyd-${KEYD_VERSION}/data/sysusers.d" \
      /staging/usr/lib/sysusers.d/keyd.conf

FROM ${BASE_IMAGE}

LABEL org.opencontainers.image.source="https://github.com/marcortola/workstation-os-image"
LABEL org.opencontainers.image.description="Personal Fedora bootc image with host-integrated tools"

COPY system_files/etc/yum.repos.d/insync.repo /etc/yum.repos.d/insync.repo

RUN rpm --import https://d2t3ff60b2tol4.cloudfront.net/repomd.xml.key && \
    dnf -y install \
      https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm \
      https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm && \
    dnf -y config-manager addrepo \
      --from-repofile=https://download.docker.com/linux/fedora/docker-ce.repo && \
    dnf -y install --allowerasing --setopt=install_weak_deps=False \
      cabextract \
      containerd.io \
      cpio \
      docker-buildx-plugin \
      docker-ce \
      docker-ce-cli \
      docker-compose-plugin \
      ffmpeg \
      fish \
      fontconfig \
      gstreamer1-plugins-ugly \
      insync \
      libavcodec-freeworld \
      mkcert \
      shadow-utils \
      slurp \
      unrar \
      unzip \
      wf-recorder && \
    dnf clean all && \
    rm -rf /var/cache/libdnf5 /var/lib/dnf

COPY system_files/ /
COPY --from=workstation-x11-clipsync-builder \
  /usr/libexec/workstation-x11-clipsync \
  /usr/libexec/workstation-x11-clipsync
COPY --from=keyd-builder /staging/ /

RUN /usr/libexec/workstation-patch-zdots && \
    dockerd --validate \
      --config-file=/usr/share/factory/etc/docker/daemon.json && \
    keyd check /usr/share/factory/etc/keyd/default.conf && \
    systemd-analyze verify \
      /usr/lib/systemd/system/workstation-brew-trust.service \
      /usr/lib/systemd/system/workstation-user-groups.service \
      /usr/lib/systemd/user/workstation-bootstrap.service \
      /usr/lib/systemd/user/workstation-claude-mcp-seed.service \
      /usr/lib/systemd/user/workstation-dms-settings.service \
      /usr/lib/systemd/user/workstation-flatpak-wayland.service \
      /usr/lib/systemd/user/workstation-invoice-bookmarks.service \
      /usr/lib/systemd/user/workstation-microsoft-fonts.service \
      /usr/lib/systemd/user/workstation-x11-clipsync.service \
      /usr/lib/systemd/user/dcal.service \
      /usr/lib/systemd/user/dsearch.service && \
    systemctl preset containerd.service docker.service keyd.service \
      workstation-brew-trust.service workstation-user-groups.service && \
    systemctl --global preset dcal.service dsearch.service \
      workstation-bootstrap.service \
      workstation-claude-mcp-seed.service \
      workstation-dms-settings.service \
      workstation-flatpak-wayland.service \
      workstation-invoice-bookmarks.timer \
      workstation-microsoft-fonts.service \
      workstation-x11-clipsync.service && \
    rm -rf /run/dnf /run/systemd/systemd-units-load && \
    find /tmp -mindepth 1 -delete && \
    rm -rf \
      /var/cache/ldconfig \
      /var/cache/libdnf5 \
      /var/lib/dnf \
      /var/log/dnf5.log && \
    bootc container lint
