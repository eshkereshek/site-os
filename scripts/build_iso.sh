#!/usr/bin/env bash
# Site OS ISO builder. Non-interactive. NOT CHECKED IN VM.
#
# Usage:
#   sudo ./scripts/build_iso.sh /path/to/linuxmint-xfce.iso [output-dir]
#
# Needs root, ~25 GB free space, squashfs-tools xorriso rsync p7zip-full
# (see README.md). Never run on the host system: it works in a chroot.
# Output: <output-dir>/SITEOS.iso (default output-dir: ./out) and its SHA256.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_ISO="${1:-}"
OUT_DIR="${2:-${REPO}/out}"
OUT_ISO="${OUT_DIR}/SITEOS.iso"
WORK="${WORK:-${REPO}/build/work}"
ISO_ROOT="${WORK}/iso"
SQ_ROOT="${WORK}/squashfs-root"
SQ_IN="${ISO_ROOT}/casper/filesystem.squashfs"
VOLID="SITE_OS"

log() { printf '[build-iso] %s\n' "$*"; }
die() { printf '[build-iso][ERROR] %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Usage: sudo ./scripts/build_iso.sh <original-linux-mint-xfce.iso> [output-dir]
Environment: WORK=<dir> to change the build directory (default: build/work).
EOF
}

# Mounts we made, unmounted in reverse order on exit (success or failure).
MOUNTS=()
add_mount() { MOUNTS+=("$1"); }

cleanup() {
  local rc=$?
  local i
  for (( i=${#MOUNTS[@]}-1; i>=0; i-- )); do
    local m="${MOUNTS[$i]}"
    if mountpoint -q "$m" 2>/dev/null; then
      umount -l "$m" 2>/dev/null || log "warning: could not unmount $m"
    fi
  done
  if [[ $rc -ne 0 ]]; then
    log "build FAILED (exit ${rc}); work dir kept for inspection: ${WORK}"
  fi
  exit "$rc"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

require_tools() {
  local t missing=()
  for t in unsquashfs mksquashfs xorriso rsync chroot md5sum sha256sum xz mountpoint; do
    command -v "$t" >/dev/null 2>&1 || missing+=("$t")
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    die "missing tools: ${missing[*]} (apt install squashfs-tools xorriso rsync xz-utils)"
  fi
}

check_args() {
  [[ "${EUID}" -eq 0 ]] || die "run as root (sudo)"
  if [[ -z "${SRC_ISO}" || "${SRC_ISO}" == "-h" || "${SRC_ISO}" == "--help" ]]; then
    usage
    exit 2
  fi
  [[ -f "${SRC_ISO}" ]] || die "source ISO not found: ${SRC_ISO}"
  [[ -f "${REPO}/install.sh" ]] || die "install.sh not found in ${REPO}"
  case "$(uname -m)" in
    x86_64) ;;
    *) die "x86_64 host required" ;;
  esac
}

# Check free space: the squashfs and the ISO each take roughly the ISO size.
check_space() {
  local need_gb=$(( $(stat -c %s "${SRC_ISO}") * 3 / 1024 / 1024 / 1024 + 1 ))
  mkdir -p "${WORK}" "${OUT_DIR}"
  local free_gb
  free_gb=$(( $(df -P --block-size=1G "${WORK}" | awk 'NR==2 {print $4}') ))
  if (( free_gb < need_gb )); then
    die "need about ${need_gb} GB free in ${WORK}, have ${free_gb} GB"
  fi
  log "space: ${free_gb} GB free, about ${need_gb} GB needed"
}

extract_iso() {
  log "extracting ISO to ${ISO_ROOT}"
  rm -rf "${ISO_ROOT}"
  mkdir -p "${ISO_ROOT}"
  xorriso -osirrox on -indev "${SRC_ISO}" -extract / "${ISO_ROOT}" >/dev/null 2>&1 \
    || die "xorriso extraction failed"
  chmod -R u+w "${ISO_ROOT}"
  [[ -f "${SQ_IN}" ]] || die "squashfs not found at casper/filesystem.squashfs (non-Mint layout?)"
}

extract_squashfs() {
  log "unpacking squashfs to ${SQ_ROOT} (this takes a while)"
  rm -rf "${SQ_ROOT}"
  unsquashfs -no-progress -f -d "${SQ_ROOT}" "${SQ_IN}" >/dev/null \
    || die "unsquashfs failed"
}

# Chroot helpers: bind mounts are registered for cleanup.
mount_chroot() {
  mkdir -p "${SQ_ROOT}/proc" "${SQ_ROOT}/sys" "${SQ_ROOT}/dev/pts" "${SQ_ROOT}/run"
  mount -t proc proc "${SQ_ROOT}/proc"; add_mount "${SQ_ROOT}/proc"
  mount -t sysfs sys "${SQ_ROOT}/sys"; add_mount "${SQ_ROOT}/sys"
  mount --bind /dev "${SQ_ROOT}/dev"; add_mount "${SQ_ROOT}/dev"
  mount --bind /dev/pts "${SQ_ROOT}/dev/pts"; add_mount "${SQ_ROOT}/dev/pts"
  mount -t tmpfs tmpfs "${SQ_ROOT}/run"; add_mount "${SQ_ROOT}/run"
  # Keep DNS working for apt inside chroot.
  cp -L /etc/resolv.conf "${SQ_ROOT}/etc/resolv.conf"
}

unmount_chroot() {
  local m
  for m in "${SQ_ROOT}/run" "${SQ_ROOT}/dev/pts" "${SQ_ROOT}/dev" "${SQ_ROOT}/sys" "${SQ_ROOT}/proc"; do
    mountpoint -q "$m" && umount -l "$m"
  done
  MOUNTS=()
}

run_install_in_chroot() {
  log "copying repository into chroot"
  rsync -a --delete --exclude '.git' --exclude 'build' --exclude 'out' \
    "${REPO}/" "${SQ_ROOT}/root/site-os/"

  mount_chroot
  log "running install.sh --step all in chroot"
  chroot "${SQ_ROOT}" /usr/bin/env -i \
    HOME=/root LANG=C.UTF-8 PATH=/usr/sbin:/usr/bin:/sbin:/bin \
    DEBIAN_FRONTEND=noninteractive \
    bash -c 'cd /root/site-os && ./install.sh --step all' \
    || die "install.sh failed in chroot"

  log "cleaning chroot"
  chroot "${SQ_ROOT}" /usr/bin/env -i HOME=/root PATH=/usr/sbin:/usr/bin:/sbin:/bin \
    bash -c 'apt-get clean; rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* /root/site-os; \
             rm -f /root/.bash_history; : > /etc/machine-id 2>/dev/null || true' \
    || die "chroot cleanup failed"
  rm -f "${SQ_ROOT}/etc/resolv.conf"
  unmount_chroot
}

rebuild_squashfs() {
  log "rebuilding squashfs (xz, slow)"
  local new_sq="${WORK}/filesystem.squashfs.new"
  rm -f "${new_sq}"
  mksquashfs "${SQ_ROOT}" "${new_sq}" -comp xz -noappend -no-progress >/dev/null \
    || die "mksquashfs failed"
  mv -f "${new_sq}" "${SQ_IN}"
}

update_manifest_and_size() {
  log "updating filesystem.manifest and filesystem.size"
  local base="${ISO_ROOT}/casper"
  if [[ -f "${base}/filesystem.manifest" ]]; then
    chroot_pkgs_manifest > "${base}/filesystem.manifest"
  fi
  printf '%s' "$(du -sxB1 "${SQ_ROOT}" | cut -f1)" > "${base}/filesystem.size"
}

# Package list from the chroot's dpkg database (same format as the Mint manifest).
chroot_pkgs_manifest() {
  chroot "${SQ_ROOT}" dpkg-query -W --showformat='${Package} ${Version}\n'
}

update_md5() {
  log "recalculating md5sum.txt"
  (
    cd "${ISO_ROOT}"
    find . -type f ! -name md5sum.txt -print0 \
      | sort -z \
      | xargs -0 md5sum > md5sum.txt
  )
}

# BIOS (isolinux/El Torito) + UEFI (EFI image) boot, taken from the original ISO.
build_iso() {
  log "building ISO ${OUT_ISO}"
  local mbr="${WORK}/isohdpfx.bin"
  if [[ -f "${ISO_ROOT}/isolinux/isohdpfx.bin" ]]; then
    cp "${ISO_ROOT}/isolinux/isohdpfx.bin" "${mbr}"
  else
    xorriso -osirrox on -indev "${SRC_ISO}" -extract_boot_images "${WORK}/boot" >/dev/null 2>&1 || true
    cp "${WORK}/boot/isohdpfx.bin" "${mbr}" 2>/dev/null \
      || die "isohdpfx.bin not found; cannot build hybrid BIOS boot"
  fi

  local efi_img="boot/grub/efi.img"
  [[ -f "${ISO_ROOT}/${efi_img}" ]] || efi_img="$(cd "${ISO_ROOT}" && find . -iname 'efi.img' -print -quit | sed 's|^\./||')"
  [[ -n "${efi_img}" && -f "${ISO_ROOT}/${efi_img}" ]] \
    || die "EFI boot image not found in ISO; UEFI boot cannot be built"

  rm -f "${OUT_ISO}"
  xorriso -as mkisofs \
    -r -V "${VOLID}" -J -joliet-long -l \
    -iso-level 3 \
    -partition_offset 16 \
    --grub2-mbr "${mbr}" \
    -append_partition 2 0xef "${ISO_ROOT}/${efi_img}" \
    -appended_part_as_gpt \
    -c boot.catalog \
    -b isolinux/isolinux.bin \
    -no-emul-boot -boot-load-size 4 -boot-info-table \
    -eltorito-alt-boot \
    -e --interval:appended_partition_2:all:: \
    -no-emul-boot -isohybrid-gpt-basdat \
    -o "${OUT_ISO}" "${ISO_ROOT}" >/dev/null 2>&1 \
    || die "xorriso build failed (check BIOS/UEFI layout against the original ISO)"
}

print_result() {
  log "done: ${OUT_ISO}"
  (cd "${OUT_DIR}" && sha256sum SITEOS.iso | tee SITEOS.iso.sha256)
}

main() {
  check_args "$@"
  require_tools
  check_space
  extract_iso
  extract_squashfs
  run_install_in_chroot
  rebuild_squashfs
  update_manifest_and_size
  update_md5
  build_iso
  print_result
}

main "$@"
