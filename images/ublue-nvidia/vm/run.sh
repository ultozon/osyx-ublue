#!/usr/bin/env bash
# Boots the test VM. -cpu host exposes AVX2, which asryx needs.
# Graphics default to software rendering (llvmpipe in the guest): with virgl on
# an NVIDIA host, Hyprland renders but the QEMU window stays black.
#
#   ./run.sh            changes persist in disk.qcow2
#   ./run.sh -snapshot  throw away all changes on exit
#
# Hyprland may come up at 640x480 (QEMU's preferred EDID mode). Inside the VM:
#   hyprctl eval 'hl.monitor({ output = "Virtual-1", mode = "1920x1080@60", position = "auto", scale = 1 })'
# VM_GL=1 uses virgl (host-GPU 3D) instead.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DISK="$HERE/output/qcow2/disk.qcow2"
[[ -f "$DISK" ]] || { echo "no disk at $DISK, run build-disk.sh first" >&2; exit 1; }

if [[ "${VM_GL:-0}" == 1 ]]; then
  gpu=(-device virtio-vga-gl -display gtk,gl=on)
else
  gpu=(-device virtio-vga -display gtk)
fi

exec qemu-system-x86_64 \
  -enable-kvm -machine q35 -cpu host -smp "${VM_CPUS:-4}" -m "${VM_MEM:-8G}" \
  -drive file="$DISK",if=virtio,format=qcow2 \
  "${gpu[@]}" \
  -nic user,model=virtio-net-pci,hostfwd=tcp::2222-:22 \
  -audiodev pipewire,id=snd0 -device intel-hda -device hda-duplex,audiodev=snd0 \
  "$@"
