#!/usr/bin/env bash
# Boots a Site OS ISO in QEMU/KVM for a quick check. NOT CHECKED IN VM.
#
# Usage:
#   ./scripts/test_iso.sh [path/to/SITEOS.iso] [--uefi]
#
# Default: BIOS boot. --uefi: needs OVMF firmware
# (Debian/Ubuntu: apt install ovmf; file /usr/share/OVMF/OVMF_CODE_4M.fd).
# Set OVMF_CODE / OVMF_VARS to override the firmware paths.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ISO="${REPO}/out/SITEOS.iso"
UEFI=0
RAM="4G"
CPUS="${CPUS:-4}"
OVMF_CODE="${OVMF_CODE:-/usr/share/OVMF/OVMF_CODE_4M.fd}"
OVMF_VARS_SRC="${OVMF_VARS_SRC:-/usr/share/OVMF/OVMF_VARS_4M.fd}"

die() { printf '[test-iso][ERROR] %s\n' "$*" >&2; exit 1; }

for arg in "$@"; do
  case "$arg" in
    --uefi) UEFI=1 ;;
    -h|--help)
      sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) ISO="$arg" ;;
  esac
done

[[ -f "$ISO" ]] || die "ISO not found: $ISO (build it with scripts/build_iso.sh)"
command -v qemu-system-x86_64 >/dev/null 2>&1 || die "qemu-system-x86_64 not installed (apt install qemu-system-x86)"
[[ -r /dev/kvm ]] || die "/dev/kvm not accessible: enable KVM or add your user to the kvm group"

args=(
  -enable-kvm
  -cpu host
  -smp "$CPUS"
  -m "$RAM"
  -machine q35
  -device virtio-vga
  -device usb-ehci -device usb-kbd -device usb-tablet
  -netdev user,id=n0 -device virtio-net-pci,netdev=n0
  -cdrom "$ISO"
  -boot d
)

if (( UEFI )); then
  [[ -f "$OVMF_CODE" ]] || die "OVMF firmware not found: $OVMF_CODE (apt install ovmf)"
  # Writable copy of the NVRAM so the test does not change the system firmware.
  vars="$(mktemp --suffix=.fd)"
  trap 'rm -f "$vars"' EXIT
  cp "$OVMF_VARS_SRC" "$vars"
  args+=(
    -drive "if=pflash,format=raw,readonly=on,file=${OVMF_CODE}"
    -drive "if=pflash,format=raw,file=${vars}"
  )
  echo "[test-iso] UEFI boot"
else
  echo "[test-iso] BIOS boot"
fi

exec qemu-system-x86_64 "${args[@]}"
