# Medion Lifetab S1024X — Aldi kiosk removal (unkiosk)

Unlock **Medion Lifetab S1024X** tablets that Aldi shipped locked into the kiosk launcher
**AldiTalkFilialApp**: remove the kiosk, install your own launcher, enable ADB — and use
the tablet as a normal Android device again.

Everything is done **offline by editing the system image over BROM** (mtkclient), with
**no adb and no GSI** — the stock ROM boots normally, TEE/keymaster keep working. Fully
reversible (full backup + restore included).

> Keywords: Medion Lifetab S1024X, Aldi kiosk, AldiTalkFilialApp, MT6765, medion_l1016b,
> achilles6, mtkclient, remove kiosk launcher, enable adb, debloat.

---

## ⚠️ Disclaimer
Unlocking the bootloader and flashing is **at your own risk**: you may void the warranty
and, on mistakes, brick the device (recoverable while your backup + BROM are intact). This
repo contains **no** proprietary Medion/MTK firmware — you work with **your own** backup.
License: MIT.

## Device facts
| | |
|---|---|
| Device | Medion Lifetab S1024X (`medion_l1016b`, board `achilles6`) |
| SoC | MediaTek MT6765 |
| Stock | Android 10, A-only, dynamic partitions (`super`) |
| BROM | unprotected (SBC/SLA/DAA=false) → mtkclient works |
| Kiosk | `/system/priv-app/AldiTalkFilialApp` (the only HOME launcher in stock) |

## Requirements
- **~15 GB free disk space** on the PC — the stock `super` backup alone is 4 GB, and the
  build needs working space plus a 4 GB output image. Don't build in `/tmp` (it's RAM/tmpfs).
- A USB **data** cable and an x86_64 Linux PC.

**Easiest:** run **`scripts/setup.sh`** — it installs everything below + mtkclient (best on
Arch, where the single `android-tools` package provides avbtool + lp* + simg2img). On
Debian/Fedora it installs what the repos have and warns about anything missing.

Manual list (if you prefer):
- **mtkclient** — https://github.com/bkerler/mtkclient (in `~/mtkclient`)
- **android-tools**: `avbtool lpmake lpunpack lpdump simg2img img2simg` (all in one package on Arch)
- **e2fsprogs**: `debugfs e2fsck resize2fs dumpe2fs`
- `python3`, `openssl`, `git`, `libusb`
- Unlocked bootloader (via mtkclient `mtk.py da seccfg unlock`, or fastboot — see mtkclient)
- A launcher `.apk` — **KISS** is downloaded automatically by `setup.sh` (F-Droid, FOSS,
  no ads); or bring your own and pass it to `build-image.sh`.

## What is BROM and how to enter it
**BROM** (Boot ROM) is the USB bootloader baked into the SoC itself. It runs *before* any of
the tablet's own firmware, so it's always reachable and effectively unbrickable — this is how
mtkclient reads/writes partitions no matter what state the tablet is in. On this device BROM
is unprotected (SBC/SLA/DAA off), so no auth is needed.

Enter it like this:
1. **Start the mtkclient command FIRST** — it sits waiting for the device.
2. Make sure the tablet is off / not running (a device that isn't booted drops into BROM on
   connect). If it's stuck in a loop, unplug it so it disappears from `lsusb` first.
3. **Hold Volume Down (−)** and plug in USB. mtkclient catches BROM in ~1-2 seconds.

Notes:
- No timing ritual — you do **not** need to "wait N minutes" or hold Power for X seconds.
- If you get `DAA_SIG_VERIFY_FAILED (0x7024)`, the tablet came up in **Preloader** (a later
  stage), not BROM: unplug fully (it must vanish from `lsusb`), then retry holding **Vol−
  BEFORE** inserting USB.

---

## Steps

Run everything from the repo root:
```bash
git clone https://github.com/Youpee/medion-lifetab-s1024x-unlock && cd medion-lifetab-s1024x-unlock

# 0a) one-time: install all dependencies + mtkclient (+ downloads KISS launcher)
scripts/setup.sh

# 0b) REQUIRED: full stock backup (your safety net + donor for the build)
scripts/backup-stock.sh

# 0c) REQUIRED: unlock the bootloader (else vbmeta_disable is ignored and the
#     modified /system won't boot). Tablet in BROM (Vol- + USB), then:
( cd ~/mtkclient && sudo ./venv/bin/python mtk.py da seccfg unlock )
#     -> "Successfully wrote seccfg" = done ("already unlocked" is fine too).
#        This wipes /data on next boot — expected.

# 1) build the image: remove kiosk + enable ADB + add your launcher
#    (uses launchers/KISS.apk that setup.sh downloaded; or pass your own apk)
scripts/build-image.sh
#   custom launcher + extra apks: scripts/build-image.sh MyLauncher.apk App1.apk App2.apk

# 2) generate a vbmeta with AVB verification disabled
#    (otherwise the modified /system won't boot)
scripts/make-vbmeta-disable.sh

# 3) flash (BROM) + wipe /data
scripts/flash.sh super_unkiosk.img vbmeta_disable.img

# 4) when the flash finishes: unplug and power the tablet on — that's it.
#    Your launcher comes up instead of the Aldi kiosk.
#    (the very first boot after a data wipe may take a couple of minutes — normal)
```

Revert anytime:
```bash
scripts/restore-stock.sh    # restores the factory Aldi ROM
```

## What build-image.sh does
1. Extracts `system/vendor/product` from your `backup_nv/super.bin`.
2. Erases the AVB footer of `system` (verity is turned off via the vbmeta_disable step).
3. Grows the ext4 (+64 MB) to fit extra APKs.
4. `prop.default`: `ro.adb.secure=0`, `ro.debuggable=1`, `persist.sys.usb.config=mtp,adb`
   plus an init override `zz-forceadb.rc` (adbd as root, no on-screen auth prompt).
5. Removes `AldiTalkFilialApp.apk` (kiosk is no longer HOME).
6. Installs your launcher (and extra APKs) into `/system/app/<Name>/` labeled `system_file:s0`.
7. Rebuilds `super` (system + stock vendor/product), verifies size / `lpdump`.

## After boot
- Your launcher comes up. ADB is on (root, no auth): from a PC `adb shell id` → uid=0.
  From there do whatever you like (`adb install` apps, change settings, etc.).
- If the USB gadget doesn't come up by itself on some builds, switching USB to
  "File transfer" from the notification shade/settings usually helps; normally `mtp,adb`
  composes fine.

## Known gotchas
- **`user` build + enforcing SELinux**: on the stripped-down Medion build, the notification
  shade / recents and the "Developer options" menu may not work / may crash. This needs
  root (Magisk) or a permissive policy to fully fix — see `docs/FIX_PLAN.md` if included.
  It does not block a normal "working Android + launcher".
- `debugfs` doesn't set SELinux labels itself → the script sets `system_file:s0` (NUL-terminated).
- Re-sealing verity of the modified `/system` needs the OEM key (not available), so we go
  through `vbmeta_disable` (verification off). On an unlocked bootloader this is fine.

## Layout
```
scripts/
  setup.sh               # install all deps + mtkclient (run once)
  backup-stock.sh        # dump a full stock backup (BROM)
  build-image.sh         # build super: remove kiosk + enable adb + add launcher
  make-vbmeta-disable.sh # vbmeta with AVB verification disabled
  flash.sh               # flash super + vbmeta_disable (BROM)
  restore-stock.sh       # restore stock
  clean.sh               # free disk space (removes regenerable build artifacts; keeps backup)
```

## Bonus: use the tablet as a wireless second monitor
Once unlocked, you can turn the tablet into a low-latency wireless **second monitor** for a
Linux PC via Sunshine (host) + Moonlight (tablet). The KDE Plasma Wayland + AMD setup (the
tricky part: forcing a spare DRM connector as a virtual display so Sunshine's `kms` capture
sees it) is documented in **[docs/second-monitor-kde.md](docs/second-monitor-kde.md)**, with
helper scripts in `extras/` (`make-edid.py`, `vmon.sh`).

## Credits
The reverse-engineering, tooling and documentation here were worked out and written
**with the help of Claude (Anthropic)** — from the initial kiosk analysis and the offline
system-image method to the scripts and this guide — and that stays the workflow going forward.
Tools used: mtkclient (bkerler), android-tools, avbtool. Launcher: KISS — fr.neamar.kiss (F-Droid).
