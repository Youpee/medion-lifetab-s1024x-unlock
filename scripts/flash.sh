#!/usr/bin/env bash
# flash.sh — flash the modified super + vbmeta_disable over BROM and wipe /data.
#
# Enter BROM: run this script FIRST, tablet OFF, then press & HOLD the VOLUME-DOWN button
# (the lower-volume side of the volume rocker — NOT Power) and, keeping it held, plug in USB.
# If it catches "DAA_SIG_VERIFY_FAILED (0x7024)" the tablet is in Preloader, not BROM:
#   unplug fully (gone from lsusb), then replug while HOLDING VOLUME-DOWN before inserting USB.
#
# Usage:
#   scripts/flash.sh super_unkiosk.img vbmeta_disable.img [boot_magisk.img]
#   The optional 3rd arg is the Magisk-patched boot (scripts/build-magisk-boot.sh) — pass it
#   to flash root in the same run. Omit it for a no-root install.
set -euo pipefail
# terminal highlighting for the important bits (renders through `tee`/flog too)
B=$'\033[1m'; Y=$'\033[1;33m'; G=$'\033[1;32m'; R=$'\033[1;31m'; C=$'\033[1;36m'; N=$'\033[0m'
SUPER="${1:?pass the super image (e.g. super_unkiosk.img)}"
VBM="${2:-vbmeta_disable.img}"
BOOT="${3:-}"                                   # optional: boot_magisk.img (root)
MTK="${MTK:-$HOME/mtkclient}"
[ -f "$SUPER" ] || { echo "no $SUPER"; exit 1; }
[ -f "$VBM" ]   || { echo "no $VBM — generate it: scripts/make-vbmeta-disable.sh"; exit 1; }
SUPER="$(readlink -f "$SUPER")"; VBM="$(readlink -f "$VBM")"
if [ -n "$BOOT" ]; then
  [ -f "$BOOT" ] || { echo "no $BOOT — build it: scripts/build-magisk-boot.sh"; exit 1; }
  BOOT="$(readlink -f "$BOOT")"
fi
cd "$MTK"
printf '%s>>> BROM: HOLD the VOLUME-DOWN button%s (lower-volume side, NOT Power), then plug in USB.\n' "$Y" "$N"
printf '%s>>> Flashing super — this takes ~12-14 min. Do not unplug.%s\n' "$C" "$N"
sudo ./venv/bin/python mtk.py w super  "$SUPER"
sudo ./venv/bin/python mtk.py w vbmeta "$VBM"
if [ -n "$BOOT" ]; then
  echo ">>> Flashing Magisk-patched boot (root)..."
  sudo ./venv/bin/python mtk.py w boot "$BOOT"
fi
sudo ./venv/bin/python mtk.py e userdata,metadata,md_udc,cache
# Note: if a build ever crash-loops, the bootloader may latch a "boot-recovery" command and drop
# you into stock recovery. Just pick "Reboot system now" / "Try again" — a successful boot clears
# it. (No manual partition wipe needed; this device has no separate 'misc'/BCB to erase here.)
printf '%s>>> On reset mtkclient usually prints "[Errno 2] Entity not found" — %sTHAT IS NORMAL%s (the tablet just disconnected).\n' "$Y" "$B" "$N"
sudo ./venv/bin/python mtk.py reset || true

printf '\n%s============================================================%s\n' "$G" "$N"
printf '%s  DONE. Unplug and power the tablet ON.%s\n' "$G$B" "$N"
printf '%s============================================================%s\n' "$G" "$N"
if [ -n "$BOOT" ]; then
  printf '  First boot after a wipe takes ~2-3 min. Root, adb, the SELinux\n'
  printf '  permissive fix and the full Magisk app all install themselves.\n\n'
  printf '%s  ####################################################%s\n' "$R" "$N"
  printf '%s  #  FIRST BOOT: if the launcher HANGS / "not responding"  #%s\n' "$R$B" "$N"
  printf '%s  #  -> just REBOOT the tablet ONCE. Then it is permanent. #%s\n' "$R$B" "$N"
  printf '%s  ####################################################%s\n' "$R" "$N"
  printf '  (KISS checks root via su on its first launch; the boot service\n'
  printf '   settles that a moment later, so a single reboot fixes it.)\n\n'
  printf '  Then (optional): %sscripts/clean.sh%s   # free disk space\n' "$C" "$N"
else
  printf '  Your launcher comes up (no more Aldi kiosk).\n'
  printf '  Then (optional): %sscripts/clean.sh%s   # free disk space\n' "$C" "$N"
fi
