# Using the tablet as a wireless second monitor (Linux + Sunshine + Moonlight)

Turn the tablet into a low-latency wireless **second monitor** for a Linux PC:
**Sunshine** (host, on the PC) streams a screen, **Moonlight** (client, on the tablet) shows it.

Worked out on **KDE Plasma 6 Wayland + AMD**, but the tricky part — making a *virtual* second
screen that Sunshine can capture — is written to work on **any laptop**, not just one specific
machine. The connector name is auto-detected, so nothing here is hardcoded to a single PC.

> ⚠️ **Experimental — the most fragile part of this repo, and it may not work on your setup.**
> Creating a *virtual* monitor is highly specific to your compositor, GPU and driver. This was built
> and tested only on **KDE Plasma 6 Wayland + AMD**. On a different desktop (GNOME, X11) or GPU
> (NVIDIA / Intel) the virtual-monitor step may need changes or **may not come up at all**. Treat it
> as a starting point to adapt, not a guaranteed feature — nothing else in the repo depends on it.

---

## TL;DR (the whole thing)
```bash
# ON THE PC
python3 extras/make-edid.py ~/.local/share/medion-vm.edid   # one-time: fake 1920x1200 EDID
extras/vmon.sh on                                           # create the virtual monitor
sunshine                                                    # start the host
# ON THE TABLET: open Moonlight, add the PC, pick the "Desktop" app, enter the PIN in the web UI
extras/vmon.sh off                                          # when done (lets the laptop sleep)
```
The rest of this doc explains each piece and how to fix it when a step doesn't work.

> Run it as a **normal user, not with `sudo`** — the script calls `sudo` itself only for the
> DRM sysfs parts; the rest needs your live session. If you get `permission denied`, the exec
> bit is missing — either `chmod +x extras/vmon.sh` (then `./extras/vmon.sh on`) or just run
> `sh extras/vmon.sh on`.

---

## 1. Client (tablet): Moonlight
Install **Moonlight** (`com.limelight`) as a **normal user app**:
https://github.com/moonlight-stream/moonlight-android/releases (`app-nonRoot-release.apk`).
(Installed as a `/system/app` it may crash on native libs — keep it a user app.)

## 2. Host (PC): Sunshine
Install `sunshine` (AUR/repo). The encoder is auto-picked from your GPU — you usually don't
set it by hand:
- **AMD** → `h264_vaapi` (VAAPI)   • **Intel** → `qsv`/VAAPI   • **Nvidia** → `nvenc`.
- Not sure what you have: `lspci | grep -Ei 'vga|3d|display'`.

First run: set web-UI creds, then open the UI:
```bash
sunshine --creds <user> <pass>      # once
sunshine                            # start it
xdg-open https://localhost:47990    # web UI (self-signed cert warning is expected)
```
Open the firewall for the stream: **tcp 47984/47989/47990/48010** + **udp 47998-48000**.

## 3. The virtual monitor (the actual trick)
Sunshine's reliable Wayland capture is `kms`, and `kms` can only capture **real DRM outputs**.
KWin virtual outputs (`krfb-virtualmonitor`) are invisible to it — dead end. What *does* work
on every laptop: most have a **spare, disconnected** video connector (HDMI/DP). Force it "on"
with a fake EDID and it becomes a real 1920x1200 output that `kms` captures — used as an
extended second screen.

`extras/vmon.sh on|off` does this and **auto-detects the spare connector**, so it's portable:
```bash
python3 extras/make-edid.py ~/.local/share/medion-vm.edid   # one-time
extras/vmon.sh on     # picks a disconnected HDMI/DP connector, forces it on, extends the desktop
extras/vmon.sh off    # disables it again
```
> ⚠️ This runs against your **live** desktop session (enables/positions outputs). If you're
> handing commands to someone else, warn them: a flurry of display changes can shuffle windows.

If auto-detect picks wrong, override the connector explicitly:
```bash
CONN=card0-DP-2 extras/vmon.sh on
```

## 4. Point Sunshine at the virtual monitor
`kms` capture selects the screen by **index**, and the index differs per machine. Find it in
Sunshine's own log — it prints a line per output when it starts:
```
Detecting monitor 0 ... eDP-1
Detecting monitor 1 ... HDMI-A-1     <- this index is your output_name
```
Then set `~/.config/sunshine/sunshine.conf`:
```
capture = kms
output_name = 1
stream_audio = disabled
```
> ⚠️ **No trailing spaces or inline `# comments` on these lines.** Sunshine does *not* strip
> them, so `output_name = 0   ` is read literally as `"0   "`, matches no monitor, and you get
> `Couldn't find monitor [<garbage>]` → `Video failed to find working encoder`. If unsure, write
> the file clean in one shot:
> ```bash
> printf 'capture = kms\noutput_name = 0\nstream_audio = disabled\n' > ~/.config/sunshine/sunshine.conf
> ```
> (`output_name` is the index of YOUR virtual output from the log — not always 0/1.)

Restart Sunshine after editing. (On an **X11** session it's simpler: `capture = x11` and
`output_name` is the X screen — no EDID hack needed, `xrandr` can add the mode directly.)

---

## Troubleshooting (this is where the friend's setup broke)
**"I ran the script but Sunshine doesn't see the new monitor."** — Almost always the wrong
connector or the wrong Sunshine index. Check, in order:

1. **List your connectors** — the spare one is `disconnected` (not `eDP` = your laptop panel):
   ```bash
   for c in /sys/class/drm/card*-*/status; do printf '%s = %s\n' "$(basename "${c%/status}")" "$(cat "$c")"; done
   ```
   `vmon.sh on` prints which one it chose (`connector cardX-... -> output ...`). If that's not a
   real spare port, pass `CONN=<name>` yourself.
2. **Did the output actually come up?** After `vmon.sh on`:
   ```bash
   kscreen-doctor -o | grep -A1 -Ei 'hdmi|dp-'   # should show the forced output "enabled"
   ```
   If not, the connector name for the EDID node was wrong (needs debugfs mounted + root).
3. **Sunshine index mismatch.** Re-read the Sunshine log and set `output_name` to the index it
   reports for your virtual output. This is the #1 cause of "capture is black / wrong screen".
4. **Nvidia proprietary + kms** can refuse to capture; try `nvidia_drm.modeset=1` on the kernel
   cmdline, or fall back to an X11 session with `capture = x11`.

**"Video failed to find working encoder" / `Couldn't find monitor [<garbage>]`.** Sunshine
found the monitor list but can't grab a screen. In practice, two causes, check both:
- **Config whitespace (most common!).** A trailing space or `# comment` after `output_name`
  makes Sunshine search for a monitor named `"0   "` and fail — the log shows a *changing*
  garbage number like `Couldn't find monitor [-2090125424]`. Rewrite the config clean:
  ```bash
  printf 'capture = kms\noutput_name = 0\nstream_audio = disabled\n' > ~/.config/sunshine/sunshine.conf
  ```
  When it's right, `config: 'output_name' = 0` appears in the log and the number becomes `[0]`.
- **No hardware encoder.** Sunshine needs a working GPU encoder — Vulkan (`vulkan-radeon`/
  `vulkan-intel`, usually already installed with Mesa) or VAAPI (`libva-mesa-driver`
  `libva-utils`, verify with `vainfo` showing `VAEntrypointEncSlice`). Sunshine auto-picks
  whichever works (`h264_vulkan`, `h264_vaapi`, …).

## Caveats (multi-monitor quirks — annoying, not blockers)
- **New windows jump to the virtual screen.** `kwriteconfig6 --file kwinrc --group Windows --key
  ActiveMouseScreen false` helps; the script already forces the laptop panel as primary.
- **Lid close won't suspend** while the virtual monitor is on (looks like an external monitor).
  Run `vmon.sh off` before closing the lid.
- **Absolute touch is offset** with two screens. Use Moonlight **trackpad mode** (relative), or
  make the tablet the **only** display for 1:1 touch.
- **Match Moonlight's resolution** to the virtual monitor (1920x1200) to avoid stretch.

## Not-KDE / other desktops
`vmon.sh` uses `kscreen-doctor` (KDE) to enable+position the forced output. On GNOME/other
Wayland desktops, do steps 3–4 the same way but **enable and position the new output in your
Display Settings GUI** instead of `kscreen-doctor` (the EDID/DRM force and the Sunshine
`output_name` part are identical). On **X11**, skip the EDID hack entirely: `capture = x11`
plus `xrandr --newmode/--addmode` on a spare output.
