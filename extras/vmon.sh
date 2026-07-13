#!/bin/sh
# vmon.sh on|off — toggle the virtual second monitor (tablet via Sunshine on KDE Wayland).
# Needs: a 1920x1200 EDID at $EDID (generate with extras/make-edid.py), root for DRM sysfs.
# See docs/second-monitor-kde.md.
export XDG_RUNTIME_DIR=/run/user/$(id -u) WAYLAND_DISPLAY=wayland-0 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u)/bus
CONN=card1-HDMI-A-1                       # spare connector on this laptop
EDID="${EDID:-$HOME/.local/share/medion-vm.edid}"
case "$1" in
  on)
    [ -f "$EDID" ] || { echo "no EDID at $EDID (run: python3 extras/make-edid.py $EDID)"; exit 1; }
    sudo sh -c "p=\$(ls -d /sys/kernel/debug/dri/*/HDMI-A-1); cp '$EDID' \"\$p/edid_override\"; echo on > /sys/class/drm/$CONN/status"
    sleep 1
    mid=$(kscreen-doctor -o 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | awk '/HDMI-A-1/{f=1} f&&/Modes:/{print}' | grep -oE "[0-9]+:1920x1200@[0-9.]+" | head -1 | cut -d: -f1)
    kscreen-doctor output.HDMI-A-1.enable ${mid:+output.HDMI-A-1.mode.$mid} \
      output.HDMI-A-1.scale.1.5 output.HDMI-A-1.position.1746,0 \
      output.eDP-1.priority.1 output.HDMI-A-1.priority.2 output.eDP-1.position.0,0
    echo "virtual monitor ON (laptop primary, tablet extended right, 1920x1200)"
    ;;
  off)
    kscreen-doctor output.HDMI-A-1.disable 2>/dev/null
    sudo sh -c "echo off > /sys/class/drm/$CONN/status"
    echo "virtual monitor OFF (laptop can sleep on lid close again)"
    ;;
  *) echo "usage: vmon.sh on|off"; exit 1 ;;
esac
