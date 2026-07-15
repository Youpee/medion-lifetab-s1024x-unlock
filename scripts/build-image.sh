#!/usr/bin/env bash
# build-image.sh — build a modified `super` for the Medion Lifetab S1024X:
#   * remove the Aldi kiosk launcher (AldiTalkFilialApp)
#   * enable ADB (root, no auth prompt)
#   * install your own launcher (and any extra APKs) into /system/app
#
# Works OFFLINE from a stock backup (no adb needed — it's disabled on the kiosk).
# Requires: android-tools (lpunpack/lpmake/lpdump/simg2img), e2fsprogs
#           (debugfs/e2fsck/resize2fs/dumpe2fs), avbtool, python3, openssl.
#
# Run from the repo root. Usage:
#   ./scripts/build-image.sh [LAUNCHER.apk] [extra1.apk extra2.apk ...]
#   (no args -> uses launchers/KISS.apk downloaded by scripts/setup.sh)
#
# Environment (optional):
#   BACKUP  — stock backup folder (default ~/mtkclient/backup_nv), must contain super.bin
#   OUT     — output super name (default super_unkiosk.img)
#   GROW_MB — how many MB to grow /system for the APKs (default 64)
set -euo pipefail

# launcher: 1st arg, or default to launchers/KISS.apk (fetched by scripts/setup.sh)
LAUNCHER="${1:-launchers/KISS.apk}"
[ $# -gt 0 ] && shift
EXTRA_APKS=("$@")
BACKUP="${BACKUP:-$HOME/mtkclient/backup_nv}"
OUT="${OUT:-super_unkiosk.img}"
GROW_MB="${GROW_MB:-64}"
KIOSK_APP="AldiTalkFilialApp"          # kiosk launcher dir name in /system/priv-app
SUPER_SIZE=4294967296                   # this device's super geometry (constant)
GROUP_MAX=4292870144
W=".work"; mkdir -p "$W"

die(){ printf '\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }
for t in lpunpack lpmake lpdump simg2img debugfs e2fsck resize2fs dumpe2fs avbtool python3 openssl; do
  command -v "$t" >/dev/null || die "missing tool '$t' (install android-tools/e2fsprogs/avbtool)"
done
[ -f "$BACKUP/super.bin" ] || die "no $BACKUP/super.bin — make a backup first (scripts/backup-stock.sh)"
[ -f "$LAUNCHER" ] || die "launcher not found: $LAUNCHER — run scripts/setup.sh to fetch KISS, or pass an apk path"

echo "[1/7] Extracting system/vendor/product from stock super"
lpunpack --partition=system --partition=vendor --partition=product "$BACKUP/super.bin" "$W/" >/dev/null
SYS="$W/system.img"
[ -f "$SYS" ] || die "lpunpack did not produce system.img"

echo "[2/7] Erasing AVB footer of system (verity is disabled via vbmeta_disable)"
avbtool erase_footer --image "$SYS" 2>/dev/null || true

echo "[3/7] Growing ext4 by ${GROW_MB} MB (room for extra APKs)"
CUR=$(stat -c %s "$SYS"); NEW=$(( CUR + GROW_MB*1024*1024 ))
truncate -s "$NEW" "$SYS"
e2fsck -fy "$SYS" >/dev/null 2>&1 || true
resize2fs "$SYS" >/dev/null 2>&1

echo "[4/7] Preparing edits (prop.default + force-adb rc)"
printf 'u:object_r:system_file:s0\0' > "$W/lbl_sf"
debugfs -R "dump /system/etc/prop.default $W/prop.default" "$SYS" 2>/dev/null
sed -i -E \
  -e 's/^ro\.secure=.*/ro.secure=0/' \
  -e 's/^ro\.adb\.secure=.*/ro.adb.secure=0/' \
  -e 's/^ro\.debuggable=.*/ro.debuggable=1/' \
  -e 's/^persist\.sys\.usb\.config=.*/persist.sys.usb.config=mtp,adb/' \
  "$W/prop.default"
cat > "$W/zz-forceadb.rc" <<'RC'
on property:sys.usb.config=none
    setprop sys.usb.config mtp,adb
on property:sys.boot_completed=1
    setprop sys.usb.config mtp,adb
    start adbd
RC

echo "[5/7] Editing image (enable adb + remove kiosk + add launcher)"
# kiosk: removing the .apk is enough (PackageManager won't find the package)
KIOSK_RM=""
if debugfs -R "stat /system/priv-app/$KIOSK_APP/$KIOSK_APP.apk" "$SYS" 2>/dev/null | grep -qi Type; then
  KIOSK_RM="rm /system/priv-app/$KIOSK_APP/$KIOSK_APP.apk"
else
  echo "  (warning: $KIOSK_APP.apk not found — maybe a different kiosk package; check /system/priv-app)"
fi
{
  echo "rm /system/etc/prop.default"
  echo "write $W/prop.default /system/etc/prop.default"
  echo "ea_set -f $W/lbl_sf /system/etc/prop.default security.selinux"
  echo "sif /system/etc/prop.default mode 0100644"
  echo "write $W/zz-forceadb.rc /system/etc/init/zz-forceadb.rc"
  echo "ea_set -f $W/lbl_sf /system/etc/init/zz-forceadb.rc security.selinux"
  echo "sif /system/etc/init/zz-forceadb.rc mode 0100644"
  [ -n "$KIOSK_RM" ] && echo "$KIOSK_RM"
} > "$W/ea.cmd"
# add launcher + extra APKs into /system/app/<Name>/<Name>.apk
add_apk(){ local apk name; apk="$(readlink -f "$1")"; name=$(basename "$apk" .apk | tr -cd 'A-Za-z0-9'); [ -n "$name" ] || name="App$RANDOM"
  {
    echo "mkdir /system/app/$name"
    echo "write $apk /system/app/$name/$name.apk"
    echo "ea_set -f $W/lbl_sf /system/app/$name security.selinux"
    echo "ea_set -f $W/lbl_sf /system/app/$name/$name.apk security.selinux"
    echo "sif /system/app/$name mode 040755"
    echo "sif /system/app/$name/$name.apk mode 0100644"
  } >> "$W/ea.cmd"
  echo "  + added $name ($apk)"
}
add_apk "$LAUNCHER"
for a in "${EXTRA_APKS[@]:-}"; do [ -n "$a" ] && add_apk "$a"; done
debugfs -w -f "$W/ea.cmd" "$SYS" >/dev/null 2>&1
e2fsck -fy "$SYS" >/dev/null 2>&1 || true

echo "[6/7] Assembling super (system + stock vendor/product)"
VSZ=$(stat -c %s "$W/vendor.img"); PSZ=$(stat -c %s "$W/product.img"); SSZ=$(stat -c %s "$SYS")
rm -f "$W/super_sparse.img" "$OUT"
lpmake --metadata-size 65536 --super-name super --metadata-slots 2 \
  --device super:$SUPER_SIZE --group main:$GROUP_MAX \
  --partition system:readonly:$SSZ:main   --image system="$SYS" \
  --partition vendor:readonly:$VSZ:main   --image vendor="$W/vendor.img" \
  --partition product:readonly:$PSZ:main  --image product="$W/product.img" \
  --sparse --output "$W/super_sparse.img" >/dev/null
simg2img "$W/super_sparse.img" "$OUT"

echo "[7/7] Verifying"
GOT=$(stat -c %s "$OUT")
[ "$GOT" = "$SUPER_SIZE" ] && echo "  OK size $OUT = $GOT" || die "size $GOT != $SUPER_SIZE"
lpdump "$OUT" | grep -qE "Name: system" && echo "  OK lpdump readable"
echo
printf '\033[1;32mDONE: %s\033[0m\n' "$OUT"
echo "Next: scripts/make-vbmeta-disable.sh   (then: scripts/flash.sh $OUT vbmeta_disable.img)"
