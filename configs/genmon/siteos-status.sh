#!/bin/sh
# Site OS status line for xfce4-genmon-plugin. NOT CHECKED IN VM.
# Output format from mockup: "LAN: CONNECTED · SITE OS 0.1 · HH:MM:SS".
# Connection state is read from the default route; no network calls.
state="DISCONNECTED"
if ip route show default 2>/dev/null | grep -q .; then
  state="CONNECTED"
fi
printf '<txt>LAN: %s · SITE OS 0.1 · %s</txt>\n' "$state" "$(date +%H:%M:%S)"
printf '<txtclick>xfce4-terminal</txtclick>\n'
