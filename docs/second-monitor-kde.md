# Using the tablet as a wireless second monitor (KDE Plasma Wayland + AMD)

After unlocking (KISS launcher, ADB on), you can use the tablet as a low-latency wireless
**second monitor** for a Linux PC via **Sunshine** (host) + **Moonlight** (tablet client).
This doc captures what actually works on **KDE Plasma 6 Wayland + AMD (VAAPI)** — it was
non-obvious.

## Client (tablet)
Install **Moonlight** (`com.limelight`) — official APK works fine as a normal app:
https://github.com/moonlight-stream/moonlight-android/releases (`app-nonRoot-release.apk`).
(If installed as a `/system/app` it may crash on native libs — install it as a user app.)

## Host (PC): Sunshine
`sunshine` (AUR/repo). This build's capture methods are only `kms`, `wlr`, `x11`:
- `wlr` (zwlr_screencopy) does **not** work on KWin (KDE doesn't implement it).
- **`kms` works** and encodes with `h264_vaapi` on AMD — use `capture = kms`.
- `krfb-virtualmonitor` creates a KWin virtual output, **but `kms` can't see it** (it's
  KWin-internal, not a real DRM output), and this Sunshine has no `kwin`/portal capture.
  → krfb path is a dead end here.

## The virtual monitor: force a spare DRM connector (this is the trick)
`kms` only captures **real DRM outputs**. Laptops usually have a spare disconnected
connector (here `HDMI-A-1`). Force it on with a custom EDID → a real 1920x1200 output that
`kms` captures, positioned as an **extended** second screen:

```bash
# 1) generate a 1920x1200 EDID
python3 extras/make-edid.py /tmp/vm.edid          # or ~/.local/share/medion-vm.edid

# 2) inject it and force the connector on (root)
sudo sh -c 'p=$(ls -d /sys/kernel/debug/dri/*/HDMI-A-1); cp /tmp/vm.edid "$p/edid_override"; \
            echo on > /sys/class/drm/card1-HDMI-A-1/status'

# 3) KWin now sees HDMI-A-1 @ 1920x1200 (extended). Point Sunshine at it:
#    sunshine.conf:  capture = kms   +   output_name = <index of HDMI-A-1 in the KMS list>
#    (find the index in Sunshine's log: "Monitor N is HDMI-A-1"), then restart sunshine.
```

Convenience toggle: **`extras/vmon.sh on|off`** does inject+enable / disable+off.
(It's runtime — cleared on reboot; re-run `vmon on` to bring it back.)

## Sunshine config (`~/.config/sunshine/sunshine.conf`)
```
capture = kms
output_name = 0          # index of the virtual monitor from the KMS monitor list
stream_audio = disabled  # optional
```
First run: set web-UI creds with `sunshine --creds <user> <pass>`, open
`https://localhost:47990`, pair Moonlight (Moonlight shows a PIN → enter it there).
Open the firewall for the stream: ports 47984/47989/47990/48010 (tcp) + 47998-48000 (udp).

## Caveats (KDE multi-monitor quirks — not blockers, but annoying)
- **Windows may open/migrate to the virtual screen.** KDE places new windows on the
  "active" screen. `kwriteconfig6 --file kwinrc --group Windows --key ActiveMouseScreen false`
  helps; also force the laptop as primary (`kscreen-doctor output.eDP-1.priority.1`). For
  precise control use KWin Window Rules, or just drag windows over manually.
- **Lid close won't suspend** while the virtual monitor is on (system sees an "external
  monitor"). Run `vmon off` before closing the lid, or set KDE/logind to suspend anyway.
- **Direct/absolute touch is offset** with two monitors (Moonlight maps input to the whole
  desktop, plus fractional scale). Reliable options: use Moonlight **trackpad mode**
  (relative), or make the tablet the **only** display for 1:1 absolute touch.
- Match Moonlight's resolution to the virtual monitor (e.g. 1920x1200) to avoid stretch.

## Why not simpler tools
KDE Wayland has no `wlr-screencopy`; portal/PipeWire capture wasn't in this Sunshine build;
`krfb-virtualmonitor` outputs aren't visible to `kms`. Forcing a real DRM connector is the
most robust path that works with the capture Sunshine actually has.
