#!/bin/sh
# Site OS Genmon WiFi / Network Status Button
status="LAN: DISCONNECTED"
color="#A0A8B4"
if ip route get 1.1.1.1 2>/dev/null | grep -q 'dev'; then
  status="LAN: CONNECTED"
  color="#B9D8C6"
elif ip route get 8.8.8.8 2>/dev/null | grep -q 'dev'; then
  status="LAN: CONNECTED"
  color="#B9D8C6"
fi

echo "<txt><span font='VT323 15' color='${color}'>${status}</span></txt>"
echo "<tool>Network: ${status} (Click to open network settings)</tool>"
echo "<click>nm-connection-editor || xfce4-settings-manager</click>"
