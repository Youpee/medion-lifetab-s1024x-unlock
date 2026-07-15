#!/usr/bin/env bash
# clean.sh [--all] — free disk space.
#   (default)   remove regenerable BUILD artifacts in the repo (safe).
#   --all       ALSO remove what setup.sh installed elsewhere: the container image,
#               ~/mtkclient, and the downloaded launcher APK.
# It NEVER touches your stock backup (your only way back to stock).
set -euo pipefail
cd "$(dirname "$0")/.."
REPO="$(pwd)"
ALL=0; [ "${1:-}" = "--all" ] && ALL=1

freed=0
rm_if(){ if [ -e "$1" ]; then sz=$(du -sm "$1" 2>/dev/null | cut -f1); freed=$((freed + sz)); rm -rf "$1"; echo "  removed $1 (${sz} MB)"; fi; }

echo "Cleaning regenerable build artifacts in $REPO ..."
rm_if .work
rm_if .work-magisk               # Magisk apk cache + patch workspace (re-downloads on rebuild)
rm_if super_unkiosk.img          # rebuild anytime with scripts/build-image.sh
rm_if boot_magisk.img            # rebuild with scripts/build-magisk-boot.sh
rm_if medion-fixup.zip           # rebuild with scripts/build-fixup-module.sh
rm_if test_super.img
rm_if test_vbmeta.img

if [ "$ALL" = 1 ]; then
  echo
  echo "--all: removing things setup.sh installed ..."
  rm_if vbmeta_disable.img
  rm_if launchers                # downloaded launcher APK(s)
  rm_if apps                     # downloaded open-source app suite (fetch-apps.sh re-downloads)
  # container toolchain image (try both engines)
  for ce in docker podman; do
    command -v "$ce" >/dev/null 2>&1 && "$ce" rmi -f medion-unkiosk >/dev/null 2>&1 \
      && echo "  removed container image 'medion-unkiosk' via $ce (~1.2 GB)"
  done
  # mtkclient (cloned by setup.sh) — but NEVER if your backup lives inside it
  MTK="${MTK:-$HOME/mtkclient}"
  if [ -d "$MTK" ]; then
    if [ -d "$MTK/backup_nv" ]; then
      echo "  KEPT $MTK — it holds your stock backup ($MTK/backup_nv). Move the backup out first if you really want to remove mtkclient."
    else
      sz=$(du -sm "$MTK" 2>/dev/null | cut -f1); freed=$((freed + sz)); rm -rf "$MTK"; echo "  removed $MTK (${sz} MB)"
    fi
  fi
fi

echo
echo "Freed ~${freed} MB."
echo
echo "Your STOCK BACKUP is NOT touched (it's your only way back to stock):"
for b in "${BACKUP:-}" "$HOME/mtkclient/backup_nv"; do
  [ -n "$b" ] && [ -d "$b" ] && echo "  - $b  ($(du -sh "$b" 2>/dev/null | cut -f1))"
done
echo "  Delete a backup yourself ONLY if you never plan to restore stock:  rm -rf <path>"
if [ "$ALL" = 1 ] && command -v pacman >/dev/null 2>&1; then
  # Arch native install only. On Windows/macOS the tools live in the Docker image (already
  # removed above) — there are no system packages to clean here.
  echo
  echo "System packages + udev rules are left in place (they may be useful elsewhere)."
  echo "  Remove manually if you want:  sudo pacman -Rns android-tools ;  sudo rm /etc/udev/rules.d/*mtk*"
fi
