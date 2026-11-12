#!/bin/sh
# Site OS status line for xfce4-genmon-plugin.
# Output format from mockup: "LAN: CONNECTED · SITE OS 0.1 · HH:MM:SS".
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

state="DISCONNECTED"

# 1. Check default route or active interface via ip
if command -v ip >/dev/null 2>&1; then
  if ip route show default 2>/dev/null | grep -q .; then
    state="CONNECTED"
  elif ip -o link show up 2>/dev/null | grep -v 'lo:' | grep -q 'state UP'; then
    state="CONNECTED"
  fi
fi

# 2. Fallback to sysfs network devices
if [ "$state" = "DISCONNECTED" ] && [ -d /sys/class/net ]; then
  for iface in /sys/class/net/*; do
    [ -e "$iface" ] || continue
    name="$(basename "$iface")"
    [ "$name" = "lo" ] && continue
    if [ -f "$iface/operstate" ] && grep -qi "up" "$iface/operstate" 2>/dev/null; then
      state="CONNECTED"
      break
    fi
    if [ -f "$iface/carrier" ] && grep -q "1" "$iface/carrier" 2>/dev/null; then
      state="CONNECTED"
      break
    fi
  done
fi

# 3. Fallback to /proc/net/route
if [ "$state" = "DISCONNECTED" ] && [ -f /proc/net/route ]; then
  if awk '$2 == "00000000" { found=1 } END { exit !found }' /proc/net/route 2>/dev/null; then
    state="CONNECTED"
  fi
fi

cur_time="$(date +%H:%M:%S)"
printf '<txt>LAN: %s · SITE OS 0.1 · %s</txt>\n' "$state" "$cur_time"
printf '<tool>Site OS Status (Network: %s)</tool>\n' "$state"
printf '<txtclick>xfce4-terminal</txtclick>\n'
