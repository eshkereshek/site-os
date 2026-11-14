#!/usr/bin/env bash
# Site OS installer. Runs as root either inside a chroot (scripts/build_iso.sh)
# or on a real Linux Mint XFCE system (VM). NOT CHECKED IN VM.
#
# Rules:
#   - No running X session is required: no xfconf-query, gsettings, dconf write,
#     xrandr. All XFCE/GTK settings are written as files into /etc/skel and /etc/xdg.
#   - Synchronizes configurations to /etc/xdg (system defaults) and all existing
#     user directories in /home/* (e.g. live session user 'mint').
#   - Idempotent: safe to re-run.
#
# Usage:
#   sudo ./install.sh --step all
#   sudo ./install.sh --step fonts|wallpaper|gtk-theme|xfwm4-theme|xfce-config|desktop|branding|cache
#   sudo ./install.sh --help

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
THEME_NAME="SiteOS"
THEME_SRC="${REPO}/theme/${THEME_NAME}"
WALL_SRC="${REPO}/scripts/gen_wallpaper.py"
ICON_SRC="${REPO}/assets/icons/logo.png"
BOOT_LOGO_SRC="${REPO}/assets/icons/start_logo.png"
WALL_DIR="/usr/share/backgrounds/siteos"
WALL_FILE="${WALL_DIR}/site-os-topo.png"
SKEL="/etc/skel"
SKEL_XFCE="${SKEL}/.config/xfce4/xfconf/xfce-perchannel-xml"
THEME_DST="/usr/share/themes/${THEME_NAME}"
FONT_FAMILY="VT323"
VT323_FAMILY="VT323"
FONT_SRC_TTF="${REPO}/assets/fonts/VT323-Regular.ttf"
FONT_SRC_LICENSE="${REPO}/assets/fonts/OFL-VT323.txt"
FONT_DST="/usr/share/fonts/truetype/siteos"

log()  { printf '[site-os] %s\n' "$*"; }
die()  { printf '[site-os][ERROR] %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Site OS installer.

Usage:
  sudo ./install.sh --step all
  sudo ./install.sh --step <name>

Steps:
  fonts         VT323 (repo TTF) primary, DejaVu Sans Mono fallback; warnings only
  wallpaper     topographic wallpaper + xfce4-desktop.xml
  gtk-theme     GTK 3 CSS theme + settings.ini
  xfwm4-theme   xfwm4 theme (PNG frame + buttons), xfwm4.xml
  xfce-config   xsettings.xml, xfce4-panel.xml (44px), jgmenu, autostart
  desktop       Thunar list view (thunar.xml), desktop icons, optional devilspie2 title
  branding      os-release, lsb-release, hostname, logo, plymouth boot logo
  cache         fc-cache and icon caches
  all           every step above, in this order
EOF
}

require_root() {
  [[ "${EUID}" -eq 0 ]] || die "run as root (sudo or chroot)"
}

check_path() {
  [[ -e "$1" ]] || die "missing path: $1 (repo layout broken?)"
}

pkg_installed() {
  dpkg -s "$1" >/dev/null 2>&1
}

apt_install() {
  local missing=()
  local p
  for p in "$@"; do
    pkg_installed "$p" || missing+=("$p")
  done
  if [[ ${#missing[@]} -eq 0 ]]; then
    log "packages already installed: $*"
    return 0
  fi
  log "installing: ${missing[*]}"
  DEBIAN_FRONTEND=noninteractive apt-get update -qq
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${missing[@]}" \
    || die "apt-get failed for: ${missing[*]}"
}

# Writes a file atomically-enough for idempotent re-runs.
write_file() {
  local path="$1"
  mkdir -p "$(dirname "$path")"
  cat > "${path}.tmp"
  mv -f "${path}.tmp" "$path"
}

# Propagate an xfconf per-channel XML file to:
# 1. /etc/skel (future new users)
# 2. /etc/xdg/xfce4/xfconf/xfce-perchannel-xml (system default)
# 3. All existing user directories in /home/* (e.g. live user 'mint')
sync_channel() {
  local channel="$1"
  local src="${SKEL_XFCE}/${channel}.xml"
  [[ -f "$src" ]] || return 0

  # System-wide XDG defaults
  mkdir -p /etc/xdg/xfce4/xfconf/xfce-perchannel-xml
  install -m 0644 "$src" "/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/${channel}.xml"

  # Panel fallback
  if [[ "$channel" == "xfce4-panel" ]]; then
    mkdir -p /etc/xdg/xfce4/panel
    install -m 0644 "$src" /etc/xdg/xfce4/panel/default.xml
  fi

  # Distribution-specific XDG overrides (Linux Mint / Xubuntu)
  local extra_xdg
  for extra_xdg in /etc/xdg/xdg-mint /etc/xdg/xdg-xubuntu; do
    if [[ -d "$extra_xdg" ]]; then
      mkdir -p "${extra_xdg}/xfce4/xfconf/xfce-perchannel-xml"
      install -m 0644 "$src" "${extra_xdg}/xfce4/xfconf/xfce-perchannel-xml/${channel}.xml"
    fi
  done

  # Existing user homes in /home/*
  local h
  for h in /home/*; do
    if [[ -d "$h" && "$h" != "/home/*" ]]; then
      local user_xfconf="${h}/.config/xfce4/xfconf/xfce-perchannel-xml"
      mkdir -p "$user_xfconf"
      install -m 0644 "$src" "${user_xfconf}/${channel}.xml"
      local owner
      owner="$(stat -c '%u:%g' "$h")"
      chown -R "$owner" "${h}/.config" 2>/dev/null || true
    fi
  done
}

# Primary font: VT323 (OFL) shipped in assets/fonts. Fallback: DejaVu Sans Mono.
# Terminus is NOT used (bitmap; Pango does not render it). Warnings only, no exit.
# NOT CHECKED IN VM.
step_fonts() {
  log "step: fonts (primary ${VT323_FAMILY} from repo, fallback DejaVu Sans Mono)"
  check_path "${FONT_SRC_TTF}"
  apt_install fontconfig fonts-dejavu-core

  install -d -m 0755 "${FONT_DST}"
  install -m 0644 "${FONT_SRC_TTF}" "${FONT_DST}/VT323-Regular.ttf"
  [[ -f "${FONT_SRC_LICENSE}" ]] && install -m 0644 "${FONT_SRC_LICENSE}" "${FONT_DST}/OFL-VT323.txt"
  fc-cache -f >/dev/null 2>&1 || log "WARNING: fc-cache failed"

  if fc-list | grep -qi "vt323"; then
    log "fc-list: VT323 found"
  else
    log "WARNING: fc-list | grep -i vt323 found nothing; theme falls back to DejaVu Sans Mono (not checked in VM)"
  fi

  local ru
  ru="$(fc-list :lang=ru family 2>/dev/null || true)"
  if grep -qi "VT323" <<<"${ru}"; then
    log "VT323 has ru coverage"
  else
    log "WARNING: VT323 has no ru coverage; DejaVu Sans Mono is the cyrillic fallback (not checked in VM)"
  fi
  log "fonts: done (not checked in VM)"
}

step_wallpaper() {
  log "step: wallpaper (python generator)"
  check_path "${WALL_SRC}"
  apt_install python3 python3-numpy python3-scipy python3-pil
  mkdir -p "${WALL_DIR}"
  python3 "${WALL_SRC}" --out "${WALL_FILE}" --size 1920x1080 --seed 7 \
    || die "wallpaper generator failed"
  check_path "${WALL_FILE}"

  write_file "${SKEL_XFCE}/xfce4-desktop.xml" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-desktop" version="1.0">
  <property name="backdrop" type="empty">
    <property name="screen0" type="empty">
      <property name="monitor0" type="empty">
        <property name="workspace0" type="empty">
          <property name="last-image" type="string" value="${WALL_FILE}"/>
          <property name="image-style" type="int" value="5"/>
        </property>
      </property>
      <property name="monitorVirtual1" type="empty">
        <property name="workspace0" type="empty">
          <property name="last-image" type="string" value="${WALL_FILE}"/>
          <property name="image-style" type="int" value="5"/>
        </property>
      </property>
      <property name="monitorVirtual-1" type="empty">
        <property name="workspace0" type="empty">
          <property name="last-image" type="string" value="${WALL_FILE}"/>
          <property name="image-style" type="int" value="5"/>
        </property>
      </property>
      <property name="monitorHDMI-1" type="empty">
        <property name="workspace0" type="empty">
          <property name="last-image" type="string" value="${WALL_FILE}"/>
          <property name="image-style" type="int" value="5"/>
        </property>
      </property>
      <property name="monitorVGA-1" type="empty">
        <property name="workspace0" type="empty">
          <property name="last-image" type="string" value="${WALL_FILE}"/>
          <property name="image-style" type="int" value="5"/>
        </property>
      </property>
      <property name="monitordefault" type="empty">
        <property name="workspace0" type="empty">
          <property name="last-image" type="string" value="${WALL_FILE}"/>
          <property name="image-style" type="int" value="5"/>
        </property>
      </property>
    </property>
  </property>
  <property name="desktop-icons" type="empty">
    <property name="style" type="int" value="2"/>
    <property name="icon-size" type="uint" value="56"/>
    <property name="font-size" type="double" value="13.5"/>
    <property name="single-click" type="bool" value="true"/>
    <property name="use-custom-font-size" type="bool" value="true"/>
  </property>
</channel>
EOF
  sync_channel "xfce4-desktop"
  log "wallpaper: ${WALL_FILE}"
}

step_gtk_theme() {
  log "step: gtk-theme"
  check_path "${THEME_SRC}/gtk-3.0/gtk.css"

  mkdir -p "${THEME_DST}/gtk-3.0"
  install -m 0644 "${THEME_SRC}/gtk-3.0/gtk.css" "${THEME_DST}/gtk-3.0/gtk.css"

  mkdir -p "${SKEL}/.config/gtk-3.0"
  install -m 0644 "${THEME_SRC}/gtk-3.0/gtk.css" "${SKEL}/.config/gtk-3.0/gtk.css"
  write_file "${SKEL}/.config/gtk-3.0/settings.ini" <<EOF
[Settings]
gtk-theme-name=${THEME_NAME}
gtk-font-name=${FONT_FAMILY} 12
gtk-application-prefer-dark-theme=1
EOF

  # System-wide and existing users
  mkdir -p /etc/gtk-3.0
  install -m 0644 "${THEME_SRC}/gtk-3.0/gtk.css" /etc/gtk-3.0/gtk.css 2>/dev/null || true
  install -m 0644 "${SKEL}/.config/gtk-3.0/settings.ini" /etc/gtk-3.0/settings.ini 2>/dev/null || true

  local h
  for h in /home/*; do
    if [[ -d "$h" && "$h" != "/home/*" ]]; then
      mkdir -p "${h}/.config/gtk-3.0"
      install -m 0644 "${THEME_SRC}/gtk-3.0/gtk.css" "${h}/.config/gtk-3.0/gtk.css"
      install -m 0644 "${SKEL}/.config/gtk-3.0/settings.ini" "${h}/.config/gtk-3.0/settings.ini"
      local owner
      owner="$(stat -c '%u:%g' "$h")"
      chown -R "$owner" "${h}/.config/gtk-3.0" 2>/dev/null || true
    fi
  done
  log "gtk-theme: installed to ${THEME_DST} and synced to users"
}

step_xfwm4_theme() {
  log "step: xfwm4-theme"
  check_path "${THEME_SRC}/xfwm4/themerc"

  local dst="${THEME_DST}/xfwm4"
  mkdir -p "${dst}"
  install -m 0644 "${THEME_SRC}/xfwm4/themerc" "${dst}/themerc"

  # Install all PNG frame strips, corners, and dot buttons
  if ls "${THEME_SRC}/xfwm4/"*.png >/dev/null 2>&1; then
    install -m 0644 "${THEME_SRC}/xfwm4/"*.png "${dst}/"
  fi

  write_file "${SKEL_XFCE}/xfwm4.xml" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfwm4" version="1.0">
  <property name="general" type="empty">
    <property name="theme" type="string" value="${THEME_NAME}"/>
    <property name="use_compositing" type="bool" value="true"/>
    <property name="button_layout" type="string" value="|HC"/>
    <property name="title_font" type="string" value="${FONT_FAMILY} 16"/>
    <property name="title_alignment" type="string" value="left"/>
    <property name="title_horizontal_offset" type="int" value="7"/>
    <property name="button_offset" type="int" value="7"/>
    <property name="button_spacing" type="int" value="7"/>
    <property name="frame_opacity" type="int" value="100"/>
    <property name="inactive_opacity" type="int" value="100"/>
    <property name="move_opacity" type="int" value="85"/>
    <property name="resize_opacity" type="int" value="85"/>
    <property name="popup_opacity" type="int" value="98"/>
    <property name="show_frame_shadow" type="bool" value="true"/>
    <property name="show_popup_shadow" type="bool" value="true"/>
    <property name="shadow_opacity" type="int" value="50"/>
    <property name="shadow_radius" type="int" value="20"/>
    <property name="shadow_delta_x" type="int" value="0"/>
    <property name="shadow_delta_y" type="int" value="6"/>
    <property name="show_app_icon" type="bool" value="false"/>
  </property>
</channel>
EOF
  sync_channel "xfwm4"
  log "xfwm4-theme: installed to ${dst} and synced to users"
}

step_xfce_config() {
  log "step: xfce-config (files in ${SKEL} and /etc/xdg, no X session)"
  apt_install python3 python3-gi python3-gi-cairo gir1.2-gtk-3.0 eject zenity jgmenu xfce4-genmon-plugin thunar

  write_file "${SKEL_XFCE}/xsettings.xml" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xsettings" version="1.0">
  <property name="Net" type="empty">
    <property name="ThemeName" type="string" value="${THEME_NAME}"/>
  </property>
  <property name="Gtk" type="empty">
    <property name="FontName" type="string" value="${FONT_FAMILY} 12"/>
    <property name="CursorThemeSize" type="int" value="24"/>
    <property name="EnableAnimations" type="bool" value="true"/>
  </property>
</channel>
EOF
  sync_channel "xsettings"

  # Panel 44px matching mockup.html #panel:
  # [Start] | [tasklist] ... [expand] ... | [WiFi: LAN CONNECTED] | [systray] | [clock]
  write_file "${SKEL_XFCE}/xfce4-panel.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-panel" version="1.0">
  <property name="configver" type="int" value="2"/>
  <property name="panels" type="array">
    <value type="int" value="1"/>
    <property name="panel-1" type="empty">
      <property name="position" type="string" value="p=8;x=0;y=0"/>
      <property name="position-locked" type="bool" value="true"/>
      <property name="size" type="uint" value="44"/>
      <property name="length" type="uint" value="100"/>
      <property name="span-monitors" type="bool" value="false"/>
      <property name="plugin-ids" type="array">
        <value type="int" value="1"/>
        <value type="int" value="2"/>
        <value type="int" value="3"/>
        <value type="int" value="4"/>
        <value type="int" value="5"/>
        <value type="int" value="6"/>
        <value type="int" value="7"/>
        <value type="int" value="8"/>
        <value type="int" value="9"/>
        <value type="int" value="10"/>
      </property>
    </property>
  </property>
  <property name="plugins" type="empty">
    <property name="plugin-1" type="string" value="launcher">
      <property name="items" type="array">
        <value type="string" value="siteos-start.desktop"/>
      </property>
      <property name="show-label" type="bool" value="false"/>
      <property name="move-first" type="bool" value="false"/>
      <property name="arrow-position" type="uint" value="5"/>
    </property>
    <property name="plugin-2" type="string" value="separator">
      <property name="style" type="uint" value="1"/>
      <property name="expand" type="bool" value="false"/>
    </property>
    <property name="plugin-3" type="string" value="tasklist">
      <property name="grouping" type="uint" value="0"/>
      <property name="show-labels" type="bool" value="true"/>
      <property name="flat-buttons" type="bool" value="true"/>
      <property name="show-handle" type="bool" value="false"/>
      <property name="sort-order" type="uint" value="4"/>
    </property>
    <property name="plugin-4" type="string" value="separator">
      <property name="expand" type="bool" value="true"/>
      <property name="style" type="uint" value="0"/>
    </property>
    <property name="plugin-5" type="string" value="separator">
      <property name="style" type="uint" value="1"/>
      <property name="expand" type="bool" value="false"/>
    </property>
    <property name="plugin-6" type="string" value="genmon">
      <property name="command" type="string" value="/usr/local/share/siteos/siteos-wifi.sh"/>
      <property name="use-label" type="bool" value="false"/>
      <property name="update-period" type="int" value="2000"/>
      <property name="enable-single-row" type="bool" value="true"/>
      <property name="font" type="string" value="VT323 15"/>
    </property>
    <property name="plugin-7" type="string" value="separator">
      <property name="style" type="uint" value="1"/>
      <property name="expand" type="bool" value="false"/>
    </property>
    <property name="plugin-8" type="string" value="systray">
      <property name="square-icons" type="bool" value="true"/>
    </property>
    <property name="plugin-9" type="string" value="separator">
      <property name="style" type="uint" value="1"/>
      <property name="expand" type="bool" value="false"/>
    </property>
    <property name="plugin-10" type="string" value="clock">
      <property name="digital-layout" type="uint" value="3"/>
      <property name="digital-time-format" type="string" value="%H:%M:%S"/>
      <property name="mode" type="uint" value="2"/>
      <property name="show-seconds" type="bool" value="true"/>
    </property>
  </property>
</channel>
EOF
  sync_channel "xfce4-panel"

  # Site OS dialog & alert tool (mockup .win.err 1:1)
  install -d -m 0755 /usr/local/bin
  install -m 0755 "${REPO}/scripts/siteos-dialog.py" /usr/local/bin/siteos-dialog
  ln -sf /usr/local/bin/siteos-dialog /usr/bin/siteos-dialog
  ln -sf /usr/local/bin/siteos-dialog /usr/bin/siteos-error

  # Site OS custom Start Menu (mockup 1:1 with app column, eject & power buttons)
  install -d -m 0755 /usr/local/bin "${SKEL}/.local/bin"
  install -m 0755 "${REPO}/scripts/siteos-menu.py" /usr/local/bin/siteos-menu.py
  install -m 0755 "${REPO}/scripts/siteos-menu.py" "${SKEL}/.local/bin/siteos-menu.py"

  # Executable wrapper for Start button (runs siteos-menu.py first, fallbacks to jgmenu)
  write_file /usr/bin/siteos-menu <<'EOF'
#!/bin/sh
export DISPLAY="${DISPLAY:-:0}"
if [ -x /usr/local/bin/siteos-menu.py ] && command -v python3 >/dev/null 2>&1; then
  exec python3 /usr/local/bin/siteos-menu.py "$@"
elif [ -f "${HOME}/.local/bin/siteos-menu.py" ] && command -v python3 >/dev/null 2>&1; then
  exec python3 "${HOME}/.local/bin/siteos-menu.py" "$@"
elif command -v jgmenu >/dev/null 2>&1; then
  if [ -f "$HOME/.config/jgmenu/jgmenurc" ]; then
    exec jgmenu --config-file="$HOME/.config/jgmenu/jgmenurc" --csv-file="$HOME/.config/jgmenu/prepend.csv"
  elif [ -f "/etc/jgmenu/jgmenurc" ]; then
    exec jgmenu --config-file="/etc/jgmenu/jgmenurc" --csv-file="/etc/jgmenu/prepend.csv"
  else
    exec jgmenu
  fi
fi
exec xfce4-popup-applicationsmenu || xfce4-appfinder
EOF
  chmod 0755 /usr/bin/siteos-menu

  # Start button .desktop file (system-wide and local)
  write_file /usr/share/applications/siteos-start.desktop <<'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=Start
Comment=Site OS Start Menu
Exec=/usr/bin/siteos-menu
Icon=siteos-logo
Terminal=false
Categories=System;Utility;
StartupNotify=false
EOF
  chmod 0644 /usr/share/applications/siteos-start.desktop

  # Ensure launcher-1 directory has siteos-start.desktop across all configs
  mkdir -p "${SKEL}/.local/share/applications" "${SKEL}/.config/xfce4/panel/launcher-1" /etc/xdg/xfce4/panel/launcher-1 /etc/xdg/xdg-mint/xfce4/panel/launcher-1
  install -m 0644 /usr/share/applications/siteos-start.desktop "${SKEL}/.local/share/applications/siteos-start.desktop"
  install -m 0644 /usr/share/applications/siteos-start.desktop "${SKEL}/.config/xfce4/panel/launcher-1/siteos-start.desktop"
  install -m 0644 /usr/share/applications/siteos-start.desktop /etc/xdg/xfce4/panel/launcher-1/siteos-start.desktop
  install -m 0644 /usr/share/applications/siteos-start.desktop /etc/xdg/xdg-mint/xfce4/panel/launcher-1/siteos-start.desktop 2>/dev/null || true

  # jgmenu configuration
  install -d -m 0755 "${SKEL}/.config/jgmenu" /etc/jgmenu
  install -m 0644 "${REPO}/configs/jgmenu/jgmenurc" "${SKEL}/.config/jgmenu/jgmenurc"
  install -m 0644 "${REPO}/configs/jgmenu/prepend.csv" "${SKEL}/.config/jgmenu/prepend.csv"
  install -m 0644 "${REPO}/configs/jgmenu/jgmenurc" /etc/jgmenu/jgmenurc 2>/dev/null || true
  install -m 0644 "${REPO}/configs/jgmenu/prepend.csv" /etc/jgmenu/prepend.csv 2>/dev/null || true

  # Genmon network button script: "LAN: CONNECTED"
  install -d -m 0755 /usr/local/share/siteos
  install -m 0755 "${REPO}/configs/genmon/siteos-wifi.sh" /usr/local/share/siteos/siteos-wifi.sh
  install -m 0755 "${REPO}/configs/genmon/siteos-status.sh" /usr/local/share/siteos/siteos-status.sh
  ln -sf /usr/local/share/siteos/siteos-wifi.sh /usr/bin/siteos-wifi
  ln -sf /usr/local/share/siteos/siteos-status.sh /usr/bin/siteos-status

  # genmon-6.rc for WiFi / Network button
  mkdir -p "${SKEL}/.config/xfce4/panel" /etc/xdg/xfce4/panel
  write_file "${SKEL}/.config/xfce4/panel/genmon-6.rc" <<'EOF'
Command=/usr/local/share/siteos/siteos-wifi.sh
UseLabel=0
Text=(genmon)
UpdatePeriod=2000
Font=VT323 15
EOF
  install -m 0644 "${SKEL}/.config/xfce4/panel/genmon-6.rc" /etc/xdg/xfce4/panel/genmon-6.rc
  install -m 0644 "${SKEL}/.config/xfce4/panel/genmon-6.rc" /etc/xdg/xfce4/panel/genmon-4.rc 2>/dev/null || true

  # Terminal palette (mockup Terminal window).
  install -d -m 0755 "${SKEL}/.config/xfce4/terminal" /etc/xdg/xfce4/terminal
  install -m 0644 "${REPO}/configs/xfce4-terminal/terminalrc" "${SKEL}/.config/xfce4/terminal/terminalrc"
  install -m 0644 "${REPO}/configs/xfce4-terminal/terminalrc" /etc/xdg/xfce4/terminal/terminalrc 2>/dev/null || true

  # Disable the Mint welcome screen for new and live users.
  write_file "${SKEL}/.config/autostart/mintwelcome.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Welcome (disabled in Site OS)
Hidden=true
EOF

  # Sync user configs to any existing /home/*
  local h
  for h in /home/*; do
    if [[ -d "$h" && "$h" != "/home/*" ]]; then
      mkdir -p "${h}/.config/jgmenu" "${h}/.config/xfce4/terminal" "${h}/.config/xfce4/panel/launcher-1" "${h}/.local/share/applications" "${h}/.local/bin" "${h}/.config/autostart"
      install -m 0644 "${REPO}/configs/jgmenu/jgmenurc" "${h}/.config/jgmenu/jgmenurc"
      install -m 0644 "${REPO}/configs/jgmenu/prepend.csv" "${h}/.config/jgmenu/prepend.csv"
      install -m 0644 "${REPO}/configs/xfce4-terminal/terminalrc" "${h}/.config/xfce4/terminal/terminalrc"
      install -m 0755 "${REPO}/scripts/siteos-menu.py" "${h}/.local/bin/siteos-menu.py"
      install -m 0644 /usr/share/applications/siteos-start.desktop "${h}/.local/share/applications/siteos-start.desktop"
      install -m 0644 /usr/share/applications/siteos-start.desktop "${h}/.config/xfce4/panel/launcher-1/siteos-start.desktop"
      install -m 0644 "${SKEL}/.config/xfce4/panel/genmon-6.rc" "${h}/.config/xfce4/panel/genmon-6.rc"
      install -m 0644 "${SKEL}/.config/xfce4/panel/genmon-6.rc" "${h}/.config/xfce4/panel/genmon-4.rc" 2>/dev/null || true
      install -m 0644 "${SKEL}/.config/autostart/mintwelcome.desktop" "${h}/.config/autostart/mintwelcome.desktop"
      local owner
      owner="$(stat -c '%u:%g' "$h")"
      chown -R "$owner" "${h}/.config" "${h}/.local" 2>/dev/null || true
    fi
  done
  log "xfce-config: done (not checked in VM)"
}

step_desktop() {
  log "step: desktop (Thunar list view, desktop icons from mockup.html) not checked in VM"

  # Thunar configuration: Windows Explorer layout with left navigation sidebar, address bar, menubar, and statusbar
  write_file "${SKEL_XFCE}/thunar.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="thunar" version="1.0">
  <property name="last-view" type="string" value="ThunarDetailsView"/>
  <property name="last-side-pane" type="string" value="ThunarShortcutsPane"/>
  <property name="last-location-bar" type="string" value="ThunarLocationButtons"/>
  <property name="last-menubar-visible" type="bool" value="true"/>
  <property name="last-statusbar-visible" type="bool" value="true"/>
  <property name="last-show-hidden" type="bool" value="false"/>
  <property name="misc-single-click" type="bool" value="false"/>
  <property name="last-separator-position" type="int" value="180"/>
  <property name="last-details-view-zoom-level" type="string" value="THUNAR_ZOOM_LEVEL_100_PERCENT"/>
  <property name="last-details-view-column-order" type="string" value="THUNAR_COLUMN_NAME,THUNAR_COLUMN_DATE_MODIFIED,THUNAR_COLUMN_MIME_TYPE,THUNAR_COLUMN_SIZE"/>
  <property name="last-details-view-visible-columns" type="string" value="THUNAR_COLUMN_NAME,THUNAR_COLUMN_DATE_MODIFIED,THUNAR_COLUMN_MIME_TYPE,THUNAR_COLUMN_SIZE"/>
  <property name="last-details-view-column-widths" type="string" value="260,140,120,90"/>
</channel>
EOF
  sync_channel "thunar"

  # Quick Access bookmarks for Thunar left sidebar
  mkdir -p "${SKEL}/.config/gtk-3.0"
  write_file "${SKEL}/.config/gtk-3.0/bookmarks" <<'EOF'
file:///home/mint/Desktop Desktop
file:///home/mint/Desktop/Site Site
file:///home/mint/Desktop/Sessions Sessions
file:///home/mint/Desktop/Personal Personal
file:///home/mint/Desktop/Intake Intake
EOF

  # Populate desktop with the exact items from mockup.html
  local d
  for d in "${SKEL}/Desktop" /home/*/Desktop; do
    [[ -d "$(dirname "$d")" ]] || continue
    mkdir -p "${d}/Personal" "${d}/Intake" "${d}/Sessions" "${d}/Site"
    cat > "${d}/readme.txt" <<'EOF'
Welcome to Site OS.

Double-click folders to explore.
Open Start > Programs for more apps.
EOF
    cat > "${d}/Personal/todo.txt" <<'EOF'
- Buy coffee
- Call the landlord
- Finish the report
- Back up photos
EOF
    cat > "${d}/Intake/schedule.txt" <<'EOF'
MON 09:00  Orientation
TUE 10:30  Safety briefing
WED 14:00  Site walk
FRI 16:00  Debrief
EOF
    cat > "${d}/Sessions/notes.txt" <<'EOF'
Remember to rotate the logs on Friday.
EOF
    cat > "${d}/Site/report_0914_DRAFT.txt" <<'EOF'
REPORT 0914 (DRAFT)

All systems nominal.
Camera 07 needs a lens cleaning.
Generator maintenance is on schedule.
EOF
    # Remove installer icons from desktop
    rm -f "${d}/ubiquity.desktop" "${d}/mint-install.desktop" 2>/dev/null || true
    local parent_dir
    parent_dir="$(dirname "$d")"
    if [[ "$parent_dir" != "${SKEL}" && -d "$parent_dir" ]]; then
      local owner
      owner="$(stat -c '%u:%g' "$parent_dir")"
      chown -R "$owner" "$d" 2>/dev/null || true
    fi
  done

  # Sync bookmarks to existing users
  local user_h
  for user_h in /home/*; do
    if [[ -d "$user_h" && "$user_h" != "/home/*" ]]; then
      local user_name
      user_name="$(basename "$user_h")"
      mkdir -p "${user_h}/.config/gtk-3.0"
      sed "s|/home/mint|/home/${user_name}|g" "${SKEL}/.config/gtk-3.0/bookmarks" > "${user_h}/.config/gtk-3.0/bookmarks"
      local owner
      owner="$(stat -c '%u:%g' "$user_h")"
      chown -R "$owner" "${user_h}/.config/gtk-3.0" 2>/dev/null || true
    fi
  done

  # SVG icons for folders and files
  install -d -m 0755 /usr/share/icons/hicolor/scalable/places /usr/share/icons/hicolor/scalable/mimetypes
  for icon_name in folder default-folder inode-directory siteos-folder; do
    install -m 0644 "${REPO}/assets/icons/folder.svg" "/usr/share/icons/hicolor/scalable/places/${icon_name}.svg"
  done
  for icon_name in text-plain application-octet-stream empty text-x-generic siteos-file; do
    install -m 0644 "${REPO}/assets/icons/file.svg" "/usr/share/icons/hicolor/scalable/mimetypes/${icon_name}.svg"
  done

  # Optional: devilspie2 rewrites Thunar window title
  if apt_install devilspie2 >/dev/null 2>&1; then
    write_file "${SKEL}/.config/devilspie2/thunar.lua" <<'EOF'
-- Thunar title: "File Explorer - Desktop\<path>\". NOT CHECKED IN VM.
if get_application_name() == "Thunar" then
  local p = get_window_name()
  if p and not string.find(p, "File Explorer") then
    local d = p:gsub("^.-:%s*", "")
    set_window_name("File Explorer - " .. d)
  end
end
EOF
    write_file "${SKEL}/.config/autostart/devilspie2.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=devilspie2
Exec=devilspie2
Hidden=false
EOF
    log "desktop: devilspie2 installed (optional, title rule not checked in VM)"
  else
    log "WARNING: devilspie2 not available; Thunar title stays default (not checked in VM)"
  fi
  log "desktop: done (not checked in VM)"
}

step_branding() {
  log "step: branding (Site OS names; Linux Mint logos replaced)"

  local codename=""
  if [[ -f /etc/os-release ]]; then
    codename="$(grep -E '^UBUNTU_CODENAME=' /etc/os-release || true)"
  fi
  write_file /etc/os-release <<EOF
PRETTY_NAME="Site OS 1.0 (based on Linux Mint XFCE)"
NAME="Site OS"
VERSION="1.0"
VERSION_ID="1.0"
ID=siteos
ID_LIKE="ubuntu debian"
HOME_URL="https://github.com/eshkereshek/site-os"
LOGO=siteos-logo
${codename}
EOF

  write_file /etc/lsb-release <<'EOF'
DISTRIB_ID=SiteOS
DISTRIB_RELEASE=1.0
DISTRIB_DESCRIPTION="Site OS 1.0"
EOF

  write_file /etc/hostname <<'EOF'
siteos
EOF

  write_file /etc/issue <<'EOF'
Site OS 1.0 \n \l

EOF
  write_file /etc/motd <<'EOF'
Site OS: добро пожаловать / welcome.
EOF

  # Remove Linux Mint logos
  local f
  while IFS= read -r -d '' f; do
    log "removing mint logo: ${f}"
    rm -f -- "$f"
  done < <(find /usr/share /etc -type f -iname '*mint*logo*' -print0 2>/dev/null)

  check_path "${ICON_SRC}"
  install -d -m 0755 /usr/share/pixmaps /usr/share/icons/hicolor/scalable/apps /usr/share/icons/hicolor/48x48/apps
  install -m 0644 "${ICON_SRC}" /usr/share/pixmaps/siteos-logo.png
  install -m 0644 "${ICON_SRC}" /usr/share/icons/hicolor/scalable/apps/siteos-logo.png
  install -m 0644 "${ICON_SRC}" /usr/share/icons/hicolor/48x48/apps/siteos-logo.png

  # Boot/splash logo (start_logo.png) installed into Plymouth themes
  check_path "${BOOT_LOGO_SRC}"
  install -d -m 0755 /usr/share/siteos /usr/share/plymouth/themes/mint-logo /usr/share/plymouth/themes/spinner
  install -m 0644 "${BOOT_LOGO_SRC}" /usr/share/siteos/start_logo.png
  install -m 0644 "${BOOT_LOGO_SRC}" /usr/share/pixmaps/siteos-boot-logo.png
  install -m 0644 "${BOOT_LOGO_SRC}" /usr/share/plymouth/themes/mint-logo/mint-logo.png 2>/dev/null || true
  install -m 0644 "${BOOT_LOGO_SRC}" /usr/share/plymouth/themes/spinner/watermark.png 2>/dev/null || true
  install -m 0644 "${BOOT_LOGO_SRC}" /usr/share/plymouth/themes/spinner/bgrt-fallback.png 2>/dev/null || true

  # Live-session welcome text
  write_file "${SKEL}/Welcome-SiteOS.txt" <<'EOF'
Site OS
=======
Добро пожаловать. Тема: Site OS (XFCE, тёмный интерфейс).
Welcome. Theme: Site OS (XFCE, dark interface).
EOF
  log "branding: done (not checked in VM)"
}

step_cache() {
  log "step: cache"
  fc-cache -f >/dev/null
  if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    local d
    for d in /usr/share/icons/*/; do
      if [[ -f "${d}index.theme" ]]; then
        gtk-update-icon-cache -q -f -t "$d" || log "icon cache skipped: $d"
      fi
    done
  fi
  log "cache: done"
}

run_step() {
  case "$1" in
    fonts)        step_fonts ;;
    wallpaper)    step_wallpaper ;;
    gtk-theme)    step_gtk_theme ;;
    xfwm4-theme)  step_xfwm4_theme ;;
    xfce-config)  step_xfce_config ;;
    desktop)      step_desktop ;;
    branding)     step_branding ;;
    cache)        step_cache ;;
    all)
      step_fonts
      step_wallpaper
      step_gtk_theme
      step_xfwm4_theme
      step_xfce_config
      step_desktop
      step_branding
      step_cache
      ;;
    *) die "unknown step: $1 (fonts|wallpaper|gtk-theme|xfwm4-theme|xfce-config|desktop|branding|cache|all)" ;;
  esac
}

parse_args() {
  STEP_ARG=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --help|-h) usage; exit 0 ;;
      --step) STEP_ARG="${2:-}"; shift 2 ;;
      --step=*) STEP_ARG="${1#--step=}"; shift ;;
      *) usage; die "unknown argument: $1" ;;
    esac
  done
  if [[ -z "${STEP_ARG}" ]]; then
    usage
    exit 2
  fi
}

parse_args "$@"
require_root
run_step "${STEP_ARG}"
log "done: ${STEP_ARG}"
