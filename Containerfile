ARG BASE_IMAGE=ghcr.io/zirconium-dev/zirconium:latest
FROM ${BASE_IMAGE}

LABEL org.opencontainers.image.source="https://github.com/marcortola/workstation-os-image"
LABEL org.opencontainers.image.description="Personal Fedora bootc image with host-integrated tools"

COPY system_files/ /

RUN /usr/libexec/workstation-patch-zdots && \
    dnf -y config-manager addrepo \
      --from-repofile=https://download.docker.com/linux/fedora/docker-ce.repo && \
    dnf -y install \
      cabextract \
      containerd.io \
      cpio \
      docker-buildx-plugin \
      docker-ce \
      docker-ce-cli \
      docker-compose-plugin \
      fish \
      fontconfig \
      keyd \
      shadow-utils \
      unzip && \
    dnf clean all && \
    dockerd --validate \
      --config-file=/usr/share/factory/etc/docker/daemon.json && \
    keyd check /usr/share/factory/etc/keyd/default.conf && \
    systemd-analyze verify \
      /usr/lib/systemd/system/workstation-docker-users.service \
      /usr/lib/systemd/user/workstation-bootstrap.service \
      /usr/lib/systemd/user/workstation-dms-settings.service \
      /usr/lib/systemd/user/workstation-microsoft-fonts.service && \
    systemctl preset containerd.service docker.service keyd.service \
      workstation-docker-users.service && \
    systemctl --global preset workstation-bootstrap.service \
      workstation-dms-settings.service \
      workstation-microsoft-fonts.service && \
    bootc container lint
