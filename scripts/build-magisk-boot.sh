#!/usr/bin/env bash
# build-magisk-boot.sh — root the tablet by patching the STOCK boot with Magisk, OFFLINE.
#
# How it works (and why no emulator is needed):
#   Magisk ships its tools for every ABI inside the APK. We run the *x86_64* `magiskboot`
#   on the PC/container to unpack+repack the image, and we embed the *arm64* Magisk payload
#   (magiskinit/magisk/init-ld) into the ramdisk. The arm64 bits are only executed later on
#   the tablet, never on the host — so this works on any x86_64 Linux/Docker with no qemu.
#
# Requires: curl, unzip  (both are in setup.sh / the Docker image). Needs network to fetch
# Magisk once (cached in .work-magisk afterwards).
#
# Run from the repo root. Usage:
#   ./scripts/build-magisk-boot.sh
# Env (optional):
#   BACKUP      stock backup folder (default ~/mtkclient/backup_nv), must contain boot.bin
#   OUT         output name (default boot_magisk.img)
#   MAGISK_VER  Magisk release tag to use (default v30.7) — bump here to update
#   DEVICE_ARCH device ABI to embed (default arm64-v8a; MT6765 is arm64)
set -euo pipefail

BACKUP="${BACKUP:-${MTK:-$HOME/mtkclient}/backup_nv}"
OUT="${OUT:-boot_magisk.img}"
MAGISK_VER="${MAGISK_VER:-v30.7}"
DEVICE_ARCH="${DEVICE_ARCH:-arm64-v8a}"
W=".work-magisk"; mkdir -p "$W"

die(){ printf '\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }
for t in curl unzip; do command -v "$t" >/dev/null || die "missing tool '$t' (setup.sh installs it)"; done
[ -f "$BACKUP/boot.bin" ] || die "no $BACKUP/boot.bin — make a backup first (scripts/backup-stock.sh)"

APK="$W/Magisk-$MAGISK_VER.apk"
echo "[1/4] Fetching Magisk $MAGISK_VER"
if [ -f "$APK" ] && unzip -tq "$APK" >/dev/null 2>&1; then
  echo "  cached: $APK"
else
  curl -fSL -o "$APK" \
    "https://github.com/topjohnwu/Magisk/releases/download/$MAGISK_VER/Magisk-$MAGISK_VER.apk" \
    || die "download failed — check network or MAGISK_VER"
  unzip -tq "$APK" >/dev/null 2>&1 || die "downloaded Magisk apk is corrupt"
fi
# keep a copy at a stable path so build-image.sh / the fixup module can bundle the manager app
cp -f "$APK" "$W/Magisk.apk"

echo "[2/4] Extracting patch components (host=x86_64 tool, payload=$DEVICE_ARCH)"
P="$W/patch"; rm -rf "$P"; mkdir -p "$P" "$W/x"
unzip -oq "$APK" "lib/x86_64/libmagiskboot.so" -d "$W/x"
cp "$W/x/lib/x86_64/libmagiskboot.so" "$P/magiskboot"          # runs on the host/container
for f in libmagiskinit libmagisk libmagiskpolicy libinit-ld; do
  unzip -oq "$APK" "lib/$DEVICE_ARCH/$f.so" -d "$W/x" \
    || die "Magisk apk missing lib/$DEVICE_ARCH/$f.so (wrong DEVICE_ARCH?)"
done
cp "$W/x/lib/$DEVICE_ARCH/libmagiskinit.so"   "$P/magiskinit"   # becomes /init on the tablet
cp "$W/x/lib/$DEVICE_ARCH/libmagisk.so"       "$P/magisk"       # embedded, run on tablet only
cp "$W/x/lib/$DEVICE_ARCH/libmagiskpolicy.so" "$P/magiskpolicy"
cp "$W/x/lib/$DEVICE_ARCH/libinit-ld.so"      "$P/init-ld"
unzip -oq "$APK" assets/boot_patch.sh assets/util_functions.sh assets/stub.apk -d "$W/x"
cp "$W/x/assets/boot_patch.sh" "$W/x/assets/util_functions.sh" "$W/x/assets/stub.apk" "$P/"
chmod +x "$P/magiskboot" "$P/boot_patch.sh"
cp "$BACKUP/boot.bin" "$P/boot.img"

echo "[3/4] Patching boot with Magisk (offline)"
# This device: MT6765, A-only, header v2, normal two-stage-init ramdisk (no skip_initramfs).
# KEEPVERITY=true / KEEPFORCEENCRYPT=true are DELIBERATE and REQUIRED here: with false, Magisk
# rewrites the first-stage fstab to strip verity, and on this device it over-trims the /system
# line (which carries avb_keys=...) down to just "wait" — dropping "logical,first_stage_mount".
# /system is a LOGICAL partition inside super, so without that flag first-stage mount fails and
# the tablet drops to FASTBOOT. We disable verity via vbmeta_disable.img instead (same as the
# no-root flow), so the fstab must stay byte-identical to stock. LEGACYSAR/RECOVERYMODE=false;
# BOOTMODE=false = offline (host) mode.
# PREINITDEVICE=persist: an offline patch can't auto-detect the device's "preinit" partition (where
# Magisk keeps sepolicy rules before /data decrypts). Without it the log warns "preinit dir not
# found" and the app nags "reflash Magisk (recovery mode cannot get correct device info)". This
# device has a real `persist` partition, so we name it explicitly to silence both.
( cd "$P" && KEEPVERITY=true KEEPFORCEENCRYPT=true RECOVERYMODE=false LEGACYSAR=false BOOTMODE=false PREINITDEVICE=persist \
    sh ./boot_patch.sh boot.img ) > "$W/patch.log" 2>&1 \
  || { echo "---- boot_patch.sh log ----"; cat "$W/patch.log"; die "boot_patch.sh failed"; }
[ -f "$P/new-boot.img" ] || { cat "$W/patch.log"; die "no new-boot.img produced"; }

echo "[4/5] Injecting boot-resident auto-fix (SELinux permissive + adb + provisioning)"
# Magisk's magiskinit injects any *.rc in the ramdisk 'overlay.d' into init. We add a service
# that on sys.boot_completed runs as root in Magisk's permissive domain and:
#   (a) setenforce 0 — THE key fix. This 'user' build ships a broken/incomplete SELinux policy:
#       under enforcing, denied binder calls crash adbd (no adb), crash Settings' Developer
#       options, and break assorted framework bits ("half the system doesn't work"). Permissive
#       turns those denials into log-only and the system becomes fully usable. (Security
#       trade-off, fine for a hobby/second-screen tablet on an unlocked bootloader.)
#   (b) enables adb (usb + tcp:5555) — adbd only stays up once SELinux is permissive.
#   (c) finishes provisioning (device_provisioned / user_setup_complete).
# It also `pm install`s the Magisk apk that build-image.sh staged at /system/etc/medion/Magisk.apk
# (if present and not already installed) so Magisk comes up as a normal USER app — no stub, and
# none of the UPDATED_SYSTEM_APP grief a /system-app Magisk causes.
# Applies with no screen / no adb / no /data module. Harmless if it fails (never blocks boot).
# NOT fixed by this: recents/overview (mRecentsComponent=null) — that needs a Launcher3 with
# QuickStep as a privileged system app; it's a missing component, not an SELinux issue.
cat > "$P/medion.rc" <<'RC'
service medionfix /system/bin/sh -c "/system/bin/setenforce 0; /system/bin/sleep 6; /system/bin/settings put global adb_enabled 1; /system/bin/settings put global development_settings_enabled 1; /system/bin/settings put global device_provisioned 1; /system/bin/settings put secure user_setup_complete 1; /system/bin/setprop service.adb.tcp.port 5555; /system/bin/setprop ctl.stop adbd; /system/bin/sleep 1; /system/bin/setprop ctl.start adbd; [ -f /system/etc/medion/medion-boot.sh ] && /system/bin/sh /system/etc/medion/medion-boot.sh"
    user root
    seclabel u:r:magisk:s0
    oneshot
    disabled

on property:sys.boot_completed=1
    start medionfix
RC
( cd "$P" \
  && ./magiskboot unpack new-boot.img >/dev/null 2>&1 \
  && ./magiskboot cpio ramdisk.cpio "add 0644 overlay.d/medion.rc medion.rc" >/dev/null 2>&1 \
  && ./magiskboot repack new-boot.img new-boot-fix.img >/dev/null 2>&1 \
  && mv -f new-boot-fix.img new-boot.img ) \
  || die "failed to inject overlay.d auto-fix rc"

echo "[5/5] Verifying the patch is really in there"
( cd "$P" && ./magiskboot unpack new-boot.img >/dev/null 2>&1 \
  && ./magiskboot cpio ramdisk.cpio "exists .backup/.magisk" >/dev/null 2>&1 \
  && ./magiskboot cpio ramdisk.cpio "exists overlay.d/medion.rc" >/dev/null 2>&1 ) \
  || die "patched ramdisk missing Magisk backup or auto-fix rc — patch looks wrong"
( cd "$P" && ./magiskboot cleanup >/dev/null 2>&1 ) || true   # tidy unpack artifacts
cp "$P/new-boot.img" "$OUT"
echo "  OK -> $OUT  ($(du -h "$OUT" | cut -f1), Magisk $MAGISK_VER / $DEVICE_ARCH)"
echo
printf '\033[1;32mDONE: %s\033[0m\n' "$OUT"
echo "Next: flash it alongside the unkiosk image:"
echo "      scripts/flash.sh super_unkiosk.img vbmeta_disable.img $OUT"
echo "      (then install the Magisk app on the tablet: $W/Magisk.apk)"
