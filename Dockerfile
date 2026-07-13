# Build toolchain for medion-lifetab-s1024x-unlock.
# Lets the OFFLINE image build (build-image.sh + make-vbmeta-disable.sh) run on any OS with
# Docker/Podman — no need to install android-tools/e2fsprogs/avbtool on the host.
# USB steps (backup / unlock / flash) still use native mtkclient — see README.
FROM archlinux:latest
# -Syu (full upgrade + install together) avoids the partial-upgrade libgcc/gcc-libs conflict.
RUN pacman -Syu --noconfirm --needed \
      android-tools e2fsprogs python openssl git curl \
 && pacman -Scc --noconfirm && rm -rf /var/cache/pacman/pkg/*
WORKDIR /work
