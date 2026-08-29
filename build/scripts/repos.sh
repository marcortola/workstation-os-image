#!/usr/bin/bash
# Third-party repositories. Vendored, never fetched.
#
# Every .repo file here is a reviewed file in the repo rather than something
# curl'd from a vendor at build time. A remote repofile's baseurl and gpgkey
# silently become this build's trust anchors on whatever day it runs; a
# vendored file puts them under `git diff` and gitleaks. It also removes a
# network dependency and a class of transient build failure.
set -ouex pipefail

rpm -q dnf5-plugins >/dev/null || dnf5 -y install dnf5-plugins

install -Dm644 -t /etc/yum.repos.d/ /ctx/build/repos/*.repo

# Insync signs with its own key and the repofile references it by URL.
rpm --import https://d2t3ff60b2tol4.cloudfront.net/repomd.xml.key

# negativo17 ships in base-main with enabled=0 and NO priority= line (so the
# default 99). base-main enables it during its own build, installs ffmpeg and
# libavcodec from it, then disables it again. We need it enabled to pull
# gstreamer1-plugins-ugly. Note Terra is pinned to priority=100 precisely so
# that it loses to this repo on any overlap.
dnf5 -y config-manager setopt fedora-multimedia.enabled=1
