#!/bin/sh
# Site OS Genmon WiFi / Network Status Button (instant non-blocking sysfs)
status="LAN: DISCONNECTED"
color="#A0A8B4"
if grep -q "up" /sys/class/net/[ew]*/operstate 2>/dev/null; then
  status="LAN: CONNECTED"
  color="#B9D8C6"
fi

echo "<txt><span font='VT323 15' color='${color}'>${status}</span></txt>"
echo "<tool>Network: ${status} (Click to open network settings)</tool>"
echo "<click>nm-connection-editor || xfce4-settings-manager</click>"
