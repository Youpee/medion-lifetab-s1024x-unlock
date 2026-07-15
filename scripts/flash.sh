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
printf '\033[1;33m>>> BROM: HOLD the VOLUME-DOWN button (lower-volume side, not Power), then plug in USB.\033[0m\n'
echo ">>> Flashing super (super write takes ~12-14 min)..."
sudo ./venv/bin/python mtk.py w super  "$SUPER"
sudo ./venv/bin/python mtk.py w vbmeta "$VBM"
sudo ./venv/bin/python mtk.py e userdata,metadata,md_udc,cache
printf '\033[1;33m>>> On reset you may see "[Errno 2] Entity not found" — THAT IS NORMAL\033[0m\n'
echo "    right before 'Reset command was sent' — THAT IS NORMAL, don't panic."
sudo ./venv/bin/python mtk.py reset || true
printf '\033[1;32mDONE. Unplug and power the tablet on — your launcher will come up.\033[0m\n'
echo "      (first boot after the data wipe may take a couple of minutes)"
echo
echo "Next (once it boots to your launcher): scripts/clean.sh   # free disk space"
