#!/usr/bin/env bash
# Site OS installer. Runs as root either inside a chroot (scripts/build_iso.sh)
# or on a real Linux Mint XFCE system (VM). NOT CHECKED IN VM.
#
# Rules:
#   - No running X session is required: no xfconf-query, gsettings, dconf write,
#     xrandr. All XFCE/GTK settings are written as files into /etc/skel.
#   - No systemd / services are started.
#   - Idempotent: safe to re-run.
#
# Usage:
#   sudo ./install.sh --step all
#   sudo ./install.sh --step fonts|wallpaper|gtk-theme|xfwm4-theme|xfce-config|branding|cache
#   sudo ./install.sh --help

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
THEME_NAME="SiteOS"
THEME_SRC="${REPO}/theme/${THEME_NAME}"
WALL_SRC="${REPO}/scripts/gen_wallpaper.py"
ICON_SRC="${REPO}/assets/icons/logo.svg"
WALL_DIR="/usr/share/backgrounds/siteos"
WALL_FILE="${WALL_DIR}/site-os-topo.png"
SKEL="/etc/skel"
SKEL_XFCE="${SKEL}/.config/xfce4/xfconf/xfce-perchannel-xml"
THEME_DST="/usr/share/themes/${THEME_NAME}"
FONT_FAMILY="Unscii"

log()  { printf '[site-os] %s\n' "$*"; }
die()  { printf '[site-os][ERROR] %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Site OS installer.

Usage:
  sudo ./install.sh --step all
  sudo ./install.sh --step <name>

Steps:
  fonts         Unscii font (fonts-unscii), cyrillic check, DejaVu fallback
  wallpaper     topographic wallpaper + skel xfce4-desktop.xml
  gtk-theme     GTK 3 CSS theme + skel settings.ini
  xfwm4-theme   xfwm4 theme, buttons, skel xfwm4.xml
  xfce-config   skel xsettings.xml, xfce4-panel.xml, jgmenu, autostart
  branding      os-release, lsb-release, hostname, logo, live welcome
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

step_fonts() {
  log "step: fonts (${FONT_FAMILY}; cyrillic coverage checked below)"
  apt_install fonts-unscii fontconfig

  # Capture output first: `fc-list | grep -q` can trip pipefail via SIGPIPE.
  local families
  families="$(fc-list : family)"
  grep -qi "${FONT_FAMILY}" <<<"${families}" \
    || die "${FONT_FAMILY} family not found after install (fc-list)"

  local ru
  ru="$(fc-list :lang=ru family)"
  if grep -qi "${FONT_FAMILY}" <<<"${ru}"; then
    log "${FONT_FAMILY} has ru coverage"
  else
    log "WARNING: ${FONT_FAMILY} has no ru coverage; installing DejaVu Sans Mono as cyrillic fallback"
    apt_install fonts-dejavu-core
  fi
  fc-cache -f >/dev/null
  log "fonts: done"
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
    </property>
  </property>
</channel>
EOF
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
gtk-font-name=${FONT_FAMILY} 11
gtk-application-prefer-dark-theme=1
EOF
  log "gtk-theme: installed to ${THEME_DST} and ${SKEL}/.config/gtk-3.0"
}

step_xfwm4_theme() {
  log "step: xfwm4-theme"
  check_path "${THEME_SRC}/xfwm4/themerc"
  check_path "${THEME_SRC}/xfwm4/xpm/minimize.xpm"
  check_path "${THEME_SRC}/xfwm4/xpm/close.xpm"

  local dst="${THEME_DST}/xfwm4"
  mkdir -p "${dst}"
  install -m 0644 "${THEME_SRC}/xfwm4/themerc" "${dst}/themerc"

  # xfwm4 expects per-state button pixmaps; reuse the same art for all states.
  local state
  for state in active inactive prelight pressed; do
    install -m 0644 "${THEME_SRC}/xfwm4/xpm/minimize.xpm" "${dst}/minimize-${state}.xpm"
    install -m 0644 "${THEME_SRC}/xfwm4/xpm/close.xpm" "${dst}/close-${state}.xpm"
  done

  write_file "${SKEL_XFCE}/xfwm4.xml" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfwm4" version="1.0">
  <property name="general" type="empty">
    <property name="theme" type="string" value="${THEME_NAME}"/>
    <property name="use_compositing" type="bool" value="true"/>
    <property name="button_layout" type="string" value="O|HMC"/>
  </property>
</channel>
EOF
  log "xfwm4-theme: installed to ${dst} (opaque frame; transparency via compositor only)"
}

step_xfce_config() {
  log "step: xfce-config (files in ${SKEL} only, no X session)"

  write_file "${SKEL_XFCE}/xsettings.xml" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xsettings" version="1.0">
  <property name="Net" type="empty">
    <property name="ThemeName" type="string" value="${THEME_NAME}"/>
  </property>
  <property name="Gtk" type="empty">
    <property name="FontName" type="string" value="${FONT_FAMILY} 11"/>
    <property name="CursorThemeSize" type="int" value="24"/>
  </property>
</channel>
EOF

  # Single bottom panel: application menu, task list, systray, clock.
  # Position code p=8 (bottom) and plugin ids are NOT CHECKED IN VM.
  write_file "${SKEL_XFCE}/xfce4-panel.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-panel" version="1.0">
  <property name="configver" type="int" value="2"/>
  <property name="dark-mode" type="bool" value="true"/>
  <property name="panels" type="array">
    <value type="int" value="1"/>
    <property name="panel-1" type="empty">
      <property name="position" type="string" value="p=8;x=0;y=0"/>
      <property name="position-locked" type="bool" value="true"/>
      <property name="size" type="uint" value="30"/>
      <property name="length" type="uint" value="100"/>
      <property name="plugin-ids" type="array">
        <value type="int" value="1"/>
        <value type="int" value="2"/>
        <value type="int" value="3"/>
        <value type="int" value="4"/>
      </property>
    </property>
  </property>
  <property name="plugins" type="empty">
    <property name="plugin-1" type="string" value="applicationsmenu"/>
    <property name="plugin-2" type="string" value="tasklist"/>
    <property name="plugin-3" type="string" value="systray"/>
    <property name="plugin-4" type="string" value="clock"/>
  </property>
</channel>
EOF

  # jgmenu: colours mirror the theme; the Win9x menu content is stage 2.
  write_file "${SKEL}/.config/jgmenu/jgmenurc" <<EOF
# Site OS jgmenu colours (opaque, from theme/SPEC.md). NOT CHECKED IN VM.
font_name = ${FONT_FAMILY} 11
color_menu_bg = #3A4550
color_menu_fg = #E8EAF0
color_sel_bg = #5E6688
color_sel_fg = #E8EAF0
EOF

  # Disable the Mint welcome screen for new (and live) users.
  write_file "${SKEL}/.config/autostart/mintwelcome.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Welcome (disabled in Site OS)
Hidden=true
EOF
  log "xfce-config: done"
}

step_branding() {
  log "step: branding (Site OS names; Linux Mint logos removed)"

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

  # Remove Linux Mint logo files (names containing both "mint" and "logo"),
  # then install the Site OS logo under a neutral name.
  local f
  while IFS= read -r -d '' f; do
    log "removing mint logo: ${f}"
    rm -f -- "$f"
  done < <(find /usr/share /etc -type f -iname '*mint*logo*' -print0 2>/dev/null)

  check_path "${ICON_SRC}"
  install -m 0644 "${ICON_SRC}" /usr/share/pixmaps/siteos-logo.svg

  # Live-session welcome text, shipped in skel for new users.
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
    branding)     step_branding ;;
    cache)        step_cache ;;
    all)
      step_fonts
      step_wallpaper
      step_gtk_theme
      step_xfwm4_theme
      step_xfce_config
      step_branding
      step_cache
      ;;
    *) die "unknown step: $1 (fonts|wallpaper|gtk-theme|xfwm4-theme|xfce-config|branding|cache|all)" ;;
  esac
}

# Sets global STEP_ARG (no subshell, so die/exit end the whole script).
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
