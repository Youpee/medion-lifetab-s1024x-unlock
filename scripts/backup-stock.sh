#!/usr/bin/env bash
# backup-stock.sh — take a FULL stock backup over BROM (mtkclient).
# MANDATORY before any edits — your safety net and the donor for the build.
#
# Enter BROM: run this FIRST, tablet OFF, then press & HOLD the VOLUME-DOWN button (the lower-volume
# side of the volume rocker — NOT Power) and, keeping it held, plug in USB.
# (BROM = the SoC's built-in USB bootloader; see README "What is BROM".)
set -euo pipefail
Y=$'\033[1;33m'; G=$'\033[1;32m'; N=$'\033[0m'   # terminal highlighting (renders through tee too)
MTK="${MTK:-$HOME/mtkclient}"
DEST="${DEST:-$MTK/backup_nv}"
mkdir -p "$DEST"
[ -x "$MTK/venv/bin/python" ] || { echo "no $MTK/venv/bin/python — install mtkclient"; exit 1; }
cd "$MTK"
printf '%s>>> BROM: HOLD the VOLUME-DOWN button%s (lower-volume side, not Power), then plug in USB.\n' "$Y" "$N"
echo ">>> Reading partitions..."
PARTS="super,vbmeta,vbmeta_system,vbmeta_vendor,dtbo,boot,lk,lk2"
FILES="$DEST/super.bin,$DEST/vbmeta.bin,$DEST/vbmeta_system.bin,$DEST/vbmeta_vendor.bin,$DEST/dtbo.bin,$DEST/boot.bin,$DEST/lk.bin,$DEST/lk2.bin"
sudo ./venv/bin/python mtk.py r "$PARTS" "$FILES"
printf '%sDONE. Backup in %s%s\n' "$G" "$DEST" "$N"
echo
echo "Next: unlock the bootloader (tablet in BROM: HOLD VOLUME-DOWN, then plug in USB):"
echo "        ( cd \"$MTK\" && sudo ./venv/bin/python mtk.py da seccfg unlock )"
echo "      then build the image:  scripts/build-image.sh"
