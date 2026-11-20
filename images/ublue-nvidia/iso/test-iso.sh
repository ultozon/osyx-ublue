#!/usr/bin/env bash
# Boots the installer ISO in a UEFI VM with a fresh, empty 40G disk, like a
# laptop would. Nothing on the host is touched. Software rendering, see
# ../vm/run.sh.
#
#   ./test-iso.sh          boot the installer
#   ./test-iso.sh --disk   boot the installed system from the test disk
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ISO="${ISO:-$HERE/output/bootiso/osyx-${VARIANT:-nvidia}-install.iso}"
DISK="$HERE/output/test-disk.qcow2"
VARS="$HERE/output/test-OVMF_VARS.fd"
OVMF_DIR=/usr/share/edk2/x64

if [[ "${1:-}" != --disk ]]; then
  [[ -f "$ISO" ]] || { echo "no ISO at $ISO" >&2; exit 1; }
  rm -f "$DISK" "$VARS"
  qemu-img create -q -f qcow2 "$DISK" 40G
  cp "$OVMF_DIR/OVMF_VARS.4m.fd" "$VARS"
  boot=(-cdrom "$ISO" -boot order=d)
else
  boot=()
fi

exec qemu-system-x86_64 \
  -enable-kvm -machine q35 -cpu host -smp 4 -m 8G \
  -drive if=pflash,format=raw,readonly=on,file="$OVMF_DIR/OVMF_CODE.4m.fd" \
  -drive if=pflash,format=raw,file="$VARS" \
  -drive file="$DISK",if=virtio,format=qcow2 \
  -device virtio-vga -display gtk \
  -device qemu-xhci -device usb-tablet \
  -nic user,model=virtio-net-pci \
  -monitor unix:"$HERE/output/monitor.sock",server,nowait \
  "${boot[@]}"
