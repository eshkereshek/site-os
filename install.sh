#!/usr/bin/env bash
# Site OS installer, stage 1 (fonts, wallpaper, gtk-theme, xfwm4-theme).
# NOT CHECKED IN VM. Idempotent: safe to re-run. Designed for Linux Mint XFCE
# (Ubuntu base) in a VM or Cubic/chroot.
#
# Usage:
#   sudo ./install.sh --step all
#   sudo ./install.sh --step fonts|wallpaper|gtk-theme|xfwm4-theme
#   sudo ./install.sh --help

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
THEME_NAME="SiteOS"
THEME_SRC="${REPO}/theme/${THEME_NAME}"
WALL_SRC="${REPO}/scripts/gen_wallpaper.py"
WALL_DIR="/usr/share/backgrounds/siteos"
WALL_FILE="${WALL_DIR}/site-os-topo.png"
SKEL="/etc/skel"
THEME_DST="/usr/share/themes/${THEME_NAME}"

log()  { printf '[site-os] %s\n' "$*"; }
die()  { printf '[site-os][ERROR] %s\n' "$*" >&2; exit 1; }

usage() {
  sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'
}

require_root() {
  [[ "${EUID}" -eq 0 ]] || die "run as root (sudo)"
}

check_path() {
  [[ -e "$1" ]] || die "missing path: $1 (repo layout broken?)"
}

pkg_installed() {
  dpkg -s "$1" >/dev/null 2>&1
}

apt_install() {
  local missing=()
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

step_fonts() {
  log "step: fonts (Terminus primary; VT323/Share Tech Mono cyrillic NOT verified)"
  apt_install fonts-terminus fontconfig
  # Verify the family exists and has Cyrillic coverage before we rely on it.
  if ! fc-list :family | grep -qi 'terminus'; then
    die "Terminus font family not found after install (fc-list)"
  fi
  if fc-list :lang=ru family | grep -qi 'terminus'; then
    log "Terminus has Cyrillic (ru) coverage"
  else
    log "WARNING: Terminus reports no ru coverage; fallback to DejaVu Sans Mono for Cyrillic"
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

  # Desktop wallpaper for new profiles (xfce4-desktop channel, skel).
  local dest="${SKEL}/.config/xfce4/xfconf/xfce-perchannel-xml"
  mkdir -p "${dest}"
  cat > "${dest}/xfce4-desktop.xml" <<EOF
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

  # Per-user default for new profiles.
  mkdir -p "${SKEL}/.config/gtk-3.0"
  install -m 0644 "${THEME_SRC}/gtk-3.0/gtk.css" "${SKEL}/.config/gtk-3.0/gtk.css"
  cat > "${SKEL}/.config/gtk-3.0/settings.ini" <<'EOF'
[Settings]
gtk-theme-name=SiteOS
gtk-font-name=Terminus 11
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
  for state in active inactive prelight pressed; do
    install -m 0644 "${THEME_SRC}/xfwm4/xpm/minimize.xpm" "${dst}/minimize-${state}.xpm"
    install -m 0644 "${THEME_SRC}/xfwm4/xpm/close.xpm" "${dst}/close-${state}.xpm"
  done

  # Default xfwm4 config for new profiles: theme, compositing, opacity.
  local dest="${SKEL}/.config/xfce4/xfconf/xfce-perchannel-xml"
  mkdir -p "${dest}"
  cat > "${dest}/xfwm4.xml" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfwm4" version="1.0">
  <property name="general" type="empty">
    <property name="theme" type="string" value="${THEME_NAME}"/>
    <property name="use_compositing" type="bool" value="true"/>
    <property name="button_layout" type="string" value="O|HMC"/>
  </property>
</channel>
EOF

  # Apply to the current user if an XFCE session is running (no-op otherwise).
  if [[ -n "${SUDO_USER:-}" ]] && command -v xfconf-query >/dev/null 2>&1; then
    sudo -u "${SUDO_USER}" DISPLAY="${DISPLAY:-}" \
      xfconf-query -c xfwm4 -p /general/theme -s "${THEME_NAME}" 2>/dev/null \
      || log "xfconf-query skipped (no X session for ${SUDO_USER})"
  fi
  log "xfwm4-theme: installed to ${dst} (opaque frame; transparency via compositor only)"
}

usage_error() {
  usage
  exit 2
}

# Accepts "--step <name>" or "--step=<name>". Sets global STEP_ARG (no subshell,
# so die/exit terminate the whole script).
parse_args() {
  STEP_ARG=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --help|-h) usage; exit 0 ;;
      --step) STEP_ARG="${2:-}"; shift 2 ;;
      --step=*) STEP_ARG="${1#--step=}"; shift ;;
      *) die "unknown argument: $1" ;;
    esac
  done
  [[ -n "${STEP_ARG}" ]] || usage_error
}

run_step() {
  case "$1" in
    fonts)        step_fonts ;;
    wallpaper)    step_wallpaper ;;
    gtk-theme)    step_gtk_theme ;;
    xfwm4-theme)  step_xfwm4_theme ;;
    all)
      step_fonts
      step_wallpaper
      step_gtk_theme
      step_xfwm4_theme
      ;;
    *) die "unknown step: $1 (fonts|wallpaper|gtk-theme|xfwm4-theme|all)" ;;
  esac
}

parse_args "$@"
require_root
run_step "${STEP_ARG}"
log "done: ${STEP_ARG}"
