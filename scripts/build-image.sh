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
BACKUP="${BACKUP:-${MTK:-$HOME/mtkclient}/backup_nv}"
OUT="${OUT:-super_unkiosk.img}"
GROW_MB="${GROW_MB:-64}"
KIOSK_APP="AldiTalkFilialApp"          # kiosk launcher dir name in /system/priv-app
SUPER_SIZE=4294967296                   # this device's super geometry (constant)
GROUP_MAX=4292870144
W=".work"; mkdir -p "$W"

die(){ printf '\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }
for t in lpunpack lpmake lpdump simg2img debugfs e2fsck resize2fs dumpe2fs avbtool python3 openssl unzip; do
  command -v "$t" >/dev/null || die "missing tool '$t' (install android-tools/e2fsprogs/avbtool/unzip)"
done

# A baked /system app is READ-ONLY, so PackageManager can't unpack its native libs at runtime.
# Libs stored uncompressed in the apk load straight from it; DEFLATED libs can't, and the app dies
# with UnsatisfiedLinkError (e.g. Cromite's libchrome, Material Files' libhiddenapi). So for those
# we extract the deflated arm64 libs into <app>/lib/arm64 at build time (what PM would do on /data).
defl_lib_bytes(){ # $1=apk  -> uncompressed bytes of its DEFLATED arm64 .so files
  # unzip exits 11 when the apk has no matching libs; tolerate it (pipefail would abort otherwise)
  { unzip -v "$1" 'lib/arm64-v8a/*.so' 2>/dev/null || true; } \
    | awk '$2!="Stored" && /lib\/arm64-v8a\/.*\.so$/ {s+=$1} END{print s+0}'
}
emit_libs(){ # $1=apk  $2=/system/(priv-)app/Name   (appends debugfs cmds; uses $W, $W/lbl_sf)
  local apk="$1" base="$2" name; name="$(basename "$base")"
  local need; need=$({ unzip -v "$apk" 'lib/arm64-v8a/*.so' 2>/dev/null || true; } \
    | awk '$2!="Stored" && /lib\/arm64-v8a\/.*\.so$/ {print $NF}')
  [ -n "$need" ] || return 0
  local ld="$W/lib_$name"; rm -rf "$ld"; mkdir -p "$ld"
  unzip -o -j "$apk" 'lib/arm64-v8a/*.so' -d "$ld" >/dev/null 2>&1 || true
  {
    echo "mkdir $base/lib";       echo "ea_set -f $W/lbl_sf $base/lib security.selinux";       echo "sif $base/lib mode 040755"
    echo "mkdir $base/lib/arm64"; echo "ea_set -f $W/lbl_sf $base/lib/arm64 security.selinux"; echo "sif $base/lib/arm64 mode 040755"
  } >> "$W/ea.cmd"
  local so b n=0
  for so in $need; do
    b="$(basename "$so")"; [ -f "$ld/$b" ] || continue
    {
      echo "write $ld/$b $base/lib/arm64/$b"
      echo "ea_set -f $W/lbl_sf $base/lib/arm64/$b security.selinux"
      echo "sif $base/lib/arm64/$b mode 0100644"
    } >> "$W/ea.cmd"
    n=$((n+1))
  done
  echo "    + extracted $n native lib(s) -> $base/lib/arm64"
}
[ -f "$BACKUP/super.bin" ] || die "no $BACKUP/super.bin — make a backup first (scripts/backup-stock.sh)"
# auto-fetch KISS if it's the default and missing (also makes the Docker path self-contained)
if [ "$LAUNCHER" = "launchers/KISS.apk" ] && [ ! -f "$LAUNCHER" ] && command -v curl >/dev/null 2>&1; then
  echo "  launcher missing -> fetching KISS from F-Droid ..."
  mkdir -p launchers
  code=$(curl -fsSL https://f-droid.org/api/v1/packages/fr.neamar.kiss 2>/dev/null | python3 -c 'import sys,json;print(json.load(sys.stdin)["suggestedVersionCode"])' 2>/dev/null || true)
  [ -n "$code" ] && curl -fSL -o "$LAUNCHER" "https://f-droid.org/repo/fr.neamar.kiss_${code}.apk" 2>/dev/null || true
fi
[ -f "$LAUNCHER" ] || die "launcher not found: $LAUNCHER — run scripts/setup.sh to fetch KISS, or pass an apk path"

# --- curated open-source system-app suite (scripts/fetch-apps.sh -> apps/) ---
# Everything under apps/system/ is baked into /system/app. WITH_APPS=0 skips it.
WITH_APPS="${WITH_APPS:-1}"
# self-contained path: fetch the suite if it isn't here yet (mirrors the KISS auto-fetch above)
if [ "$WITH_APPS" = 1 ] && [ ! -d apps/system ] && [ -f scripts/fetch-apps.sh ] && command -v curl >/dev/null 2>&1; then
  echo "  apps/ missing -> running scripts/fetch-apps.sh (downloads the app suite) ..."
  bash scripts/fetch-apps.sh || die "scripts/fetch-apps.sh failed"
fi
SUITE_APKS=()
if [ "$WITH_APPS" = 1 ] && [ -d apps/system ]; then
  for a in apps/system/*.apk; do [ -e "$a" ] && SUITE_APKS+=("$a"); done
fi
# microG chain is present ONLY if fetch-apps.sh pulled it (root branch). WITH_MICROG=0 skips.
MICROG_GMS="apps/microg/priv-app/GmsCore.apk"
MICROG_ON=0
[ "${WITH_MICROG:-1}" = 1 ] && [ -f "$MICROG_GMS" ] && MICROG_ON=1

# auto-size the /system growth from everything we're about to add (+128 MB margin for
# Magisk/first-boot). Overridable: set GROW_MB yourself to force a value.
if [ -z "${GROW_MB_FORCED:-}" ]; then
  _b=0
  for f in "$LAUNCHER" "${EXTRA_APKS[@]:-}" "${SUITE_APKS[@]:-}"; do
    [ -n "$f" ] && [ -f "$f" ] && _b=$((_b + $(stat -c %s "$f") + $(defl_lib_bytes "$f")))
  done
  if [ "$MICROG_ON" = 1 ]; then
    for f in apps/microg/priv-app/*.apk apps/microg/system/*.apk; do
      [ -f "$f" ] && _b=$((_b + $(stat -c %s "$f") + $(defl_lib_bytes "$f")))
    done
    [ -f apps/microg/LSPosed.zip ] && _b=$((_b + $(stat -c %s apps/microg/LSPosed.zip)))
  fi
  _mb=$(( _b/1024/1024 + 128 ))
  [ "$_mb" -gt "$GROW_MB" ] && GROW_MB="$_mb"
fi
echo "  suite: ${#SUITE_APKS[@]} app(s)$( [ "$MICROG_ON" = 1 ] && printf ' + microG chain' ); growing /system by ${GROW_MB} MB"

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
# default UI language: stock ships de-DE — make English the out-of-the-box default (a fresh
# /data reads ro.product.locale). The user can still change language in Settings afterwards.
debugfs -R "dump /system/build.prop $W/build.prop" "$SYS" 2>/dev/null
if grep -q '^ro.product.locale=' "$W/build.prop" 2>/dev/null; then
  sed -i -E 's/^ro\.product\.locale=.*/ro.product.locale=en-US/' "$W/build.prop"
else
  printf 'ro.product.locale=en-US\n' >> "$W/build.prop"
fi
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
  echo "rm /system/build.prop"
  echo "write $W/build.prop /system/build.prop"
  echo "ea_set -f $W/lbl_sf /system/build.prop security.selinux"
  echo "sif /system/build.prop mode 0100644"
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
  emit_libs "$apk" "/system/app/$name"
  echo "  + added $name ($apk)"
}
add_apk "$LAUNCHER"
for a in "${EXTRA_APKS[@]:-}"; do [ -n "$a" ] && add_apk "$a"; done
# curated FOSS suite (browser, camera, gallery, files, keyboard, F-Droid, Aurora) -> /system/app
for a in "${SUITE_APKS[@]:-}"; do [ -n "$a" ] && add_apk "$a"; done

# add a PRIVILEGED system app: /system/priv-app/<Name>/<Name>.apk
add_privapp(){ local apk name; apk="$(readlink -f "$1")"; name="$2"
  {
    echo "mkdir /system/priv-app/$name"
    echo "write $apk /system/priv-app/$name/$name.apk"
    echo "ea_set -f $W/lbl_sf /system/priv-app/$name security.selinux"
    echo "ea_set -f $W/lbl_sf /system/priv-app/$name/$name.apk security.selinux"
    echo "sif /system/priv-app/$name mode 040755"
    echo "sif /system/priv-app/$name/$name.apk mode 0100644"
  } >> "$W/ea.cmd"
  emit_libs "$apk" "/system/priv-app/$name"
  echo "  + priv-app $name ($apk)"
}

# --- microG (root only): GmsCore priv-app + privapp whitelist + FakeStore/FakeGApps + LSPosed ---
# ro.control_privapp_permissions=enforce on this ROM, so GmsCore MUST ship a permission whitelist
# or it loses its privileged perms (and can warn on boot). Signature spoofing itself is provided
# at runtime by the FakeGApps LSPosed module — see medion-boot.sh + the README's microG section.
if [ "$MICROG_ON" = 1 ]; then
  echo "  microG: GmsCore (priv-app) + whitelist + FakeStore + FakeGApps + LSPosed (staged)"
  cat > "$W/privapp-microg.xml" <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<permissions>
    <privapp-permissions package="com.google.android.gms">
        <permission name="android.permission.FAKE_PACKAGE_SIGNATURE"/>
        <permission name="android.permission.INSTALL_LOCATION_PROVIDER"/>
        <permission name="android.permission.LOCATION_HARDWARE"/>
        <permission name="android.permission.UPDATE_APP_OPS_STATS"/>
        <permission name="android.permission.UPDATE_DEVICE_STATS"/>
        <permission name="android.permission.INTERACT_ACROSS_USERS"/>
        <permission name="android.permission.WRITE_SECURE_SETTINGS"/>
        <permission name="android.permission.READ_DEVICE_CONFIG"/>
        <permission name="android.permission.MANAGE_APP_OPS_MODES"/>
        <permission name="android.permission.WATCH_APPOPS"/>
        <permission name="android.permission.CHANGE_DEVICE_IDLE_TEMP_WHITELIST"/>
        <permission name="android.permission.ACCESS_BACKGROUND_LOCATION"/>
    </privapp-permissions>
</permissions>
XML
  add_privapp "$MICROG_GMS" GmsCore
  {
    echo "write $(readlink -f "$W/privapp-microg.xml") /system/etc/permissions/privapp-permissions-microg.xml"
    echo "ea_set -f $W/lbl_sf /system/etc/permissions/privapp-permissions-microg.xml security.selinux"
    echo "sif /system/etc/permissions/privapp-permissions-microg.xml mode 0100644"
  } >> "$W/ea.cmd"
  for a in apps/microg/system/*.apk; do [ -f "$a" ] && add_apk "$a"; done
  # Pre-seed LSPosed's config db so FakeGApps is ENABLED and scoped to the System Framework +
  # com.google.android.gms -> microG signature spoofing activates with NO manual LSPosed taps.
  # KEY: this LSPosed fork (JingMatrix "Vector") identifies system_server as the package `system`
  # (not `android` like upstream), so the scope MUST include `system` or the hook never lands in
  # system_server and "System spoofs signature" stays unchecked. Needs sqlite3 on the host; without
  # it we skip and spoofing becomes a documented manual step.
  if command -v sqlite3 >/dev/null 2>&1; then
    rm -f "$W/lspd-seed.db"
    sqlite3 "$W/lspd-seed.db" <<'SQL'
CREATE TABLE android_metadata (locale TEXT);
CREATE TABLE modules (mid integer PRIMARY KEY AUTOINCREMENT,module_pkg_name text NOT NULL UNIQUE,apk_path text NOT NULL, enabled BOOLEAN DEFAULT 0 CHECK (enabled IN (0, 1)), auto_include BOOLEAN DEFAULT 0 CHECK (auto_include IN (0, 1)));
CREATE TABLE scope (mid integer,app_pkg_name text NOT NULL,user_id integer NOT NULL,PRIMARY KEY (mid, app_pkg_name, user_id),CONSTRAINT scope_module_constraint  FOREIGN KEY (mid)  REFERENCES modules (mid)  ON DELETE CASCADE);
CREATE TABLE configs (module_pkg_name text NOT NULL,user_id integer NOT NULL,`group` text NOT NULL,`key` text NOT NULL,data blob NOT NULL,PRIMARY KEY (module_pkg_name, user_id, `group`, `key`),CONSTRAINT config_module_constraint  FOREIGN KEY (module_pkg_name)  REFERENCES modules (module_pkg_name)  ON DELETE CASCADE);
CREATE INDEX configs_idx ON configs (module_pkg_name, user_id);
INSERT INTO modules (module_pkg_name,apk_path,enabled,auto_include) VALUES ('lspd','/data/adb/modules/zygisk_vector/manager.apk',0,0);
INSERT INTO modules (module_pkg_name,apk_path,enabled,auto_include) VALUES ('inc.whew.android.fakegapps','/system/app/FakeGApps/FakeGApps.apk',1,0);
INSERT INTO scope (mid,app_pkg_name,user_id) SELECT mid,'system',0 FROM modules WHERE module_pkg_name='inc.whew.android.fakegapps';
INSERT INTO scope (mid,app_pkg_name,user_id) SELECT mid,'android',0 FROM modules WHERE module_pkg_name='inc.whew.android.fakegapps';
INSERT INTO scope (mid,app_pkg_name,user_id) SELECT mid,'com.google.android.gms',0 FROM modules WHERE module_pkg_name='inc.whew.android.fakegapps';
SQL
    echo "  microG: generated LSPosed seed (FakeGApps auto-enabled, scope 'system') for auto-spoofing"
  else
    echo "  microG: no host sqlite3 -> skipping LSPosed seed (FakeGApps enable becomes a manual step)"
  fi
fi
# Stage the full Magisk apk as a plain FILE in /system/etc/medion (NOT in /system/app!). The
# boot service then `pm install`s it on first boot, so Magisk lands in /data/app as a normal
# USER app: no stub / no "needs internet" dialog, AND none of the UPDATED_SYSTEM_APP grief that
# a /system-app Magisk causes (Superuser tab going unavailable after every reboot). Best of both.
# Set BAKE_MAGISK=0 to skip (then Magisk installs its stub on first boot, or `adb install` it).
MAGISK_APK="${MAGISK_APK:-.work-magisk/Magisk.apk}"
if [ "${BAKE_MAGISK:-1}" = 1 ] && [ -f "$MAGISK_APK" ]; then
  echo "  staging Magisk + boot script in /system/etc/medion (installed as a USER app on boot)"
  MA="$(readlink -f "$MAGISK_APK")"
  # Extract Magisk's env (binaries + scripts) and tar it, so the boot service can populate
  # /data/adb/magisk on first boot (the app's "additional setup", automated). Mapping: the APK's
  # lib<x>.so are the binaries (lib prefix + .so stripped); armeabi libmagisk.so is the 32-bit one.
  ME="$W/magisk-env"; rm -rf "$ME"; mkdir -p "$ME/chromeos"
  unzip -oq "$MA" 'lib/arm64-v8a/lib*.so' -d "$ME/x" 2>/dev/null
  for f in "$ME"/x/lib/arm64-v8a/lib*.so; do b="$(basename "$f" .so)"; cp "$f" "$ME/${b#lib}"; done
  unzip -oq "$MA" 'lib/armeabi-v7a/libmagisk.so' -d "$ME/x" 2>/dev/null && cp "$ME/x/lib/armeabi-v7a/libmagisk.so" "$ME/magisk32"
  unzip -oq "$MA" 'assets/boot_patch.sh' 'assets/util_functions.sh' 'assets/addon.d.sh' 'assets/stub.apk' -d "$ME/x" 2>/dev/null
  cp "$ME/x/assets/boot_patch.sh" "$ME/x/assets/util_functions.sh" "$ME/x/assets/addon.d.sh" "$ME/x/assets/stub.apk" "$ME/" 2>/dev/null
  unzip -oq "$MA" 'assets/chromeos/*' -d "$ME/x" 2>/dev/null && cp "$ME"/x/assets/chromeos/* "$ME/chromeos/" 2>/dev/null
  rm -rf "$ME/x"
  tar -C "$ME" -cf "$W/magisk-env.tar" .
  echo "    baked magisk-env.tar ($(du -h "$W/magisk-env.tar" | cut -f1)) for auto /data/adb/magisk setup"
  # boot-time script the overlay.d service runs (root, permissive). Kept as a real file so it
  # can use quotes/case that would be a nightmare inside the init .rc one-liner.
  cat > "$W/medion-boot.sh" <<'MB'
#!/system/bin/sh
# 0) Populate /data/adb/magisk from the baked env tar. This is the "additional setup" the Magisk
#    app would otherwise nag for: an empty /data/adb/magisk shows "Additional setup required" and
#    leaves Zygisk OFF. Doing it here means Zygisk turns on and LSPosed installs with NO manual
#    taps. (Like the app's own setup, it takes effect on the next boot — the first-boot reboot
#    that KISS already needs covers it.)
if [ -f /system/etc/medion/magisk-env.tar ] && [ ! -f /data/adb/magisk/magiskinit ]; then
  mkdir -p /data/adb/magisk
  tar -xf /system/etc/medion/magisk-env.tar -C /data/adb/magisk 2>/dev/null
  chmod 0755 /data/adb/magisk/* 2>/dev/null
  magisk --restorecon 2>/dev/null
fi
# 1) Install the full Magisk over its stub, as a USER app (staged apk, no internet needed).
#    The stub reports versionName=1.0 and CANNOT answer su requests -> anything that calls su
#    (e.g. the KISS launcher's root check) hangs forever. The full app answers su.
V=$(dumpsys package com.topjohnwu.magisk 2>/dev/null | grep -m1 versionName= | cut -d'=' -f2)
if [ -f /system/etc/medion/Magisk.apk ] && { [ -z "$V" ] || [ "$V" = "1.0" ]; }; then
  pm install -r -g /system/etc/medion/Magisk.apk
fi
# 2) KISS runs `su` synchronously on its MAIN THREAD at startup (root check). On a rooted device
#    that blocks on the Magisk prompt -> ANR ("KISS not responding"). Pre-grant su to the HOME
#    launcher so su returns instantly. Persisted in /data, so it's effective from the 2nd boot;
#    on a fresh /data the very first boot may need one reboot.
HP=$(cmd package resolve-activity -c android.intent.category.HOME 2>/dev/null | grep -m1 packageName= | cut -d'=' -f2)
for p in "$HP" fr.neamar.kiss; do
  [ -n "$p" ] || continue
  U=$(stat -c %u /data/data/"$p" 2>/dev/null)
  [ -n "$U" ] && magisk --sqlite "REPLACE INTO policies (uid,policy,until,logging,notification) VALUES($U,2,0,0,0)"
done
# 3) microG (only if the chain was baked): signature spoofing needs Zygisk + LSPosed + FakeGApps.
#    We automate what is reliable — turn Zygisk ON and install LSPosed as a Magisk module — and
#    keep microG alive (battery whitelist + su). ENABLING the FakeGApps module is a one-time manual
#    step in the LSPosed app afterwards (see the README). Location works even without spoofing.
if [ -f /system/etc/medion/LSPosed.zip ]; then
  # Zygisk must be on for LSPosed (Magisk setting; takes effect on the next reboot).
  magisk --sqlite "REPLACE INTO settings (key,value) VALUES('zygisk',1)" 2>/dev/null
  # Install LSPosed once from the staged zip.
  if [ ! -d /data/adb/modules/zygisk_lsposed ] && [ ! -d /data/adb/modules/lsposed ] && [ ! -d /data/adb/modules/zygisk_vector ]; then
    magisk --install-module /system/etc/medion/LSPosed.zip 2>/dev/null
  fi
  # Signature spoofing: once LSPosed has created its config db (it does that on the boot after it's
  # installed), replace it with our seed (FakeGApps enabled + scoped to 'system'=system_server and
  # com.google.android.gms) and reboot ONCE so LSPosed loads FakeGApps into system_server. After
  # that, microG's "System spoofs signature" is checked and Google login / FCM push work. One-shot,
  # guarded by a marker so it never loops or fights later manual changes.
  if [ -f /system/etc/medion/lspd-seed.db ] && [ -f /data/adb/lspd/config/modules_config.db ] && [ ! -f /data/adb/medion-lspd-seeded ]; then
    cp /system/etc/medion/lspd-seed.db /data/adb/lspd/config/modules_config.db
    rm -f /data/adb/lspd/config/modules_config.db-wal /data/adb/lspd/config/modules_config.db-shm
    chmod 600 /data/adb/lspd/config/modules_config.db
    chcon u:object_r:system_file:s0 /data/adb/lspd/config/modules_config.db 2>/dev/null
    touch /data/adb/medion-lspd-seeded
    ( sleep 4; setprop sys.powerctl reboot ) &
  fi
  # Keep GmsCore running in the background (exempt from Doze) and give it su.
  dumpsys deviceidle whitelist +com.google.android.gms >/dev/null 2>&1
  UG=$(stat -c %u /data/data/com.google.android.gms 2>/dev/null)
  [ -n "$UG" ] && magisk --sqlite "REPLACE INTO policies (uid,policy,until,logging,notification) VALUES($UG,2,0,0,0)"
fi
# 4) Notification shade helper. The stock SystemUI shade is broken (SystemUI is platform-signed,
#    unpatchable), so the shade comes from a replacement app you sideload. The only such apps are
#    Treydev's (Material Notification Shade / Power Shade / One Shade — all one dev, now ZipoApps).
#    Whichever you install, this makes it "just work": block ALL its internet with the root
#    firewall (the shade panel has no ads; ads/trackers only load over the net, so this kills them)
#    and pre-grant overlay + notification + accessibility. They share com.treydev.shades.* classes.
ACC=com.treydev.shades.MAccessibilityService
NLS=com.treydev.shades.NLService1
for SHADE in com.treydev.mns com.treydev.pns com.treydev.ons; do
  SU=$(stat -c %u /data/data/"$SHADE" 2>/dev/null)
  [ -n "$SU" ] || continue
  for ipt in iptables ip6tables; do
    $ipt -D OUTPUT -m owner --uid-owner "$SU" -j REJECT 2>/dev/null
    $ipt -I OUTPUT -m owner --uid-owner "$SU" -j REJECT 2>/dev/null
  done
  appops set "$SHADE" SYSTEM_ALERT_WINDOW allow 2>/dev/null
  cmd notification allow_listener "$SHADE/$NLS" 2>/dev/null
  cur=$(settings get secure enabled_accessibility_services 2>/dev/null)
  if [ -z "$cur" ] || [ "$cur" = null ]; then
    settings put secure enabled_accessibility_services "$SHADE/$ACC"
  elif ! printf '%s' "$cur" | grep -q "$SHADE/$ACC"; then
    settings put secure enabled_accessibility_services "$cur:$SHADE/$ACC"
  fi
  settings put secure accessibility_enabled 1
done
# 5) One-time defaults on a fresh /data: dark theme. English is already the default via build.prop
#    (ro.product.locale=en-US). Guarded by a marker so YOU can switch to light later and it won't
#    be re-forced on every boot. The marker lives in /data (wiped on reflash -> reapplied next install).
if [ ! -f /data/adb/medion-defaults-done ]; then
  cmd uimode night yes 2>/dev/null        # system-wide dark theme (Android 10 UiModeManager)
  mkdir -p /data/adb 2>/dev/null
  touch /data/adb/medion-defaults-done
fi
# 6) Keyboard: the stock LatinIME is removed (replaced by HeliBoard), so make sure HeliBoard is
#    enabled and the active IME — otherwise there'd be no keyboard at all. We discover HeliBoard's
#    IME id dynamically (robust to class renames). Only set it as default if the current IME is
#    gone/stock, so a keyboard you pick later stays.
HB=$(ime list -a -s 2>/dev/null | grep -m1 '^helium314.keyboard/')
if [ -n "$HB" ]; then
  ime enable "$HB" 2>/dev/null
  cur_ime=$(settings get secure default_input_method 2>/dev/null)
  case "$cur_ime" in
    helium314.keyboard/*) : ;;
    *inputmethod.latin*|null|"") ime set "$HB" 2>/dev/null ;;
  esac
fi
MB
  {
    echo "mkdir /system/etc/medion"
    echo "ea_set -f $W/lbl_sf /system/etc/medion security.selinux"
    echo "sif /system/etc/medion mode 040755"
    echo "write $MA /system/etc/medion/Magisk.apk"
    echo "ea_set -f $W/lbl_sf /system/etc/medion/Magisk.apk security.selinux"
    echo "sif /system/etc/medion/Magisk.apk mode 0100644"
    echo "write $(readlink -f "$W/medion-boot.sh") /system/etc/medion/medion-boot.sh"
    echo "ea_set -f $W/lbl_sf /system/etc/medion/medion-boot.sh security.selinux"
    echo "sif /system/etc/medion/medion-boot.sh mode 0100755"
    echo "write $(readlink -f "$W/magisk-env.tar") /system/etc/medion/magisk-env.tar"
    echo "ea_set -f $W/lbl_sf /system/etc/medion/magisk-env.tar security.selinux"
    echo "sif /system/etc/medion/magisk-env.tar mode 0100644"
  } >> "$W/ea.cmd"
  # microG: stage the LSPosed module zip next to Magisk (installed on first boot by medion-boot.sh)
  if [ "$MICROG_ON" = 1 ] && [ -f apps/microg/LSPosed.zip ]; then
    LSZ="$(readlink -f apps/microg/LSPosed.zip)"
    {
      echo "write $LSZ /system/etc/medion/LSPosed.zip"
      echo "ea_set -f $W/lbl_sf /system/etc/medion/LSPosed.zip security.selinux"
      echo "sif /system/etc/medion/LSPosed.zip mode 0100644"
    } >> "$W/ea.cmd"
  fi
  # microG: stage the LSPosed config seed (auto-enables FakeGApps -> signature spoofing)
  if [ "$MICROG_ON" = 1 ] && [ -f "$W/lspd-seed.db" ]; then
    {
      echo "write $(readlink -f "$W/lspd-seed.db") /system/etc/medion/lspd-seed.db"
      echo "ea_set -f $W/lbl_sf /system/etc/medion/lspd-seed.db security.selinux"
      echo "sif /system/etc/medion/lspd-seed.db mode 0100644"
    } >> "$W/ea.cmd"
  fi
else
  echo "  (Magisk not staged — BAKE_MAGISK=0 or no $MAGISK_APK; stub/adb-install path instead)"
fi
debugfs -w -f "$W/ea.cmd" "$SYS" >/dev/null 2>&1
e2fsck -fy "$SYS" >/dev/null 2>&1 || true

# vendor: relax privileged-permission enforcement. Stock ships ro.control_privapp_permissions=
# enforce, which means a privileged app whose signature|privileged perms aren't ALL whitelisted
# makes PackageManagerService throw -> system_server crash-loop -> boot to recovery. microG's
# GmsCore (a priv-app) requests several privileged perms (MODIFY_PHONE_STATE, MANAGE_USB,
# NETWORK_SCAN, START_ACTIVITIES_FROM_BACKGROUND, DUMP, ...), so enforce bootloops the tablet.
# 'log' GRANTS them all (microG fully works) and only logs violations instead of crashing.
# Only touched when microG is baked; a no-microG build keeps stock 'enforce'.
if [ "$MICROG_ON" = 1 ] && debugfs -R "cat /build.prop" "$W/vendor.img" 2>/dev/null | grep -q '^ro.control_privapp_permissions=enforce'; then
  printf 'u:object_r:vendor_file:s0\0' > "$W/lbl_vf"
  debugfs -R "dump /build.prop $W/vendor.build.prop" "$W/vendor.img" 2>/dev/null
  sed -i -E 's/^ro\.control_privapp_permissions=.*/ro.control_privapp_permissions=log/' "$W/vendor.build.prop"
  {
    echo "rm /build.prop"
    echo "write $(readlink -f "$W/vendor.build.prop") /build.prop"
    echo "ea_set -f $W/lbl_vf /build.prop security.selinux"
    echo "sif /build.prop mode 0100600"
  } > "$W/ea.vendor.cmd"
  debugfs -w -f "$W/ea.vendor.cmd" "$W/vendor.img" >/dev/null 2>&1
  e2fsck -fy "$W/vendor.img" >/dev/null 2>&1 || true
  echo "  vendor: ro.control_privapp_permissions enforce -> log (prevents microG priv-app bootloop)"
fi

# product: remove the stock apps we replaced (so there are no duplicates in the launcher). Removing
# the .apk is enough — PackageManager won't find the package. Only runs when the FOSS suite is
# baked (WITH_APPS); gated per-file by a stat so it's a no-op if a name differs on another build.
if [ "$WITH_APPS" = 1 ] && [ -f "$W/product.img" ]; then
  : > "$W/ea.product.cmd"
  # dir:apk  — stock camera / browser / gallery / keyboard (replaced by Fossify/Cromite/HeliBoard)
  for pair in app/Camera:Camera app/MtkBrowser:MtkBrowser app/LatinIME:LatinIME priv-app/MtkGallery2:MtkGallery2; do
    dir="/${pair%%:*}"; apk="$dir/${pair##*:}.apk"
    if debugfs -R "stat $apk" "$W/product.img" 2>/dev/null | grep -qi Type; then
      echo "rm $apk" >> "$W/ea.product.cmd"; echo "  product: removing $apk (stock, replaced)"
    fi
  done
  if [ -s "$W/ea.product.cmd" ]; then
    debugfs -w -f "$W/ea.product.cmd" "$W/product.img" >/dev/null 2>&1
    e2fsck -fy "$W/product.img" >/dev/null 2>&1 || true
  fi
fi

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
