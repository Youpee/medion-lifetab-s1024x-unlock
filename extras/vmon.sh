#!/bin/sh
# vmon.sh on|off — toggle a virtual second monitor (tablet via Sunshine on KDE Wayland).
#
# Auto-detects a spare (disconnected) DRM connector on THIS machine and forces it on with a
# fake 1920x1200 EDID, so Sunshine's `kms` capture sees a real extra output. The connector is
# NOT hardcoded, so it works on any laptop — not just the one it was written on.
#
# Override the auto-pick if needed:   CONN=card0-DP-2 vmon.sh on
# Needs: an EDID at $EDID (make with extras/make-edid.py) and root for DRM sysfs.
# See docs/second-monitor-kde.md.

export XDG_RUNTIME_DIR=/run/user/$(id -u)
export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u)/bus
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-$(basename "$(ls "$XDG_RUNTIME_DIR"/wayland-[0-9] 2>/dev/null | head -1)" 2>/dev/null)}"
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}"

EDID="${EDID:-$HOME/.local/share/medion-vm.edid}"

# laptop panel (connected eDP/LVDS) — kept as the primary screen
detect_panel() {
  for c in /sys/class/drm/card*-*/status; do
    n=$(basename "${c%/status}")
    case "$n" in *eDP*|*LVDS*) [ "$(cat "$c")" = connected ] && { echo "${n}" | sed 's/^card[0-9]*-//'; return; };; esac
  done
  echo eDP-1
}

# spare connector: disconnected, prefer HDMI then DP, never the panel/virtual
pick_conn() {
  for want in HDMI DP ANY; do
    for c in /sys/class/drm/card*-*/status; do
      n=$(basename "${c%/status}")
      case "$n" in *eDP*|*LVDS*|*Writeback*|*VIRTUAL*) continue;; esac
      [ "$(cat "$c")" = disconnected ] || continue
      case "$want:$n" in HDMI:*HDMI*|DP:*DP*|ANY:*) echo "$n"; return;; esac
    done
  done
}

list_conns() {
  for c in /sys/class/drm/card*-*/status; do
    printf '  %s = %s\n' "$(basename "${c%/status}")" "$(cat "$c")"
  done
}

CONN="${CONN:-$(pick_conn)}"
if [ -z "$CONN" ]; then
  echo "no spare DRM connector found. connectors on this machine:"; list_conns
  echo "pick a 'disconnected' one and rerun: CONN=<name> $0 $1"; exit 1
fi
OUT=$(echo "$CONN" | sed 's/^card[0-9]*-//')   # KMS / kscreen output name, e.g. HDMI-A-1
PANEL=$(detect_panel)

case "$1" in
  on)
    [ -f "$EDID" ] || { echo "no EDID at $EDID (run: python3 extras/make-edid.py $EDID)"; exit 1; }
    echo "connector $CONN  ->  output $OUT   (laptop panel: $PANEL)"
    sudo sh -c "p=\$(ls -d /sys/kernel/debug/dri/*/$OUT 2>/dev/null | head -1); \
                [ -n \"\$p\" ] || { echo 'no debugfs node for $OUT (debugfs mounted? running as root?)'; exit 1; }; \
                cp '$EDID' \"\$p/edid_override\"; echo on > /sys/class/drm/$CONN/status; \
                udevadm trigger --subsystem-match=drm --action=change 2>/dev/null || true" || exit 1
    # wait (up to ~6s) for KWin to actually notice the forced output before positioning it
    i=0; while [ $i -lt 12 ]; do
      kscreen-doctor -o 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | grep -q "$OUT" && break
      i=$((i+1)); sleep 0.5
    done
    mid=$(kscreen-doctor -o 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | awk -v o="$OUT" '$0~o{f=1} f&&/Modes:/{print}' | grep -oE "[0-9]+:1920x1200@[0-9.]+" | head -1 | cut -d: -f1)
    kscreen-doctor output.$OUT.enable ${mid:+output.$OUT.mode.$mid} \
      output.$OUT.scale.1.5 output.$OUT.position.1746,0 \
      output.$PANEL.priority.1 output.$OUT.priority.2 output.$PANEL.position.0,0
    echo "virtual monitor ON ($OUT, 1920x1200, extended right of $PANEL)"
    echo "point Sunshine at it: find $OUT's index in the Sunshine log ('Detecting monitor N ... $OUT')"
    ;;
  off)
    kscreen-doctor output.$OUT.disable 2>/dev/null
    sudo sh -c "echo off > /sys/class/drm/$CONN/status"
    echo "virtual monitor OFF ($OUT) — laptop can sleep on lid close again"
    ;;
  *)
    echo "usage: [CONN=cardN-XXX] $0 on|off"
    echo "connectors on this machine:"; list_conns
    exit 1 ;;
esac
