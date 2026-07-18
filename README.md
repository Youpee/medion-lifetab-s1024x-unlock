# Medion Lifetab S1024X — Unlock, De-Google & Root

> Turn the Aldi kiosk tablet into a clean, de-Googled, **rooted** Android — a real launcher,
> a full open-source app suite, working **microG** with signature spoofing, and root via Magisk.
> Everything runs **offline** from your own backup and is **fully reversible**.

![License](https://img.shields.io/badge/license-MIT-blue)
![Device](https://img.shields.io/badge/device-Medion%20Lifetab%20S1024X-informational)
![SoC](https://img.shields.io/badge/SoC-MediaTek%20MT6765-orange)
![Android](https://img.shields.io/badge/Android-10-brightgreen)
![Branch](https://img.shields.io/badge/branch-root-critical)

The **ALDI TALK Filial Tablet** (Medion **MD 60447**, retail label **Model S10242**) ships bolted
shut: it boots straight into a single kiosk app (`AldiTalkFilialApp`) — no launcher, no settings,
no apps. This project unlocks it and rebuilds it into a usable, private Android device.

This is the **`root`** branch — the complete build. Two lighter, no-root variants exist: see
[Choose your build](#choose-your-build).

---

## Contents

- [What you get](#what-you-get)
- [Screenshots](#screenshots)
- [Choose your build](#choose-your-build)
- [Device facts](#device-facts)
- [Requirements](#requirements)
- [Quick start](#quick-start)
- [Entering BROM](#entering-brom)
- [First boot](#first-boot)
- [The app suite](#the-app-suite)
- [microG & signature spoofing](#microg--signature-spoofing)
- [The notification shade](#the-notification-shade)
- [Known limitations](#known-limitations)
- [Repository layout](#repository-layout)
- [Restore & re-flash](#restore--re-flash)
- [Technical deep dive](#technical-deep-dive)
- [Credits](#credits)
- [License](#license)

---

## What you get

After flashing and a couple of automatic settling reboots, `scripts/verify.sh` reports all green:

- **No kiosk** — a real home screen (Neo-Launcher) instead of `AldiTalkFilialApp`.
- **Root** — Magisk, set up clean and automatic, with no "additional setup" nag.
- **A full open-source app suite** baked into `/system` — browser, camera, gallery, files,
  keyboard, two app stores, and a task manager. No Google binaries, no trackers.
- **microG with working signature spoofing** — sign in to a Google account and receive FCM push
  without a single Google blob on the device.
- **Working ADB (as root) and Developer options** — both crash on the plain no-root build; here
  they work.
- **English UI + dark theme** by default (stock ships German).
- **A drop-in notification shade**, auto-configured on boot (the stock shade is disabled by Medion).

---

## Screenshots

| Home | App drawer | microG | Self-check | Magisk |
|:---:|:---:|:---:|:---:|:---:|
| ![Home](docs/screenshots/01-home.png) | ![Drawer](docs/screenshots/02-app-drawer.png) | ![microG](docs/screenshots/03-microg.png) | ![Self-check](docs/screenshots/04-microg-selfcheck.png) | ![Magisk](docs/screenshots/05-magisk.png) |

---

## Choose your build

| Branch | Platform | Result |
|---|---|---|
| **`root`** (you are here) | Arch / Linux | Everything below **plus Magisk root, microG (auto signature spoofing), dark theme, and fixes for ADB / Developer options / shade**. |
| [`main`](../../tree/main) | Arch / Linux, no root | Kiosk removed + launcher + full app suite + debloat + English default. Native build, simplest. |
| [`docker`](../../tree/docker) | Windows / macOS / any Linux, no root | Same result as `main`, but the build runs in a container so it works on any OS. |

> **Why root matters:** on the stock Medion `user` image, removing only the kiosk leaves a
> half-broken system — ADB won't start and Developer options crash Settings, because the stock
> SELinux policy is incomplete. Fixing that requires root, so it only happens on this branch.

---

## Device facts

| | |
|---|---|
| Device | Medion Lifetab **S1024X** (`ro.product.model = LIFETAB S1024X`, build `S1024X_EEA`, flavor `medion_l1016b`) |
| Retail label | **ALDI TALK Filial Tablet** — case/box read **Model S10242**, **MD 60447**. Same device; retail sticker vs. internal `S1024X` codename. |
| SoC | MediaTek MT6765 |
| Stock OS | Android 10, A-only, dynamic partitions (`super`) |
| BROM | Unprotected (SBC/SLA/DAA = false) → mtkclient works with no keys |
| Kiosk app | `/system/priv-app/AldiTalkFilialApp` (the only HOME app in stock) |

---

## Requirements

- An **x86_64 Linux PC**. Arch is first-class; other distros work. On Windows/macOS use the
  [`docker`](../../tree/docker) branch (USB steps via WSL2 + usbipd-win).
- **~15 GB free disk** — the `super` backup alone is 4 GB, plus build workspace and a 4 GB output
  image. Do not build in `/tmp` (it is RAM-backed).
- A **USB data cable**.

`scripts/setup.sh` installs the rest (mtkclient, android-tools, e2fsprogs) and downloads the
launcher APK. On Arch it just works; on Debian/Fedora it installs what the repos provide and warns
about anything missing.

---

## Quick start

```bash
git clone https://github.com/Youpee/medion-lifetab-s1024x-unlock
cd medion-lifetab-s1024x-unlock
git checkout root
```

**First run — do all steps.** Re-flashing? If you already built and haven't run `clean.sh`, you can
skip straight to flashing (step 2) — see [Restore & re-flash](#restore--re-flash).

```bash
# 0a. One-time: install dependencies + mtkclient (also downloads the launcher APK).
scripts/setup.sh

# 0b. Required: full stock backup. This is BOTH your safety net AND the donor the build edits.
#     Put the tablet in BROM first (see below). Takes a few minutes.
scripts/backup-stock.sh

# 0c. Required: unlock the bootloader (otherwise vbmeta_disable is ignored and the modified
#     /system will not boot). Tablet in BROM again, then:
( cd ~/mtkclient && sudo ./venv/bin/python mtk.py da seccfg unlock )
#     "Successfully wrote seccfg" (or "already unlocked") = done. This wipes /data — expected.

# 1. Build everything. Easiest is the container (any OS with Docker/Podman). Produces:
#      super_unkiosk.img   kiosk removed + launcher + app suite + microG + Magisk staging
#      vbmeta_disable.img  AVB verification off
#      boot_magisk.img     Magisk root + the SELinux/ADB boot service
#      medion-fixup.zip    optional Magisk module
#    Needs the network once (Magisk + the app suite are downloaded and pinned).
scripts/docker-build.sh
#    Native (Arch, no Docker) — run in this exact order:
#      scripts/fetch-apps.sh && scripts/build-magisk-boot.sh && scripts/build-image.sh && \
#        scripts/make-vbmeta-disable.sh && scripts/build-fixup-module.sh

# 2. Flash all three over BROM (this wipes /data). The third image is the rooted boot.
scripts/flash.sh super_unkiosk.img vbmeta_disable.img boot_magisk.img

# 3. Unplug, power on, and wait ~5 min — it reboots itself twice (see First boot). Then verify:
scripts/verify.sh

# 4. Optional: free disk space (keeps your stock backup).
scripts/clean.sh
```

### Entering BROM

**BROM** (Boot ROM) is the USB bootloader baked into the SoC. It runs before any of the tablet's
own firmware, so it is always reachable and effectively unbrickable — this is how mtkclient reads
and writes partitions regardless of device state. On the S1024X, BROM is unprotected (no auth keys).

1. **Start the mtkclient command first** — it waits for the device.
2. **Power the tablet off.** A device that isn't booted drops into BROM on connect. If it's stuck
   looping, unplug until it disappears from `lsusb`.
3. **Hold VOLUME-DOWN** (the lower-volume side of the rocker — not Power) and, keeping it held, plug
   in USB. mtkclient catches BROM in 1–2 seconds. Release once it connects.

> Buttons are unlabelled. Holding the tablet with the camera at the top-right, **VOLUME-DOWN is the
> button on the LEFT**:
>
> ![Which button is Volume-Down](docs/volume-buttons.jpg)

If you get `DAA_SIG_VERIFY_FAILED (0x7024)`, the tablet came up in **Preloader** (a later stage),
not BROM. Unplug fully (it must vanish from `lsusb`), then retry — start holding **Vol−** *before*
inserting USB.

---

## First boot

1. First boot takes ~2–3 min (fresh `/data` + first-run dexopt of large apps). It comes straight up
   on Neo-Launcher — no "pick a launcher" prompt.
2. A one-shot boot service flips SELinux to permissive, installs the full Magisk app, populates
   `/data/adb/magisk`, enables Zygisk, installs LSPosed, and seeds microG's spoofing config.
3. **The tablet reboots itself twice — this is expected, not a boot loop:**
   - **Reboot 1** activates **Zygisk** (it only goes live on the next boot; LSPosed can't create its
     config DB until it does).
   - **Reboot 2** loads the **spoofing seed** so LSPosed injects FakeGApps into `system_server`.

   Each reboot is guarded by a marker in `/data/adb`, so it fires exactly once and never loops.
4. It lands on Neo-Launcher for good. Run `scripts/verify.sh` — everything should be green,
   including *"signature spoofing active"*, with no manual taps in LSPosed.

> Do **not** use Magisk's **"Direct Install"** — it re-patches boot and undoes the custom SELinux/ADB
> fix. The build already installs root correctly.

---

## The app suite

`scripts/fetch-apps.sh` downloads each app from its **official** source (F-Droid API or the
project's own GitHub releases — nothing is re-hosted here), pins exact versions in
`apps/VERSIONS.txt`, and `build-image.sh` bakes them into `/system` as **system apps** (they survive
a factory reset and are the defaults). The stock camera/browser/gallery/keyboard are removed.

| Role | App | Package | Source |
|---|---|---|---|
| Launcher | **Neo-Launcher** | `com.saggitt.omega` | GitHub `NeoApplications/Neo-Launcher` |
| Browser | **Cromite** | `org.cromite.cromite` | GitHub `uazo/cromite` (arm64) |
| App store (FOSS) | **F-Droid** | `org.fdroid.fdroid` | f-droid.org |
| App store (Play, anon) | **Aurora Store** | `com.aurora.store` | F-Droid |
| Camera | **Fossify Camera** | `org.fossify.camera` | F-Droid |
| Gallery | **Fossify Gallery** | `org.fossify.gallery` | F-Droid |
| Files | **Material Files** | `me.zhanghai.android.files` | F-Droid |
| Keyboard | **HeliBoard** (offline, no INTERNET permission) | `helium314.keyboard` | F-Droid |
| Running apps / cleaner | **TaskManager** (root/Shizuku) | `com.rk.taskmanager` | GitHub `RohitKushvaha01/TaskManager` |

Cromite is chosen over Brave (no crypto wallet/rewards); Fossify over Simple Mobile Tools (which was
acquired by an ad company). TaskManager stands in for the missing recents screen — it lists and kills
running apps (grant it root when Magisk asks).

---

## microG & signature spoofing

microG replaces Google Play Services, so apps that expect "Google" run **without Google's blobs**
(and, once spoofing is active, you can optionally sign in to a real account). The build bakes
**GmsCore** (privileged), **FakeStore**, **FakeGApps**, and **LSPosed**, then wires up spoofing
automatically across the first boots — no manual taps. When it settles,
**microG Settings → Self-Check** shows *"System spoofs signature ✓"*.

> Key detail: the LSPosed "Vector" fork identifies `system_server` as the package **`system`**, not
> `android` as upstream does. FakeGApps must be scoped to `system` or spoofing silently does nothing.
> Full write-up in [docs/app-suite.md](docs/app-suite.md).

---

## The notification shade

Medion disabled the stock shade at the SystemUI code level (it is stuck at 36 px and won't expand,
even via `cmd statusbar expand-notifications`). SystemUI is platform-signed with Medion's private
key, so it can't be rebuilt. The workaround is a **drop-in shade app** that draws its own panel.

The only apps that do this are Treydev's: **Power Shade** (`com.treydev.pns`),
**Material Notification Shade** (`com.treydev.mns`), **One Shade** (`com.treydev.ons`). They are
proprietary (there is no open-source shade), so this repo does not redistribute them — install the
**official** APK yourself (never a repackaged "Mod").

- **Recommended: Power Shade** (`com.treydev.pns`) — the one this build was tested with. The others
  are the same developer and work identically.
- The boot service auto-detects any installed `com.treydev.*` shade and pre-grants its overlay,
  notification, and accessibility permissions — no manual setup.

---

## Known limitations

- **Recents / overview** (□ button) is unavailable — the stock ROM points it at a Launcher3 component
  that Aldi never shipped. Redirecting it to a QuickStep launcher crashes on file-based encryption, so
  it's not enabled. Use **TaskManager** to see and close running apps instead.
- **No lock screen out of the box** (`lockscreen.password_type = null`) — normal for a fresh `/data`.
  Setting a PIN is untested and may lock you out (the keyguard UI could be broken like the shade). If
  you try one, keep adb connected: `adb shell locksettings clear --old <pin>`.

Both are covered in full in [docs/app-suite.md](docs/app-suite.md).

---

## Repository layout

```
scripts/
  setup.sh               Install dependencies + mtkclient (run once)
  backup-stock.sh        Full stock backup over BROM  (safety net + build donor)
  fetch-apps.sh          Download the pinned app suite (+ microG chain) → apps/
  build-magisk-boot.sh   Patch boot with Magisk offline → boot_magisk.img (root + SELinux/ADB service)
  build-image.sh         Build super: remove kiosk + launcher + app suite + microG + Magisk staging
  make-vbmeta-disable.sh vbmeta with AVB verification off
  build-fixup-module.sh  Optional Magisk module → medion-fixup.zip
  flash.sh               Flash super + vbmeta [+ boot_magisk] over BROM
  verify.sh              Post-install health check over adb (read-only)
  restore-stock.sh       Restore the factory ROM from your backup
  clean.sh               Free disk space (keeps your backup)
  docker-build.sh        Build everything in a container (non-Arch / Windows / macOS)
docs/
  app-suite.md           Technical deep dive (apps, microG, war stories)
  second-monitor-kde.md  Optional: use the tablet as a wireless second monitor
extras/                  Helper scripts (EDID generation, virtual monitor)
```

---

## Restore & re-flash

Revert to bone-stock at any time:

```bash
scripts/restore-stock.sh    # restores the factory Aldi ROM from your backup
```

**Re-flashing or updating the build?** Tools, backup, and unlock are one-time; build and flash you
can repeat freely.

- **Skip `0a` (setup)** if the tools and `~/mtkclient` are still installed.
- **Skip `0b` (backup)** if `~/mtkclient/backup_nv/` still exists — the build reuses it as the donor
  and it's your safety net. **Never delete it.**
- **Skip `0c` (unlock)** if the bootloader is already unlocked (it stays unlocked across flashes;
  re-running is harmless).
- **Skip the build (step 1)** if you already built and **haven't run `scripts/clean.sh`** — the
  images (`super_unkiosk.img`, `vbmeta_disable.img`, `boot_magisk.img`) are still in the repo, so you
  can go straight to **flashing (step 2)**. If you ran `clean.sh` or changed the build, rebuild first.
- **Flashing (step 2) always re-wipes `/data`**, so the first-boot settle happens every time.

---

## Technical deep dive

[docs/app-suite.md](docs/app-suite.md) documents the hard parts in full: native-library extraction
for `/system` apps (`UnsatisfiedLinkError`), the privileged-app permission whitelist, the Magisk
offline patch and boot service, and the complete microG signature-spoofing chain.

---

## Credits

Reverse-engineering, tooling, and this guide were worked out with the help of **Claude (Anthropic)**.

- Tooling: **mtkclient** (bkerler), **Magisk** (topjohnwu), android-tools, avbtool.
- Launcher: **Neo-Launcher** (NeoApplications).
- App suite: **Cromite** (uazo), **F-Droid**, **Aurora Store**, **Fossify** (Camera & Gallery),
  **Material Files** (zhanghai), **HeliBoard** (Helium314), **TaskManager** (RohitKushvaha01).
- microG stack: **GmsCore** (microG), **LSPosed** (JingMatrix), **FakeGApps** (whew-inc).

Please support these projects.

## License

MIT — see [LICENSE](LICENSE). This repository ships **no** proprietary Medion/MTK firmware; you work
only with **your own** backup.

> **Disclaimer:** unlocking the bootloader and flashing is done at your own risk. You can void the
> warranty and, if you mishandle it, brick the device — recoverable as long as your backup and BROM
> are intact, which they always are.

---

<sub>Keywords: ALDI TALK Filial Tablet, Medion MD 60447 / MD60447, Model S10242, Medion Lifetab
S1024X, Aldi kiosk, AldiTalkFilialApp, MediaTek MT6765 / MT8768, medion_l1016b, mtkclient, remove
kiosk, root, Magisk, microG, signature spoofing, SELinux permissive, de-Google, debloat. — German:
Aldi Tablet entsperren, Kiosk-Modus / Filial-App entfernen, Medion Lifetab S1024X / S10242 (MD 60447)
rooten.</sub>
