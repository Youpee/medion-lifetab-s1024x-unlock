#!/usr/bin/env bash
# restore-stock.sh — restore the factory stock from backup (fully reversible).
# Enter BROM: run FIRST → tablet off → hold Volume Down (-) → plug USB.
set -euo pipefail
MTK="${MTK:-$HOME/mtkclient}"
B="${BACKUP:-$MTK/backup_nv}"
for f in super vbmeta vbmeta_system vbmeta_vendor dtbo boot lk lk2; do
  [ -f "$B/$f.bin" ] || { echo "no $B/$f.bin — incomplete backup"; exit 1; }
done
cd "$MTK"
printf '\033[1;33m>>> BROM: HOLD the VOLUME-DOWN button (lower-volume side, not Power), then plug in USB.\033[0m\n'
echo ">>> Restoring stock..."
sudo ./venv/bin/python mtk.py w super,vbmeta,vbmeta_system,vbmeta_vendor,dtbo,boot,lk,lk2 \
  "$B/super.bin,$B/vbmeta.bin,$B/vbmeta_system.bin,$B/vbmeta_vendor.bin,$B/dtbo.bin,$B/boot.bin,$B/lk.bin,$B/lk2.bin"
sudo ./venv/bin/python mtk.py e userdata,metadata,md_udc,cache
printf '\033[1;33m>>> "[Errno 2] Entity not found" on reset is NORMAL (device disconnecting).\033[0m\n'
sudo ./venv/bin/python mtk.py reset || true
printf '\033[1;32mDONE. Factory Aldi stock restored.\033[0m\n'
echo "(To unlock again later: scripts/build-image.sh -> make-vbmeta-disable.sh -> flash.sh)"
