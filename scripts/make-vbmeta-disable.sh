#!/usr/bin/env bash
# make-vbmeta-disable.sh — generate a vbmeta with AVB verification disabled.
# Needed so the modified /system boots without dm-verity.
set -euo pipefail
OUT="${1:-vbmeta_disable.img}"
command -v avbtool >/dev/null || { echo "avbtool not found"; exit 1; }
avbtool make_vbmeta_image --flags 2 --padding_size 4096 --output "$OUT"
echo "DONE: $OUT (flags=2, verification disabled)"
avbtool info_image --image "$OUT" | grep -iE "Flags|Header" | head -2
echo
echo "Next: scripts/flash.sh super_unkiosk.img $OUT"
