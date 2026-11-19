#!/usr/bin/env bash
# Turns localhost/osyx-nvidia:latest into a bootable qcow2 for run.sh.
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
sudo podman run --rm -it --privileged --pull=newer \
  --security-opt label=type:unconfined_t \
  -v "$HERE/config.toml:/config.toml:ro" \
  -v "$OUT:/output" \
  -v /var/lib/containers/storage:/var/lib/containers/storage \
  quay.io/centos-bootc/bootc-image-builder:latest \
  --type qcow2 --rootfs btrfs "$IMAGE"

sudo chown -R "$(id -u):$(id -g)" "$OUT"
echo "disk: $OUT/qcow2/disk.qcow2"
