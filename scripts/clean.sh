#!/usr/bin/env bash
# clean.sh — free disk space after a successful flash by removing REGENERABLE artifacts.
# Keeps your stock backup (restore safety net) and the tiny vbmeta_disable.img / launchers.
# Run from anywhere; operates on the repo root.
set -euo pipefail
cd "$(dirname "$0")/.."
REPO="$(pwd)"

freed=0
rm_if(){ if [ -e "$1" ]; then sz=$(du -sm "$1" 2>/dev/null | cut -f1); freed=$((freed + sz)); rm -rf "$1"; echo "  removed $1 (${sz} MB)"; fi; }

echo "Cleaning regenerable build artifacts in $REPO ..."
rm_if .work
rm_if super_unkiosk.img          # rebuild anytime with scripts/build-image.sh
rm_if test_super.img
rm_if test_vbmeta.img
echo "Freed ~${freed} MB."
echo

echo "KEPT on purpose:"
echo "  - vbmeta_disable.img  (tiny, reusable)"
echo "  - launchers/          (your launcher APKs)"
echo "  - scripts/, docs/, README"
echo
echo "Your STOCK BACKUP is NOT touched (it's your only way back to stock):"
for b in "${BACKUP:-}" "$HOME/mtkclient/backup_nv"; do
  [ -n "$b" ] && [ -d "$b" ] && echo "  - $b  ($(du -sh "$b" 2>/dev/null | cut -f1))"
done
echo "  Delete a backup yourself ONLY if you never plan to restore stock:  rm -rf <path>"
