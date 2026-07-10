ARG BASE_IMAGE=ghcr.io/zirconium-dev/zirconium:latest
FROM ${BASE_IMAGE}

LABEL org.opencontainers.image.source="https://github.com/marcortola/workstation-os-image"
LABEL org.opencontainers.image.description="Personal Fedora bootc image with host-integrated tools"

COPY system_files/ /

RUN /usr/libexec/workstation-patch-zdots && \
    rpm --import https://d2t3ff60b2tol4.cloudfront.net/repomd.xml.key && \
    dnf -y install \
      https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm \
      https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm && \
    dnf -y config-manager addrepo \
      --from-repofile=https://download.docker.com/linux/fedora/docker-ce.repo && \
    dnf -y install --allowerasing \
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
      keyd \
      libavcodec-freeworld \
      mkcert \
      shadow-utils \
      slurp \
      unrar \
      unzip \
      wf-recorder && \
    dnf clean all && \
    dockerd --validate \
      --config-file=/usr/share/factory/etc/docker/daemon.json && \
    keyd check /usr/share/factory/etc/keyd/default.conf && \
    systemd-analyze verify \
      /usr/lib/systemd/system/workstation-docker-users.service \
      /usr/lib/systemd/user/workstation-bootstrap.service \
      /usr/lib/systemd/user/workstation-dms-settings.service \
      /usr/lib/systemd/user/workstation-invoice-bookmarks.service \
      /usr/lib/systemd/user/workstation-microsoft-fonts.service && \
    systemctl preset containerd.service docker.service keyd.service \
      workstation-docker-users.service && \
    systemctl --global preset workstation-bootstrap.service \
      workstation-dms-settings.service \
      workstation-invoice-bookmarks.timer \
      workstation-microsoft-fonts.service && \
    bootc container lint
