#!/usr/bin/env bash
# restore-stock.sh — restore the factory stock from backup (fully reversible).
# Enter BROM: run FIRST, tablet OFF, then press & HOLD the VOLUME-DOWN button (the lower-volume
# side of the volume rocker — NOT Power) and, keeping it held, plug in USB.
set -euo pipefail
Y=$'\033[1;33m'; G=$'\033[1;32m'; N=$'\033[0m'   # terminal highlighting (renders through tee too)
MTK="${MTK:-$HOME/mtkclient}"
B="${BACKUP:-$MTK/backup_nv}"
for f in super vbmeta vbmeta_system vbmeta_vendor dtbo boot lk lk2; do
  [ -f "$B/$f.bin" ] || { echo "no $B/$f.bin — incomplete backup"; exit 1; }
done
cd "$MTK"
printf '%s>>> BROM: HOLD the VOLUME-DOWN button%s (lower-volume side, not Power), then plug in USB.\n' "$Y" "$N"
echo ">>> Restoring stock..."
sudo ./venv/bin/python mtk.py w super,vbmeta,vbmeta_system,vbmeta_vendor,dtbo,boot,lk,lk2 \
  "$B/super.bin,$B/vbmeta.bin,$B/vbmeta_system.bin,$B/vbmeta_vendor.bin,$B/dtbo.bin,$B/boot.bin,$B/lk.bin,$B/lk2.bin"
sudo ./venv/bin/python mtk.py e userdata,metadata,md_udc,cache
printf '%s>>> "[Errno 2] Entity not found" on the reset is NORMAL%s (device disconnecting).\n' "$Y" "$N"
sudo ./venv/bin/python mtk.py reset || true
printf '%sDONE. Factory Aldi stock restored.%s\n' "$G" "$N"
echo "(To unlock again later: scripts/build-image.sh -> make-vbmeta-disable.sh -> flash.sh)"
