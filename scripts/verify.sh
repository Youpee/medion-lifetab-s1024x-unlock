#!/usr/bin/env bash
# verify.sh — post-install health check over adb. READ-ONLY: it changes nothing on the tablet.
#
# Run it AFTER the tablet has booted to your launcher (give the first boot ~2-3 min to settle;
# microG's spoofing seed triggers one automatic reboot on first setup). Then plug in USB and:
#   scripts/verify.sh
# It prints a colored PASS/FAIL for every part of the build so you can see it all landed.
set -uo pipefail   # deliberately NOT -e: run every check even if some fail

G=$'\033[1;32m'; R=$'\033[1;31m'; Y=$'\033[1;33m'; C=$'\033[1;36m'; B=$'\033[1m'; N=$'\033[0m'
P=0; F=0; W=0
ok(){   printf "  ${G}\xe2\x9c\x94${N}  %-42s ${C}%s${N}\n" "$1" "${2:-}"; P=$((P+1)); }
bad(){  printf "  ${R}\xe2\x9c\x97${N}  %-42s ${Y}%s${N}\n" "$1" "${2:-}"; F=$((F+1)); }
warn(){ printf "  ${Y}\xe2\x9e\x9c${N}  %-42s %s\n" "$1" "${2:-}"; W=$((W+1)); }
sec(){  printf "\n${B}%s${N}\n" "$1"; }
# NOTE: </dev/null on every adb call — otherwise `adb shell` eats the stdin of the while-read
# loops below (it would silently swallow the app/debloat list after the first item).
A(){ adb shell "$@" </dev/null 2>/dev/null | tr -d '\r'; }
has(){ adb shell pm path "$1" </dev/null >/dev/null 2>&1; }
isdir(){ [ "$(A "[ -d $1 ] && echo y")" = y ]; }

printf "${B}${C}================ Medion Lifetab S1024X — install health check ================${N}\n"
adb devices 2>/dev/null | grep -qw device || {
  printf "${R}No device over adb.${N} Plug in USB and make sure the tablet booted to your launcher.\n"; exit 1; }
printf "  device: ${C}%s${N}   Android ${C}%s${N}   build ${C}%s${N}\n" \
  "$(A getprop ro.product.model)" "$(A getprop ro.build.version.release)" "$(A getprop ro.build.id)"

sec "Core"
[ "$(A id | grep -o uid=0)" = uid=0 ] && ok "root (adb shell is uid=0)" || bad "root" "adb shell is not root"
en=$(A getenforce); [ "$en" = Permissive ] && ok "SELinux permissive (the usability fix)" || warn "SELinux" "$en (root branch expects Permissive)"
[ "$(A getprop sys.boot_completed)" = 1 ] && ok "boot completed" || bad "boot not completed"
loc=$(A getprop ro.product.locale); [ "$loc" = en-US ] && ok "language = English" "$loc" || warn "language" "$loc"
A cmd uimode night | grep -qi yes && ok "dark theme on" || warn "dark theme off" "(you may have changed it)"

sec "Launcher"
foc=$(A dumpsys window | grep -m1 mCurrentFocus)
if echo "$foc" | grep -qi "Not Responding"; then bad "launcher is stuck (ANR)" "reboot once, then re-run"
elif has com.saggitt.omega; then ok "Neo-Launcher installed"; else bad "Neo-Launcher not installed"; fi

MG=$(A dumpsys package com.topjohnwu.magisk | grep -m1 versionName= | cut -d= -f2)
if [ -z "$MG" ]; then
  sec "Magisk / microG"
  warn "no Magisk detected" "looks like a no-root (main/docker) build — skipping root checks"
else
  sec "Magisk (root)"
  if [ "$MG" = "1.0" ]; then bad "Magisk is still the STUB (v1.0)" "boot service didn't run"
  else ok "Magisk full app installed" "v$MG"; fi
  nf=$(A "ls /data/adb/magisk" | wc -w); [ "$nf" -ge 6 ] && ok "/data/adb/magisk populated (auto-setup)" "$nf files" || bad "/data/adb/magisk empty" "env setup didn't run"
  # spoofing = FakeGApps injected into system_server (uid 1000). That ALSO proves Zygisk is live,
  # so we use it as the Zygisk signal too (the settings-table query is unreliable through adb).
  spoof=0; A "cat /data/adb/lspd/log/verbose_*.log" | grep 'inc.whew.android.fakegapps' | grep -q ' 1000:' && spoof=1
  { A magisk --sqlite "SELECT * FROM settings" | grep -qi "zygisk.*1" || [ "$spoof" = 1 ]; } \
    && ok "Zygisk enabled" || warn "Zygisk not confirmed" "reboot once more, then re-run"

  sec "microG + signature spoofing (root)"
  has com.google.android.gms && ok "microG GmsCore installed" || bad "microG GmsCore missing"
  isdir /data/adb/modules/zygisk_vector && ok "LSPosed installed" || bad "LSPosed not installed"
  has inc.whew.android.fakegapps && ok "FakeGApps installed" || bad "FakeGApps missing"
  [ "$spoof" = 1 ] && ok "signature spoofing active (system_server)" "System spoofs signature = ON" \
    || warn "spoofing not confirmed from logs" "open microG > Self-Check: 'System spoofs signature'"
fi

sec "Open-source app suite"
while IFS=: read -r p label; do has "$p" && ok "$label" || bad "$label MISSING"; done <<APPS
org.cromite.cromite:Cromite (browser)
org.fdroid.fdroid:F-Droid
com.aurora.store:Aurora Store
org.fossify.camera:Fossify Camera
org.fossify.gallery:Fossify Gallery
me.zhanghai.android.files:Material Files
helium314.keyboard:HeliBoard (keyboard)
APPS
A settings get secure default_input_method | grep -q helium314 && ok "HeliBoard is the default keyboard" || warn "default keyboard is not HeliBoard"

sec "Debloat (stock duplicates removed)"
while IFS=: read -r p label; do has "$p" && bad "$label still present" || ok "$label removed"; done <<STOCK
com.mediatek.camera:stock Camera
com.android.inputmethod.latin:stock Keyboard
STOCK

printf "\n${B}=============================================================================${N}\n"
printf "${B}Result:  ${G}%d passed${N}${B}   ${Y}%d warnings${N}${B}   ${R}%d failed${N}\n" "$P" "$W" "$F"
if [ "$F" = 0 ] && [ "$W" = 0 ]; then printf "${G}${B}All green — the tablet is set up correctly. Enjoy your de-Googled Lifetab.${N}\n"
elif [ "$F" = 0 ]; then printf "${Y}${B}Good — warnings usually clear after one reboot; re-run this to confirm.${N}\n"
else printf "${R}${B}Some checks failed — see the red items above.${N}\n"; fi
