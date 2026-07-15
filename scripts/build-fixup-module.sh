#!/usr/bin/env bash
# build-fixup-module.sh — build a Magisk module (medion-fixup.zip) that, once root is
# installed, restores the things Aldi's kiosk left broken:
#   * ADB over USB (force-enable from root — it wouldn't come up without root on this build)
#   * finishes device provisioning (device_provisioned / user_setup_complete), which is what
#     leaves the notification shade / quick-settings gear / recents half-disabled on a fresh
#     /data with no working setup wizard.
#
# Install it AFTER flashing the Magisk-patched boot: open the Magisk app on the tablet,
# Modules -> Install from storage -> medion-fixup.zip -> reboot.
#
# Requires: curl, python3. Run from the repo root.
# Env: MAGISK_VER (default v30.7) — must match build-magisk-boot.sh so the installer matches.
set -euo pipefail
MAGISK_VER="${MAGISK_VER:-v30.7}"
OUT="${OUT:-medion-fixup.zip}"
W=".work-magisk/module"; rm -rf "$W"; mkdir -p "$W/META-INF/com/google/android"

die(){ printf '\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }
for t in curl python3; do command -v "$t" >/dev/null || die "missing tool '$t'"; done

echo "[1/3] Fetching Magisk module installer ($MAGISK_VER)"
curl -fSL -o "$W/META-INF/com/google/android/update-binary" \
  "https://raw.githubusercontent.com/topjohnwu/Magisk/$MAGISK_VER/scripts/module_installer.sh" \
  || die "could not fetch module_installer.sh (check network / MAGISK_VER)"
printf '#MAGISK\n' > "$W/META-INF/com/google/android/updater-script"

echo "[2/3] Writing module.prop + service.sh"
cat > "$W/module.prop" <<PROP
id=medion-fixup
name=Medion S1024X fixup (adb + provisioning)
version=1.0
versionCode=1
author=medion-lifetab-s1024x-unlock (with Claude)
description=Force-enables ADB and finishes provisioning so the shade / quick-settings gear / recents work after removing the Aldi kiosk. Runs at boot as root.
PROP

cat > "$W/service.sh" <<'SVC'
#!/system/bin/sh
# medion-fixup — runs at boot as root (Magisk late_start service).
# Restores adb + finishes provisioning that the kiosk left off. Idempotent.
until [ "$(getprop sys.boot_completed)" = "1" ]; do sleep 2; done
sleep 8   # let system_server / SettingsProvider settle

S=/system/bin/settings

# --- enable adb (framework side) ---
$S put global adb_enabled 1
$S put global development_settings_enabled 1

# --- ADB over USB (best effort; this 'user' build's USB gadget often won't compose adb) ---
resetprop persist.sys.usb.config mtp,adb 2>/dev/null || setprop persist.sys.usb.config mtp,adb

# --- ADB over WiFi/TCP (does NOT need the USB gadget — the reliable channel here) ---
# After the tablet is on WiFi, connect from the PC with:  adb connect <tablet-ip>:5555
setprop service.adb.tcp.port 5555
stop adbd 2>/dev/null || true
start adbd 2>/dev/null || setprop ctl.start adbd

# --- finish provisioning (fixes disabled shade / QS gear / recents on fresh /data) ---
$S put global device_provisioned 1
$S put secure user_setup_complete 1

log -t medion-fixup "applied adb(usb+tcp:5555) + provisioning fixups"
SVC
chmod 0755 "$W/service.sh"

echo "[3/3] Packing $OUT"
rm -f "$OUT"
OUT="$OUT" SRC="$W" python3 - <<'PY'
import os, zipfile, stat
src, out = os.environ["SRC"], os.environ["OUT"]
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    for root, _, files in os.walk(src):
        for f in files:
            p = os.path.join(root, f)
            arc = os.path.relpath(p, src)
            zi = zipfile.ZipInfo(arc)
            zi.compress_type = zipfile.ZIP_DEFLATED
            # keep exec bit on scripts so recovery-side flashing is happy
            mode = 0o755 if arc.endswith(".sh") or arc.endswith("update-binary") else 0o644
            zi.external_attr = (stat.S_IFREG | mode) << 16
            with open(p, "rb") as fh:
                z.writestr(zi, fh.read())
PY
[ -f "$OUT" ] || die "packing failed"
echo "  OK -> $OUT  ($(du -h "$OUT" | cut -f1))"
echo
printf '\033[1;32mDONE: %s\033[0m\n' "$OUT"
echo "Next: copy $OUT to the tablet, then Magisk app -> Modules -> Install from storage -> reboot."
echo "      (recents/overview still needs a Launcher3-QuickStep — see README 'Recents'.)"
