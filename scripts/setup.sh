#!/usr/bin/env bash
# setup.sh — install everything needed for this repo (beginner-friendly).
#   * system tools: android-tools (avbtool, lpmake/lpunpack/lpdump, simg2img/img2simg),
#     e2fsprogs (debugfs/resize2fs/dumpe2fs), python, openssl, git, libusb
#   * mtkclient (cloned to ~/mtkclient, own venv) + its udev rules
#
# Best supported: Arch (all tools are in the `android-tools` package). Debian/Fedora get
# what their repos have + a warning for anything missing (lpmake/avbtool aren't always packaged).
#
# Usage:  ./scripts/setup.sh
set -euo pipefail
MTK_DIR="${MTK:-$HOME/mtkclient}"
REPO="$(cd "$(dirname "$0")/.." && pwd)"

say(){ printf '\n=== %s ===\n' "$*"; }
have(){ command -v "$1" >/dev/null 2>&1; }

say "1) System packages"
if have pacman; then
  sudo pacman -S --needed --noconfirm android-tools e2fsprogs python openssl git libusb
elif have apt; then
  sudo apt update
  sudo apt install -y git python3 python3-venv python3-pip openssl e2fsprogs \
       libusb-1.0-0 android-sdk-libsparse-utils || true
  echo "NOTE (Debian/Ubuntu): lpmake/lpunpack/lpdump and avbtool are usually NOT in the repos."
  echo "  Get them from AOSP 'android-tools'/'aftv-tools' builds or pip (avbtool), then re-run."
elif have dnf; then
  sudo dnf install -y git python3 openssl e2fsprogs libusbx android-tools || true
  echo "NOTE (Fedora): if lpmake/lpunpack/avbtool are missing, install AOSP android-tools manually."
else
  echo "Unknown package manager. Install manually: android-tools (avbtool,lpmake,lpunpack,"
  echo "lpdump,simg2img,img2simg), e2fsprogs, python3, openssl, git, libusb."
fi

say "2) mtkclient (BROM tool)"
if [ -x "$MTK_DIR/venv/bin/python" ]; then
  echo "mtkclient already set up at $MTK_DIR — skipping."
else
  [ -d "$MTK_DIR/.git" ] || git clone --depth 1 https://github.com/bkerler/mtkclient "$MTK_DIR"
  python3 -m venv "$MTK_DIR/venv"
  "$MTK_DIR/venv/bin/pip" install --upgrade pip wheel
  if [ -f "$MTK_DIR/requirements.txt" ]; then
    "$MTK_DIR/venv/bin/pip" install -r "$MTK_DIR/requirements.txt"
  else
    "$MTK_DIR/venv/bin/pip" install "$MTK_DIR"
  fi
fi

say "3) udev rules (USB access without root fights)"
RULES=$(find "$MTK_DIR" -path '*Setup/Linux/*.rules' 2>/dev/null | head -1)
if [ -n "$RULES" ]; then
  sudo cp "$MTK_DIR"/mtkclient/Setup/Linux/*.rules /etc/udev/rules.d/ 2>/dev/null \
    || sudo cp "$(dirname "$RULES")"/*.rules /etc/udev/rules.d/
  sudo udevadm control --reload-rules && sudo udevadm trigger || true
  echo "udev rules installed."
else
  echo "Could not find mtkclient udev rules — flashing may need sudo (that's fine)."
fi

say "4) Launcher (KISS from F-Droid)"
mkdir -p "$REPO/launchers"
if [ -f "$REPO/launchers/KISS.apk" ]; then
  echo "launchers/KISS.apk already present — skipping."
elif have curl && have python3; then
  code=$(curl -fsSL https://f-droid.org/api/v1/packages/fr.neamar.kiss 2>/dev/null \
         | python3 -c 'import sys,json;print(json.load(sys.stdin)["suggestedVersionCode"])' 2>/dev/null || true)
  if [ -n "$code" ] && curl -fSL -o "$REPO/launchers/KISS.apk" "https://f-droid.org/repo/fr.neamar.kiss_${code}.apk"; then
    echo "downloaded launchers/KISS.apk (fr.neamar.kiss build $code)"
  else
    echo "couldn't fetch KISS automatically — download it manually to launchers/KISS.apk:"
    echo "  https://f-droid.org/packages/fr.neamar.kiss/"
  fi
else
  echo "curl/python3 missing — download KISS manually to launchers/KISS.apk:"
  echo "  https://f-droid.org/packages/fr.neamar.kiss/"
fi

say "5) Check"
MISS=0
for t in avbtool lpmake lpunpack lpdump simg2img debugfs resize2fs python3 openssl; do
  have "$t" && printf '  ok  %s\n' "$t" || { printf '  MISSING  %s\n' "$t"; MISS=1; }
done
[ -x "$MTK_DIR/venv/bin/python" ] && echo "  ok  mtkclient ($MTK_DIR)" || { echo "  MISSING  mtkclient"; MISS=1; }
echo
[ "$MISS" = 0 ] && printf '\033[1;32mAll set. Next: scripts/backup-stock.sh\033[0m\n' \
                || printf '\033[1;31mSome tools are missing — install them, then re-run.\033[0m\n'
