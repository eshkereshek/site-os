#!/bin/sh
# Site OS status line for xfce4-genmon-plugin. NOT CHECKED IN VM.
# Output format from mockup: "LAN: CONNECTED · SITE OS 0.1 · HH:MM:SS".
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
state="CONNECTED"
if [ -x /sbin/ip ] || [ -x /usr/bin/ip ]; then
  if ! ip route show default 2>/dev/null | grep -q .; then
    state="DISCONNECTED"
  fi
fi
cur_time=$(date +%H:%M:%S)
printf '<txt>LAN: %s · SITE OS 0.1 · %s</txt>\n' "$state" "$cur_time"
printf '<tool>Site OS Status</tool>\n'
printf '<txtclick>xfce4-terminal</txtclick>\n'
