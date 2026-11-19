#!/usr/bin/env bash
# Builds an interactive Anaconda installer ISO from localhost/osyx-nvidia:latest.
#
# bootc-image-builder always writes an unattended kickstart (osbuild.ks:
# clearpart --all, autopart, reboot), even with the Anaconda modules from
# iso.toml enabled. That ISO would wipe every disk without asking. So its
# osbuild.ks is replaced with osyx.ks, which only names the payload; boot
# setup is replayed unchanged by xorriso. Only the safe ISO is kept:
#   output/bootiso/osyx-install.iso
#
# Needs sudo: bootc-image-builder runs privileged and reads root's storage.
set -euo pipefail

IMAGE="${IMAGE:-localhost/osyx-nvidia:latest}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="$HERE/output"

# Images built rootless live in the user's storage; copy into root's.
if ! sudo podman image exists "$IMAGE" \
   || [[ "$(podman image inspect -f '{{.Id}}' "$IMAGE")" != "$(sudo podman image inspect -f '{{.Id}}' "$IMAGE")" ]]; then
  echo "copying $IMAGE into root storage"
  podman save "$IMAGE" | sudo podman load
fi

mkdir -p "$OUT"
sudo podman run --rm -it --privileged --pull=newer --net=host \
  --security-opt label=type:unconfined_t \
  -v "$HERE/iso.toml:/config.toml:ro" \
  -v "$OUT:/output" \
  -v /var/lib/containers/storage:/var/lib/containers/storage \
  quay.io/centos-bootc/bootc-image-builder:latest \
  --type anaconda-iso --use-librepo=True --rootfs btrfs "$IMAGE"

sudo chown -R "$(id -u):$(id -g)" "$OUT"

# Swap in the interactive kickstart (rootless; tools from a Fedora container).
podman run --rm -v "$HERE:/w:z" -w /w registry.fedoraproject.org/fedora:44 bash -euc '
  dnf5 -y -q install xorriso isomd5sum diffutils >/dev/null
  rm -f output/bootiso/osyx-install.iso
  xorriso -indev output/bootiso/install.iso -outdev output/bootiso/osyx-install.iso \
    -boot_image any replay -map osyx.ks /osbuild.ks
  implantisomd5 output/bootiso/osyx-install.iso >/dev/null
  xorriso -osirrox on -indev output/bootiso/osyx-install.iso \
    -extract /osbuild.ks /tmp/osbuild.ks 2>/dev/null
  cmp -s osyx.ks /tmp/osbuild.ks || { echo "kickstart swap failed" >&2; exit 1; }
  if grep -qE "^(clearpart|autopart|zerombr|reboot)" /tmp/osbuild.ks; then
    echo "osbuild.ks still unattended" >&2; exit 1
  fi'

# Never leave the unattended ISO lying around.
rm -f "$OUT/bootiso/install.iso"
echo "iso: $OUT/bootiso/osyx-install.iso"
