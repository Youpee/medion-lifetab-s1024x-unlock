# Medion Lifetab S1024X — kiosk removal + ROOT (root branch)

> **This is the `root` branch.** It does everything the base flow does (remove the Aldi
> **AldiTalkFilialApp** kiosk, install a launcher **and a full open-source app suite** — browser,
> camera, gallery, files, keyboard, app stores), **and then roots the tablet with Magisk**, adds
> **microG with working signature spoofing**, and applies the one fix that turns the stripped Medion
> build into a genuinely usable system. If you only want the kiosk gone **plus the app suite** but no
> root, use the `main`/`docker` branch (same apps, minus microG + Magisk). See
> **[docs/app-suite.md](docs/app-suite.md)** for the full app write-up.

On this Medion **`user`** build, just removing the kiosk leaves a half-broken system: **ADB
won't come up, Developer options crash Settings, the notification shade and recents don't
work.** We traced all of that to one thing — the stock **SELinux policy is incomplete, so
under _enforcing_ mode denied binder calls crash adbd, Settings, and framework bits.** So this
branch:
- patches **`boot`** with **Magisk** (offline, over BROM — no PC-side emulator needed), and
- has a boot-time service flip SELinux to **permissive** (`setenforce 0`) + finish provisioning
  + bring up **adb** — after which **root, adb (USB, as root), Developer options and the
  Settings you actually need all work.**

The shade and recents are the only things that stay broken at the SystemUI level (SystemUI is
platform-signed, can't be modified) — see **[After boot](#after-boot--what-you-actually-get-honest)**
for the working workaround (a sideloaded shade app) and the honest recents story.

Everything is done **offline by editing `super` + patching `boot` over BROM** (mtkclient); the
stock ROM boots normally, TEE/keymaster keep working. Fully reversible (full backup + restore).

> Keywords: Medion Lifetab S1024X, Aldi kiosk, AldiTalkFilialApp, MT6765, medion_l1016b,
> achilles6, mtkclient, remove kiosk, root, Magisk, SELinux permissive, enable adb, debloat.

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

## Platform support — the build runs in Docker, so it works everywhere
- **Build** (extract `system`, remove the kiosk, inject a launcher, repack `super`) runs inside
  a container, so it works on **Linux, Windows and macOS** — that's `scripts/docker-build.sh`.
  On **Arch/Linux** you can also build natively without Docker (`scripts/build-image.sh`).
- **Get a container engine:** Linux → `scripts/setup.sh` installs **podman** (rootless, no
  daemon/group hassle); **Windows/macOS** → install **Docker Desktop**
  (https://www.docker.com/products/docker-desktop).
- **USB is NOT in Docker.** `backup-stock.sh`, the unlock and `flash.sh` talk to the tablet over
  USB via native **mtkclient** (Python): Linux runs it directly; on **Windows** use **WSL2 +
  usbipd-win** (or native mtkclient + WinUSB/Zadig); **macOS** runs mtkclient natively.

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
3. **Press and hold the VOLUME-DOWN button** — the lower-volume side of the volume rocker
   (**not** the Power button) — and, keeping it held, plug in the USB cable. mtkclient catches
   BROM in ~1-2 seconds. (You can let go once it connects.)

> **The buttons on the tablet are NOT labelled.** Holding it with the camera at the top-right
> (as in the photo), **VOLUME-DOWN is the button on the LEFT** (`Vol−`):
>
> ![Which button is Volume-Down](docs/volume-buttons.jpg)

Notes:
- No timing ritual — you do **not** need to "wait N minutes" or hold Power for X seconds.
- If you get `DAA_SIG_VERIFY_FAILED (0x7024)`, the tablet came up in **Preloader** (a later
  stage), not BROM: unplug fully (it must vanish from `lsusb`), then retry — start holding
  **VOLUME-DOWN BEFORE** you insert USB.

---

## Steps

**Arch quick start (clone + install everything, one line):**
```bash
git clone https://github.com/Youpee/medion-lifetab-s1024x-unlock && cd medion-lifetab-s1024x-unlock && scripts/setup.sh
```

Then run the rest from the repo root:
```bash
# (already inside the cloned folder)

# 0a) one-time: install all dependencies + mtkclient (+ downloads KISS launcher)  [Arch]
scripts/setup.sh

# 0b) REQUIRED: full stock backup (your safety net + donor for the build)
scripts/backup-stock.sh

# 0c) REQUIRED: unlock the bootloader (else vbmeta_disable is ignored and the
#     modified /system won't boot). Tablet in BROM (HOLD VOLUME-DOWN, then plug in USB), then:
( cd ~/mtkclient && sudo ./venv/bin/python mtk.py da seccfg unlock )
#     -> "Successfully wrote seccfg" = done ("already unlocked" is fine too).
#        This wipes /data on next boot — expected.

# 0d) optional: pre-download the open-source app suite (browser, camera, gallery, files,
#     keyboard, F-Droid, Aurora + the microG chain). build-image.sh does this automatically if
#     apps/ is missing, so this step is only to fetch ahead of time / pin versions:
scripts/fetch-apps.sh          # (scripts/fetch-apps.sh --check just validates the URLs)

# 1) build EVERYTHING in a container (works on any OS with Docker/Podman). Produces:
#    super_unkiosk.img (kiosk removed + launcher + the app suite + microG + Magisk baked in),
#    vbmeta_disable.img, boot_magisk.img (Magisk root + the setenforce/adb boot service),
#    medion-fixup.zip (optional Magisk module).  Needs network once (Magisk + the app suite ~400 MB).
scripts/docker-build.sh
#   custom launcher + extra apks: scripts/docker-build.sh launchers/MyLauncher.apk launchers/App1.apk
#   native (Arch/Linux, no Docker), run in THIS order (build-magisk-boot first so the Magisk
#   app is available to bake into super):
#     scripts/build-magisk-boot.sh && scripts/build-image.sh && \
#       scripts/make-vbmeta-disable.sh && scripts/build-fixup-module.sh

# 2) flash all three (BROM) + wipe /data.  The 3rd arg is the rooted boot.
scripts/flash.sh super_unkiosk.img vbmeta_disable.img boot_magisk.img

# 3) unplug, power on, WAIT ~2-3 min (first boot after wipe + the boot service runs).
#    Your launcher comes up; root is active; adb + Developer options work; and Magisk
#    installs ITSELF as a normal user app (staged in /system, pm-installed on first boot) —
#    open it once and the Superuser tab is ready. No manual reinstall, no stub.

# 4) (optional) free disk space — keeps your stock backup:
scripts/clean.sh          # or: scripts/clean.sh --all  (also removes the container image + KISS)
```

Revert anytime:
```bash
scripts/restore-stock.sh    # restores the factory Aldi ROM
```

## Build with Docker (non-Arch / Windows / macOS)
On **Arch** just use the native flow above — no Docker. On **other systems** you can run the
offline build in a container instead of installing android-tools/e2fsprogs/avbtool yourself:

```bash
# after: git clone ... && cd ...   and after you have a stock backup (see below)
scripts/docker-build.sh            # builds super_unkiosk.img + vbmeta_disable.img in a container
#   custom launcher: put it in launchers/ and: scripts/docker-build.sh launchers/MyLauncher.apk
```
How it works: your repo stays on your disk; the container only provides the build tools and
writes the output back into your folder (owned by you). Costs ~1.2 GB for the toolchain image
(plus the usual build workspace).

**The USB steps are NOT in Docker.** `backup-stock.sh`, the bootloader unlock, and `flash.sh`
talk to the tablet over USB, which Docker can't reliably pass through on Windows/macOS. So:
1. Install **mtkclient** natively (it's just Python) + a USB driver
   (Windows: WinUSB via Zadig; or run everything inside **WSL2** with `usbipd-win`).
2. `backup-stock.sh` → unlock → `docker-build.sh` (or native `build-image.sh`) → `flash.sh`.

> **USB note:** in theory USB should work out of the box, but it's **not guaranteed** —
> MediaTek BROM + USB drivers vary by machine/OS. If mtkclient can't see the tablet, that's a
> driver/OS-level thing beyond this repo — search Google or ask an AI assistant. We can't fix
> USB drivers from here.

## What build-image.sh does
1. Extracts `system/vendor/product` from your `backup_nv/super.bin`.
2. Erases the AVB footer of `system` (verity is turned off via the vbmeta_disable step).
3. Grows the ext4 (auto-sized to fit the app suite + 128 MB margin) to fit the extra APKs.
4. `prop.default`: `ro.adb.secure=0`, `ro.debuggable=1`, `persist.sys.usb.config=mtp,adb`
   plus an init override `zz-forceadb.rc` — a **best-effort** ADB enable (often the USB gadget
   still won't come up on this build; see "After boot").
5. Removes `AldiTalkFilialApp.apk` (kiosk is no longer HOME).
6. Installs your launcher (and extra APKs) into `/system/app/<Name>/` labeled `system_file:s0`.
6b. **Bakes the open-source app suite** (everything `scripts/fetch-apps.sh` put under `apps/`):
    the browser/camera/gallery/files/keyboard/stores go to `/system/app`; **microG's GmsCore**
    goes to `/system/priv-app` with a `privapp-permissions-microg.xml` whitelist (this ROM has
    `ro.control_privapp_permissions=enforce`), and the **LSPosed** module zip is staged for the
    boot service to install. `WITH_APPS=0` skips the suite; `WITH_MICROG=0` skips microG.
7. **Stages the Magisk apk** as a plain file at `/system/etc/medion/Magisk.apk` (from
   `.work-magisk/Magisk.apk`) — the boot service then `pm install`s it on first boot so Magisk
   comes up as a normal **user** app (no stub, and no `UPDATED_SYSTEM_APP` grief). `BAKE_MAGISK=0`
   to skip.
8. Rebuilds `super` (system + stock vendor/product), verifies size / `lpdump`.

**What `build-magisk-boot.sh` does:** downloads Magisk, runs its `boot_patch.sh` **offline** on
your `backup_nv/boot.bin` (x86_64 `magiskboot` on the host, arm64 payload embedded — no qemu),
with `KEEPVERITY=true KEEPFORCEENCRYPT=true` (verity is off via `vbmeta_disable`; leaving the
first-stage fstab untouched is **required** here — trimming it drops `logical,first_stage_mount`
from the `/system` line and the tablet drops to **fastboot**). Then injects an `overlay.d`
init service that on boot does `setenforce 0` + provisioning + adb. Output: `boot_magisk.img`.

## After boot — what you actually get (honest)
With the rooted `boot` flashed, the boot service (overlay.d `medion.rc`) runs at
`sys.boot_completed`: `setenforce 0` (permissive), finish provisioning, enable adb. Result:

**Works:**
- **Your launcher** — no more Aldi kiosk. (KISS calls `su` synchronously at startup to check for
  root; on a rooted device that would hang on the Magisk prompt, so the boot script pre-grants
  the launcher su. This persists in `/data`, so it's reliable from the 2nd boot — on the very
  first boot after a data wipe the launcher may hang once; just reboot and it's fine.)
- **Root** — Magisk, set up **clean and automatically**: the boot service populates
  `/data/adb/magisk` and the boot is patched with `PREINITDEVICE=persist`, so there is **no "Requires
  additional setup" / "reinstall Magisk" nag** — just open the app and the Superuser tab is ready. Do
  **not** use Magisk's "Direct Install"; it would overwrite the custom boot that provides the
  SELinux-permissive fix.
- **ADB over USB, as root.** `adb devices` shows the tablet; `adb shell` is already `uid=0`.
  (adbd only stays up because SELinux is permissive — under enforcing it crash-loops with
  `Could not set SELinux context`, which is also why USB looked "charge-only" before.)
- **Developer options + Settings** — they crashed under enforcing (denied binder calls); under
  permissive they open fine.
- **A full open-source app suite, baked in as system apps** (see next section).
- **English UI + dark theme by default.** Stock ships German; the build sets `ro.product.locale=en-US`
  and the boot service enables system dark mode once (marker-guarded — switch either in Settings
  afterwards and it stays).

### Open-source apps (baked in as system apps)
`scripts/fetch-apps.sh` pulls these from their **official** sources (F-Droid / the projects' own
GitHub releases — nothing is re-hosted here) and `build-image.sh` bakes them into `/system`, so
the tablet is usable out of the box with **no Google and no trackers**:

| Role | App | Package | Source |
|------|-----|---------|--------|
| Browser | **Cromite** | `org.cromite.cromite` | GitHub `uazo/cromite` (arm64) |
| App store (FOSS) | **F-Droid** | `org.fdroid.fdroid` | f-droid.org |
| App store (Play, anon) | **Aurora Store** | `com.aurora.store` | F-Droid |
| Camera | **Fossify Camera** | `org.fossify.camera` | F-Droid |
| Gallery | **Fossify Gallery** | `org.fossify.gallery` | F-Droid |
| Files | **Material Files** | `me.zhanghai.android.files` | F-Droid |
| Keyboard | **HeliBoard** (offline, no INTERNET) | `helium314.keyboard` | F-Droid |

The exact resolved version of each is pinned and written to `apps/VERSIONS.txt`. Trim the set with
`WITH_APPS=0` (skip all) or by deleting APKs from `apps/system/` before you build. The stock
camera/browser/gallery/keyboard are **removed** so your apps become the defaults. The full rationale
(why each app, how native libs are baked, the privapp/boot fixes, the microG machinery) is in
**[docs/app-suite.md](docs/app-suite.md)**.

### microG (Google-app compatibility, root only) — fully automatic
The build bakes **GmsCore** (priv-app + permission whitelist), **FakeStore** (`com.android.vending`
stub) and **FakeGApps**, stages **LSPosed**, and wires up **signature spoofing with no manual taps**:
across the first boots the boot service populates Magisk's env (so **Zygisk** turns on), installs
**LSPosed**, seeds LSPosed's config so **FakeGApps is enabled and scoped to the system framework**, and
reboots once to load it. Once the tablet settles, **microG Settings → Self-Check** shows **"System
spoofs signature ✓"** — sign in under **Google account** and enable **Cloud Messaging** for FCM push.

> The non-obvious bit (and why this took real digging): the LSPosed "Vector" fork calls `system_server`
> the package **`system`**, not `android` like upstream — so FakeGApps must be scoped to `system` or
> spoofing silently never activates. The full write-up — the LSPosed DB schema, the seed, the whole
> chain — is in **[docs/app-suite.md](docs/app-suite.md)**.
>
> `WITH_MICROG=0` skips the whole chain. microG is **root-only** and therefore absent from the
> `main`/`docker` branches (it can't work without root).

**Two SystemUI-level walls that stay broken** (SystemUI is platform-signed → we can't patch it):
- **Notification shade won't expand.** No disable flags, no error — the shade window just never
  opens. **Workaround that fully works:** sideload a shade app that draws its own panel via
  Accessibility. The only apps that do this are **Treydev's** — **Material Notification Shade**
  (`com.treydev.mns`, recommended: the most stock/simple look), **Power Shade** (`com.treydev.pns`)
  or **One Shade** (`com.treydev.ons`). They're all one developer (now under **ZipoApps**, an
  ad/analytics company — the same reason we picked Fossify over Simple Mobile Tools), and there is
  **no open-source shade** (re-implementing the whole panel is too big). Get the **official** apk
  from Play/APKMirror — **never a "Mod"**: a repackaged app that gets Accessibility + root is a
  malware risk.
  - **Ads?** The shade panel itself has none; ads only load inside the app's own settings screen,
    over the network. This build's boot service **blocks that app's internet with the root
    firewall** (by UID), so no ad ever loads and nothing phones home — effectively ad-free and
    tracker-free. (A local "buy Pro" button may remain; the basic shade is free and complete.)
  - **It auto-configures.** Just install any one of the three and **reboot once** — the boot
    service detects it and grants overlay + notification + accessibility access **and** firewalls
    its internet automatically. No adb needed. It runs unprivileged (deny it root — the shade
    doesn't need it). If you'd rather pre-grant by hand:
  ```bash
  adb install-multiple base.apk split_config.hdpi.apk split_config.en.apk   # from the .apkm
  adb shell appops set com.treydev.mns SYSTEM_ALERT_WINDOW allow
  adb shell cmd notification allow_listener com.treydev.mns/com.treydev.shades.NLService1
  adb shell settings put secure enabled_accessibility_services com.treydev.mns/com.treydev.shades.MAccessibilityService
  adb shell settings put secure accessibility_enabled 1
  ```
- **Recents / overview ("square" button) — not available.** Framework wants
  `config_recentsComponentName = com.android.launcher3/...quickstep.RecentsActivity`, but Aldi
  shipped no Launcher3 (the kiosk was the only HOME), so `mRecentsComponent=null`. A working
  overview needs a **Launcher3-QuickStep built as a privileged system app** (QuickStep perms are
  `signature|privileged` and `ro.control_privapp_permissions=enforce` here, so it needs a
  privapp whitelist) — a real, uncertain project on this stripped build. Switch apps via your
  launcher's app drawer instead.

**Note — no lock screen:** out of the box there's no secure lock, simply because no PIN is set
(`lockscreen.password_type=null`) — normal for a fresh `/data`. The device *supports* it
(`android.software.secure_lock_screen`, KeyguardService runs). But whether the keyguard UI is
usable is **untested** and may be broken like the shade, so setting a PIN could lock you out.
If you try one, keep adb connected — you can always clear it:
`adb shell locksettings clear --old <pin>`. For a second-screen/hobby tablet, no lock is fine.

**Add more apps:** **F-Droid** and **Aurora Store** are already installed, so just open them. You
also have root+adb (`adb install app.apk`), can bake extras in at build time
(`build-image.sh Launcher.apk App1.apk …`), or use Cromite + "unknown sources".

## Known gotchas
- **Don't panic at the `reset` "error".** When the device powers off after flashing,
  mtkclient almost always prints `DeviceClass - [Errno 2] Entity not found` right before
  `Reset command was sent`. That is **normal** — the tablet just disconnected. If the write
  hit 100%, you're fine: unplug and boot.
- **Fastboot after flashing the rooted boot?** You used `KEEPVERITY=false` somewhere — this
  device needs `KEEPVERITY=true` (the scripts already do). Recover with the stock boot:
  `mtk.py w boot ~/mtkclient/backup_nv/boot.bin`, then rebuild `boot_magisk.img`.
- **Magisk app shows a greyed-out Superuser tab / `su` says "denied":** that's a *system-app*
  Magisk (the old `BAKE_MAGISK` behaviour, and what happens if you ever `pm install` Magisk into
  `/system/app`). This flow avoids it — Magisk is `pm install`ed as a user app on first boot. If
  you hit it anyway, reinstall Magisk as a normal user app (`adb install .work-magisk/Magisk.apk`).
- **`user` build + enforcing SELinux** is *the* root cause of the broken bits — the boot service
  flips it to permissive (`setenforce 0`). That's a security trade-off (fine for an unlocked
  hobby tablet). If you'd rather stay enforcing, you'd need to add targeted `magiskpolicy` rules
  for every denial (adbd, `system_app` → wificond/vold/…) — impractical here.
- `debugfs` doesn't set SELinux labels itself → the script sets `system_file:s0` (NUL-terminated).
- Re-sealing verity of the modified `/system` needs the OEM key (not available), so we go
  through `vbmeta_disable` (verification off). On an unlocked bootloader this is fine.

## Layout
```
scripts/
  setup.sh               # install all deps + mtkclient (run once)
  backup-stock.sh        # dump a full stock backup (BROM)
  fetch-apps.sh          # download the open-source app suite (+ microG chain) -> apps/  (--check to just probe URLs)
  build-magisk-boot.sh   # patch boot with Magisk offline -> boot_magisk.img (root + setenforce/adb service)
  build-image.sh         # build super: remove kiosk + launcher + app suite + microG + Magisk app
  make-vbmeta-disable.sh # vbmeta with AVB verification disabled
  build-fixup-module.sh  # optional Magisk module (adb + provisioning) -> medion-fixup.zip
  flash.sh               # flash super + vbmeta_disable [+ boot_magisk] (BROM)
  restore-stock.sh       # restore stock
  clean.sh               # free disk space (removes regenerable build artifacts; keeps backup)
  docker-build.sh        # build EVERYTHING in a container (non-Arch / Windows / macOS)
Dockerfile               # build toolchain image (for docker-build.sh)
```

## Bonus: use the tablet as a wireless second monitor
Once unlocked, you can turn the tablet into a low-latency wireless **second monitor** for a
Linux PC via Sunshine (host) + Moonlight (tablet). The tricky part — forcing a spare DRM
connector into a virtual display so Sunshine's `kms` capture sees it — is documented in
**[docs/second-monitor-kde.md](docs/second-monitor-kde.md)**, with helper scripts in `extras/`
(`make-edid.py`, `vmon.sh`). Written on KDE Plasma Wayland + AMD, but the connector is
auto-detected so it's portable across laptops; the doc has a TL;DR, a troubleshooting section
(wrong connector, Sunshine `output_name`, the config-whitespace gotcha, encoders) and X11/other
-desktop notes.

## Credits
The reverse-engineering, tooling and documentation here were worked out and written
**with the help of Claude (Anthropic)** — from the initial kiosk analysis and the offline
system-image method to the scripts and this guide — and that stays the workflow going forward.
Tools used: **mtkclient** (bkerler), **Magisk** (topjohnwu — the root engine this branch is built
on), android-tools, avbtool. Launcher: KISS — fr.neamar.kiss (F-Droid). Shade workaround:
Material Notification Shade / Power Shade (Treydev).

Baked-in open-source apps (fetched from their own official sources, never re-hosted here):
**Cromite** (uazo), **F-Droid**, **Aurora Store**, **Fossify** Camera & Gallery, **Material
Files** (zhanghai), **HeliBoard** (Helium314). microG stack: **GmsCore** (microG), **LSPosed**
(JingMatrix) and **FakeGApps** (whew-inc) for signature spoofing. Huge thanks to all of these
projects — please support them.
