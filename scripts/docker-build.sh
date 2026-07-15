#!/usr/bin/env bash
# docker-build.sh — build the flashable image inside a container (for NON-Arch / Windows / macOS).
# On Arch just use the native flow (scripts/setup.sh + scripts/build-image.sh) — no Docker needed.
#
# This only covers the OFFLINE build (build-image.sh + make-vbmeta-disable.sh). The USB steps
# (backup / unlock / flash) still use NATIVE mtkclient — Docker can't reliably do USB on Win/macOS.
#
# Usage (from repo root):  scripts/docker-build.sh [LAUNCHER.apk] [extra.apk ...]
#   (paths must be inside the repo, e.g. launchers/KISS.apk; no args -> launchers/KISS.apk)
# Env: BACKUP=/path/to/backup_nv (default ~/mtkclient/backup_nv)
set -euo pipefail
cd "$(dirname "$0")/.."
BACKUP="${BACKUP:-${MTK:-$HOME/mtkclient}/backup_nv}"
IMG=medion-unkiosk
# pick the first container engine that actually WORKS (docker if it's set up, else rootless podman)
if [ -z "${CE:-}" ]; then
  for e in docker podman; do
    if command -v "$e" >/dev/null 2>&1 && "$e" info >/dev/null 2>&1; then CE="$(command -v "$e")"; break; fi
  done
  CE="${CE:-$(command -v docker || command -v podman || true)}"   # fall back for the helpful error below
fi
[ -n "$CE" ] || { echo "No docker/podman found. Install one (Linux: podman is easiest; or Docker Desktop on Win/macOS)."; exit 1; }
if ! "$CE" info >/dev/null 2>&1; then
  echo "Can't talk to '$(basename "$CE")'. Make sure it's running and you can use it:"
  echo "  Linux (docker): sudo systemctl enable --now docker && sudo usermod -aG docker \"\$USER\"   (then log out/in)"
  echo "  Linux (podman): usually works rootless out of the box (try: CE=podman $0 $*)"
  echo "  Windows/macOS:  start Docker Desktop and wait until it says 'running'"
  exit 1
fi
[ -f "$BACKUP/super.bin" ] || { echo "No $BACKUP/super.bin — make a backup first with native mtkclient (scripts/backup-stock.sh)."; exit 1; }

echo ">>> [$(basename "$CE")] building toolchain image '$IMG' ..."
echo "    Heads-up on timing (first run only — the image is cached afterwards):"
echo "      * building this image downloads Arch + android-tools/python/git = ~5-10 min,"
echo "        depending on your mirror speed (a silent 'Synchronizing databases' is normal)."
echo "      * the build inside the container is quick (~1-2 min)."
echo "      * flashing later (scripts/flash.sh) writes the 4 GB super = another ~12-14 min."
echo "    So budget ~20 min end to end the first time. Grab a coffee."
echo "    If a download stalls and the build aborts, just re-run this script: the Arch base"
echo "    image is already cached, so it jumps back to the package step and retries a mirror."
"$CE" build -t "$IMG" -f Dockerfile .

echo ">>> building the flashable image inside the container ..."
# Ownership of the output:
#   - rootless podman maps container-root -> your host user, so DON'T pass -u (it breaks writes).
#   - docker (rootful) runs as root -> pass -u so the output is owned by you, not root.
UFLAG=()
case "$(basename "$CE")" in docker) UFLAG=(-u "$(id -u):$(id -g)");; esac
# build-magisk-boot.sh downloads Magisk and build-image.sh auto-runs fetch-apps.sh (the app
# suite, ~400 MB) inside the container, so this run needs network (default on). It reads only
# $BACKUP/boot.bin; outputs (boot_magisk.img, super, apps/) land in the mounted repo.
"$CE" run --rm "${UFLAG[@]}" \
  -v "$PWD":/work -v "$BACKUP":/backup:ro -w /work \
  "$IMG" bash -c "BACKUP=/backup ./scripts/build-magisk-boot.sh \
    && BACKUP=/backup ./scripts/build-image.sh $* \
    && ./scripts/make-vbmeta-disable.sh \
    && ./scripts/build-fixup-module.sh"

echo
printf '\033[1;32mDone -> super_unkiosk.img + vbmeta_disable.img + boot_magisk.img + medion-fixup.zip in %s\033[0m\n' "$PWD"
echo "Next: flash all three with NATIVE mtkclient:"
echo "  scripts/flash.sh super_unkiosk.img vbmeta_disable.img boot_magisk.img"
echo "Then on the tablet: install .work-magisk/Magisk.apk, and medion-fixup.zip via Magisk -> Modules."
