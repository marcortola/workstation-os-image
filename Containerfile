ARG BASE_IMAGE=ghcr.io/zirconium-dev/zirconium:latest
FROM ${BASE_IMAGE}

LABEL org.opencontainers.image.source="https://github.com/marcortola/workstation-os-image"
LABEL org.opencontainers.image.description="Personal Fedora bootc image with host-integrated tools"

RUN dnf -y config-manager addrepo \
      --from-repofile=https://download.docker.com/linux/fedora/docker-ce.repo && \
    dnf -y install \
      containerd.io \
      docker-buildx-plugin \
      docker-ce \
      docker-ce-cli \
      docker-compose-plugin \
      fish \
      keyd && \
    dnf clean all && \
    systemctl enable containerd.service docker.service keyd.service && \
    bootc container lint
