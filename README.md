# Medion Lifetab S1024X — un-kiosk + de-Google (no root)

Aldi sold this tablet **bolted shut**: it boots straight into a kiosk app (`AldiTalkFilialApp`) and
that's all you get. No launcher, no settings, no apps — a €100 paperweight with a store demo on it.

This branch (`main`) frees it **without root**: it removes the kiosk, drops in a real launcher, and
**bakes in a full set of open-source apps** — a browser, camera, gallery, files, keyboard, two app
stores and a task manager. **No Google, no trackers.** Everything is done **offline** from *your own*
backup over BROM (mtkclient) — the stock ROM boots normally, and it's **fully reversible**.

> **Want the deep version?** The **[`root` branch](https://github.com/Youpee/medion-lifetab-s1024x-unlock/tree/root)**
> adds Magisk root, **microG with working signature spoofing**, a dark-theme default, working ADB /
> Developer options, and an auto-firewalled notification shade — i.e. it fixes the things this no-root
> build can't. If you want a *genuinely* usable tablet, that's the one. See the table below.

> Keywords: Medion Lifetab S1024X, Aldi kiosk, AldiTalkFilialApp, MT6765, medion_l1016b, achilles6,
> mtkclient, remove kiosk, de-Google, debloat. (German: *Aldi Tablet entsperren, Kiosk-Modus /
> Filial-App entfernen, Medion Lifetab S1024X.*)

---

## Pick your flavor (three branches)

| Branch | Best for | What you get |
|---|---|---|
| **`main`** (you are here) | Arch / Linux, no root | Kiosk gone + launcher + **the full open-source app suite** + debloat + English default. Native, simplest. |
| **[`docker`](https://github.com/Youpee/medion-lifetab-s1024x-unlock/tree/docker)** | Windows / macOS / any Linux, no root | **Exactly the same result**, but the build runs in a container so it works on any OS. |
| **[`root`](https://github.com/Youpee/medion-lifetab-s1024x-unlock/tree/root)** | a genuinely usable tablet | Everything above **plus Magisk root + microG (auto signature spoofing)**, dark theme, working ADB/Developer options, and an auto-firewalled shade. |

> **Honest heads-up:** on the stock Medion **`user`** image, just removing the kiosk leaves a
> half-broken system — **ADB won't come up and Developer options crash Settings.** That's the ROM's
> incomplete SELinux policy, not our bug, and you can't fix it without root. So on this branch you get
> a clean launcher + all the apps, but ADB/Dev-options stay flaky. Want them fixed? → `root` branch.

---

## ⚠️ The obligatory disclaimer

Unlocking the bootloader and flashing is **at your own risk** — you can void the warranty and, if you
fumble it, brick the device (recoverable as long as your backup + BROM are intact). This repo ships
**no** proprietary Medion/MTK firmware; you work with **your own** backup. License: MIT.

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
- **`scripts/setup.sh`** installs the rest (mtkclient, android-tools, e2fsprogs) and downloads the
  Neo-Launcher APK. On Arch it "just works"; on Debian/Fedora it installs what the repos have and warns
  about the rest (`lpmake`/`avbtool` aren't always packaged there).

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

# 1) BUILD the image. Downloads + bakes the app suite; produces super_unkiosk.img + vbmeta_disable.img.
#    (It fetches the launcher + apps automatically if they're missing — needs the network once.)
scripts/build-image.sh
scripts/make-vbmeta-disable.sh

# 2) FLASH over BROM (this wipes /data).
scripts/flash.sh super_unkiosk.img vbmeta_disable.img

# 3) Unplug, power on. First boot takes a couple of minutes (fresh /data + dexopt of big apps).
#    Your launcher comes up instead of the Aldi kiosk.

# 4) (optional) free disk space — keeps your stock backup:
scripts/clean.sh
```

### Already did this once?

Re-flashing or updating the build? Skip what you already have:

- **Skip `0a` (setup)** if the tools + `~/mtkclient` are still installed.
- **Skip `0b` (backup)** if you still have `~/mtkclient/backup_nv/` — the build reuses it as the donor,
  and it's your safety net either way. *(Never delete it.)*
- **Skip `0c` (unlock)** if the bootloader is already unlocked — it stays unlocked across flashes.
  (Re-running the unlock just says "already unlocked", so it's harmless.)
- **You still do steps 1–2** (build + flash). Flashing `super` always re-wipes `/data`, so the tablet
  comes up fresh regardless.

In short: **tools + backup + unlock are one-time; build + flash you can repeat as often as you like.**

Revert to bone-stock anytime:
```bash
scripts/restore-stock.sh    # puts the factory Aldi ROM back from your backup
```

---

## The open-source app suite

`scripts/fetch-apps.sh` pulls these from their **official** sources (F-Droid API / the projects' own
GitHub releases — nothing is re-hosted here), pins exact versions (`apps/VERSIONS.txt`), and
`build-image.sh` bakes them into `/system` as **system apps** (they survive a factory reset and are the
defaults). The stock camera/browser/gallery/keyboard get removed so ours win, and the UI defaults to
**English**.

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
| Running apps / cleaner | **TaskManager** (needs root or Shizuku) | `com.rk.taskmanager` | GitHub `RohitKushvaha01/TaskManager` |

**Cromite, not Brave** (no crypto wallet / rewards). **Fossify, not Simple Mobile Tools** (those got
bought by an ad company). `WITH_APPS=0` skips the whole suite; delete APKs from `apps/system/` before
building to trim it. Full rationale + build internals are in **[docs/app-suite.md](docs/app-suite.md)**.

> **microG** (Google-app compatibility with signature spoofing) needs root, so it's **not** on this
> branch — it ships on the **[`root` branch](https://github.com/Youpee/medion-lifetab-s1024x-unlock/tree/root)**.
> **TaskManager** needs root or Shizuku to actually kill apps — on this no-root branch you'd set it up
> via Shizuku (or just use the `root` branch, where it works out of the box).

### The notification shade

Heads-up: the **stock notification shade won't pull down** on this build — Medion gutted the shade in
their (platform-signed, un-rebuildable) SystemUI for kiosk use, so it's stuck. The workaround is a
drop-in shade app (**Power Shade** / **Material Notification Shade**, `com.treydev.*`) that draws its own
panel via Accessibility. There is **no open-source shade** (the whole category is one ad-supported dev),
and we won't redistribute a proprietary APK — grab the **official** one yourself (never a "Mod").

**Recommended: Power Shade** (`com.treydev.pns`) — the one this project was tested with; Material Notification Shade / One Shade are the same developer and work the same, so pick whichever.

> On the **`root` branch** the build auto-configures that shade app *and firewalls it off the internet*
> so it can't phone home. Here on no-root it works via Accessibility, but you can't firewall it — one
> more reason the `root` branch is the better experience.

---

## The stuff that fought back

For the curious (and the next person who Googles this device) — a couple of the traps, with the full
gory detail in **[docs/app-suite.md](docs/app-suite.md)**:

- **"Cromite and Material Files just… don't open."** `UnsatisfiedLinkError`. A read-only `/system` app
  can't unpack its native libraries the way a normal install does, and if they're compressed in the APK
  the loader can't use them either. So we extract the deflated `.so`s into `/system/app/<x>/lib/arm64`
  at build time. (Cromite's `libchrome.so` is a chonky 215 MB — surprise.)
- **"ADB / Developer options are dead."** Not fixable here — the stock ROM's SELinux policy is
  incomplete, and under *enforcing* the denied binder calls crash adbd and Settings. The **`root`
  branch** flips SELinux to permissive on boot and it all comes back; a no-root build can't.
- **"…the shade, recents?"** Medion killed the shade at the SystemUI code level (and the platform key to
  rebuild it is Medion's own private key — unobtainable). Recents needs a QuickStep launcher that our
  file-based-encryption setup keeps crashing. Both are covered honestly on the `root` branch.

## Layout

```
scripts/
  setup.sh               # install deps + mtkclient (run once)
  backup-stock.sh        # full stock backup over BROM  (safety net + build donor)
  fetch-apps.sh          # download the pinned app suite -> apps/  (--check just probes URLs)
  build-image.sh         # build super: remove kiosk + launcher + app suite + debloat + English
  make-vbmeta-disable.sh # vbmeta with AVB verification off
  flash.sh               # flash super + vbmeta over BROM
  verify.sh              # post-install health check over adb (read-only)
  restore-stock.sh       # put the factory ROM back
  clean.sh               # free disk space (keeps your backup)
docs/app-suite.md        # the deep technical write-up
```

## Credits

The reverse-engineering, tooling and this guide were worked out **with the help of Claude (Anthropic)**.

Tools: **mtkclient** (bkerler), android-tools, avbtool. Launcher: **Neo-Launcher** (NeoApplications).
Baked-in apps (all from their own official sources): **Cromite** (uazo), **F-Droid**, **Aurora Store**,
**Fossify** Camera & Gallery, **Material Files** (zhanghai), **HeliBoard** (Helium314), **TaskManager**
(RohitKushvaha01). Huge thanks to all of them — please support their projects.
