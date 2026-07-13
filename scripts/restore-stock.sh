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
echo ">>> BROM: hold Vol- + plug USB. Restoring stock..."
sudo ./venv/bin/python mtk.py w super,vbmeta,vbmeta_system,vbmeta_vendor,dtbo,boot,lk,lk2 \
  "$B/super.bin,$B/vbmeta.bin,$B/vbmeta_system.bin,$B/vbmeta_vendor.bin,$B/dtbo.bin,$B/boot.bin,$B/lk.bin,$B/lk2.bin"
sudo ./venv/bin/python mtk.py e userdata,metadata,md_udc,cache
sudo ./venv/bin/python mtk.py reset
echo "DONE. Factory Aldi stock restored."
echo "(To unlock again later: scripts/build-image.sh -> make-vbmeta-disable.sh -> flash.sh)"
