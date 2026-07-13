#!/usr/bin/env bash
# flash.sh — flash the modified super + vbmeta_disable over BROM and wipe /data.
#
# Enter BROM: run this script FIRST → tablet off → hold Volume Down (-) → plug USB.
# If it catches "DAA_SIG_VERIFY_FAILED (0x7024)" the tablet is in Preloader, not BROM:
#   unplug fully (gone from lsusb), then replug holding Vol- BEFORE inserting USB.
set -euo pipefail
SUPER="${1:?pass the super image (e.g. super_unkiosk.img)}"
VBM="${2:-vbmeta_disable.img}"
MTK="${MTK:-$HOME/mtkclient}"
[ -f "$SUPER" ] || { echo "no $SUPER"; exit 1; }
[ -f "$VBM" ]   || { echo "no $VBM — generate it: scripts/make-vbmeta-disable.sh"; exit 1; }
SUPER="$(readlink -f "$SUPER")"; VBM="$(readlink -f "$VBM")"
cd "$MTK"
echo ">>> BROM: hold Vol- + plug USB. Flashing super (super write takes ~12-14 min)..."
sudo ./venv/bin/python mtk.py w super  "$SUPER"
sudo ./venv/bin/python mtk.py w vbmeta "$VBM"
sudo ./venv/bin/python mtk.py e userdata,metadata,md_udc,cache
sudo ./venv/bin/python mtk.py reset
echo "DONE. Unplug and power the tablet on — your launcher will come up."
echo "      (first boot after the data wipe may take a couple of minutes)"
