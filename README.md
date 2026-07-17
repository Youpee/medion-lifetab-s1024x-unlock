# Medion Lifetab S1024X — Unlock & De-Google (no root)

> Turn the Aldi kiosk tablet into a clean, de-Googled Android — **without root**: a real launcher and
> a full open-source app suite, built natively on Linux. Everything runs **offline** from your own
> backup and is **fully reversible**.

![License](https://img.shields.io/badge/license-MIT-blue)
![Device](https://img.shields.io/badge/device-Medion%20Lifetab%20S1024X-informational)
![SoC](https://img.shields.io/badge/SoC-MediaTek%20MT6765-orange)
![Android](https://img.shields.io/badge/Android-10-brightgreen)
![Branch](https://img.shields.io/badge/branch-main-blue)

The **ALDI TALK Filial Tablet** (Medion **MD 60447**, retail label **Model S10242**) ships bolted
shut: it boots straight into a single kiosk app (`AldiTalkFilialApp`) — no launcher, no settings,
no apps. This project unlocks it and rebuilds it into a usable, private Android device.

This is the **`main`** branch — the no-root, native Linux build. For root, microG, and the fixes
this build can't do, see [Choose your build](#choose-your-build).

---

## Contents

- [What you get](#what-you-get)
- [Choose your build](#choose-your-build)
- [Device facts](#device-facts)
- [Requirements](#requirements)
- [Quick start](#quick-start)
- [Entering BROM](#entering-brom)
- [The app suite](#the-app-suite)
- [The notification shade](#the-notification-shade)
- [Known limitations](#known-limitations)
- [Repository layout](#repository-layout)
- [Restore & re-flash](#restore--re-flash)
- [Technical deep dive](#technical-deep-dive)
- [Credits](#credits)
- [License](#license)

---

## What you get

- **No kiosk** — a real home screen (Neo-Launcher) instead of `AldiTalkFilialApp`.
- **A full open-source app suite** baked into `/system` — browser, camera, gallery, files,
  keyboard, two app stores, and a task manager. No Google binaries, no trackers.
- **English UI** by default (stock ships German).
- **Debloat** — the stock camera/browser/gallery/keyboard are removed so the open-source ones win.

This build does **not** include root, microG, or a working notification shade — those require root.
See the [`root` branch](../../tree/root).

---

## Choose your build

| Branch | Platform | Result |
|---|---|---|
| **`main`** (you are here) | Arch / Linux, no root | Kiosk removed + launcher + full app suite + debloat + English default. Native build, simplest. |
| [`docker`](../../tree/docker) | Windows / macOS / any Linux, no root | Same result as `main`, but the build runs in a container so it works on any OS. |
| [`root`](../../tree/root) | Arch / Linux | Everything above **plus Magisk root, microG (auto signature spoofing), dark theme, and fixes for ADB / Developer options / shade**. |

> **Honest heads-up:** on the stock Medion `user` image, removing only the kiosk leaves a
> half-broken system — **ADB won't start and Developer options crash Settings**, because the stock
> SELinux policy is incomplete. That's the ROM, not this project, and it **can't be fixed without
> root**. On this branch you get a clean launcher and all the apps, but ADB / Developer options stay
> flaky. Want them fixed? → [`root` branch](../../tree/root).

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
about anything missing (`lpmake`/`avbtool` aren't always packaged there).

---

## Quick start

```bash
git clone https://github.com/Youpee/medion-lifetab-s1024x-unlock
cd medion-lifetab-s1024x-unlock
```

**First run — do all steps.** Coming back to re-flash? See [Restore & re-flash](#restore--re-flash).

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

# 1. Build the image. Downloads + bakes the app suite; produces super_unkiosk.img + vbmeta_disable.img.
#    (Fetches the launcher + apps automatically if missing — needs the network once.)
scripts/build-image.sh
scripts/make-vbmeta-disable.sh

# 2. Flash over BROM (this wipes /data).
scripts/flash.sh super_unkiosk.img vbmeta_disable.img

# 3. Unplug, power on. First boot takes a couple of minutes (fresh /data + dexopt of large apps).
#    Your launcher comes up instead of the Aldi kiosk.

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

## The app suite

`scripts/fetch-apps.sh` downloads each app from its **official** source (F-Droid API or the
project's own GitHub releases — nothing is re-hosted here), pins exact versions in
`apps/VERSIONS.txt`, and `build-image.sh` bakes them into `/system` as **system apps** (they survive
a factory reset and are the defaults). The stock camera/browser/gallery/keyboard are removed and the
UI defaults to **English**.

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
| Running apps / cleaner | **TaskManager** (needs root or Shizuku) | `com.rk.taskmanager` | GitHub `RohitKushvaha01/TaskManager` |

Cromite is chosen over Brave (no crypto wallet/rewards); Fossify over Simple Mobile Tools (which was
acquired by an ad company). `WITH_APPS=0` skips the whole suite; delete APKs from `apps/system/`
before building to trim it.

> **microG** (Google-app compatibility with signature spoofing) needs root, so it is **not** on this
> branch — it ships on the [`root` branch](../../tree/root). **TaskManager** also needs root or
> Shizuku to actually kill apps; on this no-root branch you'd wire it up via Shizuku.

---

## The notification shade

Medion disabled the stock shade at the SystemUI code level — it won't pull down on any build.
SystemUI is platform-signed with Medion's private key, so it can't be rebuilt. The workaround is a
**drop-in shade app** that draws its own panel via Accessibility: **Power Shade** (`com.treydev.pns`),
**Material Notification Shade** (`com.treydev.mns`), or **One Shade** (`com.treydev.ons`).

These are proprietary (there is no open-source shade), so this repo does not redistribute them —
install the **official** APK yourself (never a repackaged "Mod"). **Recommended: Power Shade.**

> On the [`root` branch](../../tree/root) the build auto-configures the shade *and firewalls it off
> the internet* so it can't phone home. On this no-root branch it works via Accessibility, but you
> can't firewall it.

---

## Known limitations

- **ADB / Developer options don't work** — the stock ROM's SELinux policy is incomplete, and under
  *enforcing* the denied binder calls crash adbd and Settings. Fixing this needs root
  (the [`root` branch](../../tree/root) flips SELinux to permissive on boot); a no-root build can't.
- **The notification shade** is disabled by Medion — see above; use a drop-in shade app.
- **Recents / overview** (□ button) is unavailable — the stock ROM points it at a Launcher3 component
  Aldi never shipped, and the QuickStep workaround crashes on file-based encryption.

All three are covered in full in [docs/app-suite.md](docs/app-suite.md).

---

## Repository layout

```
scripts/
  setup.sh               Install dependencies + mtkclient (run once)
  backup-stock.sh        Full stock backup over BROM  (safety net + build donor)
  fetch-apps.sh          Download the pinned app suite → apps/
  build-image.sh         Build super: remove kiosk + launcher + app suite + debloat + English
  make-vbmeta-disable.sh vbmeta with AVB verification off
  flash.sh               Flash super + vbmeta over BROM
  verify.sh              Post-install health check over adb (read-only)
  restore-stock.sh       Restore the factory ROM from your backup
  clean.sh               Free disk space (keeps your backup)
docs/
  app-suite.md           Technical deep dive (apps + build internals)
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
- **Repeat steps 1–2.** Flashing `super` always re-wipes `/data`, so the tablet comes up fresh.

---

## Technical deep dive

[docs/app-suite.md](docs/app-suite.md) documents the hard parts: native-library extraction for
`/system` apps (`UnsatisfiedLinkError`), the privileged-app permission whitelist, debloat, and the
English/default-settings tweaks.

---

## Credits

Reverse-engineering, tooling, and this guide were worked out with the help of **Claude (Anthropic)**.

- Tooling: **mtkclient** (bkerler), android-tools, avbtool.
- Launcher: **Neo-Launcher** (NeoApplications).
- App suite: **Cromite** (uazo), **F-Droid**, **Aurora Store**, **Fossify** (Camera & Gallery),
  **Material Files** (zhanghai), **HeliBoard** (Helium314), **TaskManager** (RohitKushvaha01).

Please support these projects.

## License

MIT — see [LICENSE](LICENSE). This repository ships **no** proprietary Medion/MTK firmware; you work
only with **your own** backup.

> **Disclaimer:** unlocking the bootloader and flashing is done at your own risk. You can void the
> warranty and, if you mishandle it, brick the device — recoverable as long as your backup and BROM
> are intact.

---

<sub>Keywords: ALDI TALK Filial Tablet, Medion MD 60447 / MD60447, Model S10242, Medion Lifetab
S1024X, Aldi kiosk, AldiTalkFilialApp, MediaTek MT6765 / MT8768, medion_l1016b, mtkclient, remove
kiosk, de-Google, debloat. — German: Aldi Tablet entsperren, Kiosk-Modus / Filial-App entfernen,
Medion Lifetab S1024X / S10242 (MD 60447).</sub>
