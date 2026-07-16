# Medion Lifetab S1024X — un-kiosk + de-Google + root

Aldi sold this tablet **bolted shut**: it boots straight into a kiosk app (`AldiTalkFilialApp`) and
that's all you get. No launcher, no settings, no apps — a €100 paperweight with a store demo on it.

This repo turns it into a **clean, de-Googled, rooted Android** — a real launcher, a full set of
open-source apps, working **microG** (yes, with signature spoofing that actually works), root via
Magisk, and the one fix that makes this stripped-down build usable at all. Everything is done
**offline** from *your own* backup over BROM (mtkclient) — the stock ROM boots normally, and it's
**fully reversible**.

> **This is the `root` branch** — the full package. Want just the kiosk gone + the app suite, no
> root? Use `main` / `docker` (same apps, minus Magisk + microG). See the branch table below.

We got here by falling into basically every trap this device had to offer. If you like a good "why
did that take three hours" story, there's a whole **[section for that](#the-stuff-that-fought-back)** —
and the deep technical write-up lives in **[docs/app-suite.md](docs/app-suite.md)**.

> Keywords: Medion Lifetab S1024X, Aldi kiosk, AldiTalkFilialApp, MT6765, medion_l1016b, achilles6,
> mtkclient, remove kiosk, root, Magisk, microG, signature spoofing, SELinux permissive, de-Google,
> debloat. (German: *Aldi Tablet entsperren, Kiosk-Modus / Filial-App entfernen, Medion Lifetab
> S1024X rooten.*)

---

## 👉 What you actually end up with

After a flash and a couple of self-settling reboots, `scripts/verify.sh` prints all green and you have:

- 🚫 **No more Aldi kiosk** — a real home screen (**Neo-Launcher**).
- 🧩 **A full open-source app suite baked in** — browser, camera, gallery, files, keyboard, two app
  stores, a task manager. **No Google, no trackers.** (Stock camera/browser/gallery/keyboard removed.)
- 🌍 **English UI + dark theme** by default (stock ships German).
- 🔓 **Root** (Magisk), **ADB over USB as root**, working **Developer options** — all of which are
  broken on the plain no-root build (see below).
- 📲 **microG with working signature spoofing** → you can sign in to a Google account and get FCM push,
  without a single Google binary on the device.
- 🪟 A **notification shade** you install yourself in one step (the native shade is bricked by Medion —
  long story), auto-configured on boot so it just works.

---

## Pick your flavor (three branches)

| Branch | Best for | What you get |
|---|---|---|
| **[`main`](https://github.com/Youpee/medion-lifetab-s1024x-unlock)** | Arch / Linux, no root | Kiosk gone + launcher + **the full open-source app suite** + debloat + English default. Native, simplest. |
| **[`docker`](https://github.com/Youpee/medion-lifetab-s1024x-unlock/tree/docker)** | Windows / macOS / any Linux, no root | **Exactly the same result**, but the build runs in a container so it works on any OS. |
| **`root`** (you are here) | a genuinely usable tablet | Everything above **plus Magisk root + microG (with auto signature spoofing)**, dark-theme default, and the fixes for what the stripped Medion build leaves broken. |

> **Heads-up about the no-root build:** on the stock Medion **`user`** image, just removing the kiosk
> leaves a half-broken system — **ADB won't come up, Developer options crash Settings**, etc. That's
> not our bug, it's the ROM (details below). If you want those *actually fixed*, you want this branch.

---

## ⚠️ The obligatory disclaimer

Unlocking the bootloader and flashing is **at your own risk** — you can void the warranty and, if you
fumble it, brick the device (recoverable as long as your backup + BROM are intact, which they always
are). This repo ships **no** proprietary Medion/MTK firmware; you work with **your own** backup.
License: MIT.

---

## Device facts

| | |
|---|---|
| Device | Medion Lifetab S1024X (`medion_l1016b`, board `achilles6`) |
| SoC | MediaTek MT6765 |
| Stock | Android 10, A-only, dynamic partitions (`super`) |
| BROM | unprotected (SBC/SLA/DAA = false) → mtkclient just works |
| Kiosk | `/system/priv-app/AldiTalkFilialApp` (the only HOME app in stock) |

## What you need

- **An x86_64 Linux PC** (Arch is first-class; other distros work; Windows/macOS → use the `docker`
  branch, USB steps via WSL2 + usbipd-win).
- **~15 GB free disk** — the `super` backup alone is 4 GB and the build needs working space + a 4 GB
  output image. Don't build in `/tmp` (it's RAM).
- A **USB data cable**.
- **`scripts/setup.sh`** installs everything else (mtkclient, android-tools, e2fsprogs, and downloads
  the Neo-Launcher APK). On Arch it "just works"; on Debian/Fedora it installs what the repos have and
  warns about the rest.

---

## What is BROM, and how do I get into it?

**BROM** (Boot ROM) is the USB bootloader baked into the SoC itself. It runs *before* any of the
tablet's own firmware, so it's always reachable and basically unbrickable — this is how mtkclient
reads/writes partitions no matter what state the tablet is in. On this device BROM is unprotected, so
no auth keys are needed.

To enter it:
1. **Start the mtkclient command first** — it sits there waiting.
2. Tablet **off** (a device that isn't booted drops into BROM on connect). If it's stuck looping,
   unplug it until it disappears from `lsusb`.
3. **Press and hold VOLUME-DOWN** — the lower-volume side of the rocker, **not** Power — and, keeping
   it held, plug in USB. mtkclient catches BROM in ~1–2 seconds. Let go once it connects.

> **The buttons aren't labelled.** Holding the tablet with the camera at the top-right (as in the
> photo), **VOLUME-DOWN is the button on the LEFT** (`Vol−`):
>
> ![Which button is Volume-Down](docs/volume-buttons.jpg)

If you get `DAA_SIG_VERIFY_FAILED (0x7024)`, the tablet came up in **Preloader** (a later stage), not
BROM: unplug fully (must vanish from `lsusb`), then retry — start holding **Vol−** *before* you insert
USB.

---

## Steps

```bash
git clone https://github.com/Youpee/medion-lifetab-s1024x-unlock && cd medion-lifetab-s1024x-unlock
git checkout root
```

**First time? Do all of these.** (Coming back for a re-flash? Jump to the [returning-user note](#already-did-this-once).)

```bash
# 0a) one-time: install deps + mtkclient (+ downloads the Neo-Launcher APK)   [Arch/Linux]
scripts/setup.sh

# 0b) REQUIRED: a full stock backup. This is BOTH your safety net AND the donor the build edits.
#     Tablet in BROM (hold Vol−, plug USB). Takes a few minutes.
scripts/backup-stock.sh

# 0c) REQUIRED: unlock the bootloader (otherwise vbmeta_disable is ignored and the modified /system
#     won't boot). Tablet in BROM again, then:
( cd ~/mtkclient && sudo ./venv/bin/python mtk.py da seccfg unlock )
#     -> "Successfully wrote seccfg" = done ("already unlocked" is fine). This wipes /data — expected.

# 1) BUILD everything. Easiest is the container (works on any OS with Docker/Podman). Produces:
#      super_unkiosk.img   (kiosk gone + Neo-Launcher + the whole app suite + microG + Magisk baked in)
#      vbmeta_disable.img  (AVB verification off)
#      boot_magisk.img     (Magisk root + the setenforce/adb boot service)
#      medion-fixup.zip    (optional Magisk module)
#    Needs the network once (Magisk + the ~400 MB app suite are downloaded and pinned).
scripts/docker-build.sh
#   Native (Arch, no Docker) — run in THIS order (build-magisk-boot first, so the Magisk app exists
#   to bake into super):
#     scripts/fetch-apps.sh && scripts/build-magisk-boot.sh && scripts/build-image.sh && \
#       scripts/make-vbmeta-disable.sh && scripts/build-fixup-module.sh

# 2) FLASH all three over BROM (this wipes /data). The 3rd arg is the rooted boot.
scripts/flash.sh super_unkiosk.img vbmeta_disable.img boot_magisk.img

# 3) Unplug, power on. Let it settle (~5 min): it reboots ITSELF TWICE (Zygisk on, then microG spoofing).
#    Then run the health check — it should be all green:
scripts/verify.sh

# 4) (optional) free disk space — keeps your stock backup:
scripts/clean.sh
```

### Already did this once?

If you've flashed before and are just **re-flashing or updating the build**, you can skip the setup you
already did:

- **Skip `0a` (setup)** if the tools + `~/mtkclient` are still installed.
- **Skip `0b` (backup)** if you still have `~/mtkclient/backup_nv/` — the build reuses it as the donor,
  and it's your safety net either way. *(Never delete it.)*
- **Skip `0c` (unlock)** if the bootloader is already unlocked — it stays unlocked across flashes.
  (`mtk.py da seccfg unlock` just says "already unlocked" if you re-run it, so re-running is harmless.)
- **You still do steps 1–2** (build + flash). Flashing `super`/`boot` always re-wipes `/data`, so the
  tablet comes up fresh regardless — that's why the first-boot settle happens every time.

In short: **tools + backup + unlock are one-time; build + flash you can repeat as often as you like.**

Revert to bone-stock anytime:
```bash
scripts/restore-stock.sh    # puts the factory Aldi ROM back from your backup
```

---

## After the flash — what happens on first boot

1. First boot takes ~2–3 min (fresh `/data` + first-run dexopt of big apps like Cromite/microG). It
   comes straight up on **Neo-Launcher** — no "pick a launcher" prompt.
2. The boot service quietly does its thing: flips SELinux to permissive, installs the full Magisk app,
   sets up `/data/adb/magisk`, turns on Zygisk, installs LSPosed, and **seeds microG's spoofing config**.
3. **The tablet then reboots itself TWICE, on its own** — this is expected, not a boot loop:
   - **Reboot 1** switches **Zygisk** on. Zygisk only becomes active *after* a reboot, and LSPosed can't
     run (and can't create its config DB) until it is — so this reboot is what actually brings it to life.
   - **Reboot 2** loads the **spoofing config**: on the boot after LSPosed created its DB, the service
     drops in our seed and reboots once more so LSPosed injects FakeGApps into `system_server`.
   Each reboot is a one-shot guarded by a marker in `/data/adb`, so it fires exactly once and never loops.
4. It lands on Neo-Launcher for good. Run **`scripts/verify.sh`** and you should see all green —
   including *"signature spoofing active"* — with **no manual taps in LSPosed, ever**.

*(Unlike the old KISS launcher we started with, Neo-Launcher doesn't hang on the root check, so there's
no "if it freezes, reboot it yourself" dance — the two reboots above are automatic and only for
turning Zygisk + microG spoofing on. Full mechanics in [docs/app-suite.md](docs/app-suite.md).)*

---

## What works (the honest list)

**Fixed / working:**
- **Neo-Launcher** as home, plus the full app suite (below).
- **Root** — Magisk, set up clean and automatic. No "additional setup" / "reinstall" nag (we patch the
  boot with `PREINITDEVICE=persist` and pre-populate `/data/adb/magisk` — see the war stories). Just
  **don't** hit Magisk's "Direct Install"; it would overwrite our custom boot and undo the SELinux fix.
- **ADB over USB, as root** (`adb shell` is already `uid=0`), and **Developer options + Settings** —
  both of which *crash* on the plain build because the stock SELinux policy is incomplete and, under
  *enforcing*, denied binder calls kill adbd/Settings. The boot service flips SELinux to **permissive**
  and it all comes back.
- **English + dark theme** by default (change either in Settings; it sticks).
- **microG with signature spoofing** → Google account login + FCM push (see the app section).

**Still broken (and why):**
- **The notification shade won't pull down.** This one's on Medion — [full autopsy below](#the-notification-shade). Fix = a drop-in shade app.
- **Recents ("□" overview) isn't available.** Also a rabbit hole — [see below](#recents-the-one-we-couldnt-win).

**Note — no lock screen:** out of the box there's no PIN (`lockscreen.password_type=null`) — normal for
a fresh `/data`. Setting one is untested and might lock you out (the keyguard UI could be broken like
the shade), so for a hobby/second-screen tablet, leaving it open is fine. If you try a PIN, keep adb
connected: `adb shell locksettings clear --old <pin>`.

---

## The open-source app suite

`scripts/fetch-apps.sh` pulls these from their **official** sources (F-Droid API / the projects' own
GitHub releases — nothing is re-hosted here), pins exact versions (`apps/VERSIONS.txt`), and
`build-image.sh` bakes them into `/system` as **system apps** (so they survive a factory reset and are
the defaults). The stock camera/browser/gallery/keyboard get removed so ours win.

| Role | App | Package | Source |
|---|---|---|---|
| Launcher | **Neo-Launcher** | `com.saggitt.omega` | GitHub `NeoApplications/Neo-Launcher` |
| Browser | **Cromite** | `org.cromite.cromite` | GitHub `uazo/cromite` (arm64) |
| App store (FOSS) | **F-Droid** | `org.fdroid.fdroid` | f-droid.org |
| App store (Play, anon) | **Aurora Store** | `com.aurora.store` | F-Droid |
| Camera | **Fossify Camera** | `org.fossify.camera` | F-Droid |
| Gallery | **Fossify Gallery** | `org.fossify.gallery` | F-Droid |
| Files | **Material Files** | `me.zhanghai.android.files` | F-Droid |
| Keyboard | **HeliBoard** (100% offline, no INTERNET) | `helium314.keyboard` | F-Droid |
| Running apps / cleaner | **TaskManager** (root/Shizuku) | `com.rk.taskmanager` | GitHub `RohitKushvaha01/TaskManager` |

**Cromite, not Brave** (no crypto wallet / rewards). **Fossify, not Simple Mobile Tools** (those got
bought by an ad company — same reason we avoid the shade apps below). **TaskManager** is your stand-in
for the missing recents: it lists running apps and kills them (grant it root — Magisk will ask).

### microG (root only) — signature spoofing, automatic

microG replaces Google Play Services so apps that need "Google" run **without Google's blobs and without
an account** (though you *can* sign in once spoofing works). The build bakes **GmsCore** (privileged),
**FakeStore**, **FakeGApps**, and **LSPosed**, then wires up spoofing **with zero manual taps** — across
the first boots it enables Zygisk, installs LSPosed, seeds the config, and reboots once. When it settles,
**microG Settings → Self-Check** shows **"System spoofs signature ✓"**.

> The one non-obvious detail (and one of the war stories): the LSPosed "Vector" fork calls
> `system_server` the package **`system`**, not `android` like upstream — scope FakeGApps to the wrong
> one and spoofing silently does nothing. Full write-up in **[docs/app-suite.md](docs/app-suite.md)**.

### The notification shade

The stock shade won't open, so the shade comes from a **drop-in app** you install once. The only apps
that draw their own shade panel are **Treydev's** — **Power Shade** (`com.treydev.pns`), **Material
Notification Shade** (`com.treydev.mns`), **One Shade** (`com.treydev.ons`). They're all one dev, now
under an ad company, and **there is no open-source shade** (we checked, repeatedly — the whole category
is this one company).

**Recommended: Power Shade** (`com.treydev.pns`) — it's the one this build was tested with. Material
Notification Shade and One Shade are the same developer and work the same, so pick whichever; the boot
service handles any of them.

- **You install it yourself.** It's proprietary and not on F-Droid, so we won't redistribute it — grab
  the **official** APK (Play/APKMirror) and sideload it. **Never a "Mod"**: a repackaged app that asks
  for Accessibility is a malware risk.
- **Then it just works.** The boot service auto-detects any `com.treydev.*` shade you install and
  pre-grants its overlay + notification + accessibility, so you don't have to hunt through Settings.

---

## The stuff that fought back

A short tour of the traps, for the curious (and for the next poor soul who Googles this device). Full
gory detail in **[docs/app-suite.md](docs/app-suite.md)**.

- **"I flashed it and it booted to recovery."** microG's `GmsCore` is a privileged app, and this ROM
  *enforces* the priv-app permission whitelist. GmsCore asks for privileged perms we hadn't whitelisted
  (`MODIFY_PHONE_STATE`, `MANAGE_USB`, `NETWORK_SCAN`, …), so `PackageManagerService` threw a tantrum,
  `system_server` crash-looped, and the bootloader nope'd out to recovery. Fix: flip
  `ro.control_privapp_permissions` to `log` in `/vendor/build.prop` — grants them all, never fatal.
- **"Cromite and Material Files just… don't open."** `UnsatisfiedLinkError`. A read-only `/system` app
  can't unpack its native libraries the way a normal install does, and if they're compressed in the APK
  the loader can't use them either. So we extract the deflated `.so`s into `/system/app/<x>/lib/arm64`
  at build time. (Cromite's `libchrome.so` is a chonky 215 MB — surprise.)
- **"Magisk keeps nagging to reinstall."** Two nags, actually. One because `/data/adb/magisk` was empty
  (we now pre-populate it from a baked tarball). The other — *"reinstall Magisk, recovery mode can't get
  device info"* — because an offline patch never set `PREINITDEVICE`. We pass `PREINITDEVICE=persist` and
  both nags vanish. **Do not** click its "Direct Install" — it re-patches boot and eats our SELinux fix.
- **"microG says spoofing is off even though FakeGApps is loaded."** The single most time-consuming line
  of this whole project: the LSPosed fork identifies `system_server` as package **`system`**, not
  `android`. Scoped to `android`, FakeGApps loaded into the microG process but *never into
  system_server*, so the framework never spoofed. Add `system` to the scope → instantly green.
- **"Can't we just fix the shade?"** No. The `NotificationPanel` window is code-locked at 36 px and won't
  expand even via `cmd statusbar expand-notifications` — Medion gutted the shade in their SystemUI for
  kiosk use. It's not a flag, a policy, or an overlay we can flip; it's baked into a **platform-signed**
  app. And the platform key is **Medion's own private key** (`O=MEDION AG`), not the public AOSP test key
  and not in the 2022 OEM-key leaks — so we can't rebuild/re-sign it. Hence a drop-in shade app.
- **"…recents, then?"** See below. Spoiler: file-based encryption said no.

### Recents (the one we couldn't win)

The overview/recents screen points at `com.android.launcher3/…RecentsActivity`, which doesn't exist here
(the kiosk was the only launcher). The **QuickSwitch** approach (redirect recents to a Launcher3-based
launcher via a Magisk overlay) *works* — we got the component to repoint to Lawnchair. But every
QuickStep launcher's `TouchInteractionService` then crashes on **file-based encryption / user-unlock**
(`isUserUnlocked()` NPE, null binding to the overview proxy). Lawnchair 14 didn't even launch on Android
10; Lawnchair 12.1 launched but its QuickStep never bound. The only thing that would likely fix it is
turning off `/data` encryption — a real security downgrade for a recents button, so we didn't. Use
**TaskManager** (in the suite) to see and close running apps instead.

---

## Health check

After it boots, `scripts/verify.sh` reads the tablet over adb (read-only) and prints a colored
pass/fail for every part of the build — root, SELinux, language, dark theme, Magisk, Zygisk, microG
spoofing, every app, the debloat, and the keyboard. If everything's green, you're done.

## Layout

```
scripts/
  setup.sh               # install deps + mtkclient (run once)
  backup-stock.sh        # full stock backup over BROM  (safety net + build donor)
  fetch-apps.sh          # download the pinned app suite (+ microG chain) -> apps/  (--check just probes URLs)
  build-magisk-boot.sh   # patch boot with Magisk offline -> boot_magisk.img (root + setenforce/adb service)
  build-image.sh         # build super: remove kiosk + launcher + app suite + microG + Magisk staging
  make-vbmeta-disable.sh # vbmeta with AVB verification off
  build-fixup-module.sh  # optional Magisk module -> medion-fixup.zip
  flash.sh               # flash super + vbmeta [+ boot_magisk] over BROM
  verify.sh              # post-install health check over adb (read-only)
  restore-stock.sh       # put the factory ROM back
  clean.sh               # free disk space (keeps your backup)
  docker-build.sh        # build EVERYTHING in a container (non-Arch / Windows / macOS)
docs/app-suite.md        # the deep technical write-up
```

## Credits

The reverse-engineering, tooling and this guide were worked out **with the help of Claude (Anthropic)** —
from the first kiosk analysis and the offline image method to the scripts and the war stories above.

Tools: **mtkclient** (bkerler), **Magisk** (topjohnwu — the root engine this branch is built on),
android-tools, avbtool. Launcher: **Neo-Launcher** (NeoApplications). Baked-in apps (all from their own
official sources): **Cromite** (uazo), **F-Droid**, **Aurora Store**, **Fossify** Camera & Gallery,
**Material Files** (zhanghai), **HeliBoard** (Helium314), **TaskManager** (RohitKushvaha01). microG stack:
**GmsCore** (microG), **LSPosed** (JingMatrix), **FakeGApps** (whew-inc). Shade helper: Treydev. Huge
thanks to all of them — please support their projects.
