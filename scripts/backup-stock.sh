#!/usr/bin/env bash
# backup-stock.sh — take a FULL stock backup over BROM (mtkclient).
# MANDATORY before any edits — your safety net and the donor for the build.
#
# Enter BROM: run this FIRST → tablet off → hold Volume Down (-) → plug USB.
# (BROM = the SoC's built-in USB bootloader; see README "What is BROM".)
set -euo pipefail
MTK="${MTK:-$HOME/mtkclient}"
DEST="${DEST:-$MTK/backup_nv}"
mkdir -p "$DEST"
[ -x "$MTK/venv/bin/python" ] || { echo "no $MTK/venv/bin/python — install mtkclient"; exit 1; }
cd "$MTK"
printf '\033[1;33m>>> BROM: HOLD the VOLUME-DOWN button (lower-volume side, not Power), then plug in USB.\033[0m\n'
echo ">>> Reading partitions..."
PARTS="super,vbmeta,vbmeta_system,vbmeta_vendor,dtbo,boot,lk,lk2"
FILES="$DEST/super.bin,$DEST/vbmeta.bin,$DEST/vbmeta_system.bin,$DEST/vbmeta_vendor.bin,$DEST/dtbo.bin,$DEST/boot.bin,$DEST/lk.bin,$DEST/lk2.bin"
sudo ./venv/bin/python mtk.py r "$PARTS" "$FILES"
printf "\033[1;32mDONE. Backup in %s\033[0m\n" "$DEST"
echo
echo "Next: unlock the bootloader (tablet in BROM: Vol- + USB):"
echo "        ( cd \"$MTK\" && sudo ./venv/bin/python mtk.py da seccfg unlock )"
echo "      then build the image:  scripts/build-image.sh"
