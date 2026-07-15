# Build toolchain for medion-lifetab-s1024x-unlock.
# Lets the OFFLINE image build (build-image.sh + make-vbmeta-disable.sh) run on any OS with
# Docker/Podman — no need to install android-tools/e2fsprogs/avbtool on the host.
# USB steps (backup / unlock / flash) still use native mtkclient — see README.
FROM archlinux:latest
# Speed-up + reliability: use a small list of fast mirrors instead of the flaky default.
# pacman fails over to the next Server if one stalls (the default fastly mirror likes to drop
# to <1 byte/sec mid-download and abort the whole build). Order: geo-CDN, then two solid mirrors.
RUN { \
      echo 'Server = https://geo.mirror.pkgbuild.com/$repo/os/$arch'; \
      echo 'Server = https://ftp.halifax.rwth-aachen.de/archlinux/$repo/os/$arch'; \
      echo 'Server = https://mirror.rackspace.com/archlinux/$repo/os/$arch'; \
    } > /etc/pacman.d/mirrorlist
# -Syu (full upgrade + install together) avoids the partial-upgrade libgcc/gcc-libs conflict.
# Only what the container build actually uses (no git — it's a host-only dep, for cloning mtkclient).
RUN pacman -Syu --noconfirm --needed \
      android-tools e2fsprogs python openssl curl unzip sqlite \
 && pacman -Scc --noconfirm && rm -rf /var/cache/pacman/pkg/*
WORKDIR /work
