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
BACKUP="${BACKUP:-$HOME/mtkclient/backup_nv}"
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
"$CE" build -t "$IMG" -f Dockerfile .

echo ">>> building the flashable image inside the container ..."
# Ownership of the output:
#   - rootless podman maps container-root -> your host user, so DON'T pass -u (it breaks writes).
#   - docker (rootful) runs as root -> pass -u so the output is owned by you, not root.
UFLAG=()
case "$(basename "$CE")" in docker) UFLAG=(-u "$(id -u):$(id -g)");; esac
"$CE" run --rm "${UFLAG[@]}" \
  -v "$PWD":/work -v "$BACKUP":/backup:ro -w /work \
  "$IMG" bash -c "BACKUP=/backup ./scripts/build-image.sh $* && ./scripts/make-vbmeta-disable.sh"

echo
printf '\033[1;32mDone -> super_unkiosk.img + vbmeta_disable.img in %s\033[0m\n' "$PWD"
echo "Next: flash with NATIVE mtkclient:  scripts/flash.sh super_unkiosk.img vbmeta_disable.img"
