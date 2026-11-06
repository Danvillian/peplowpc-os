#!/usr/bin/bash
# Build PeplowPC OS on a Linux machine (Fedora, or WSL2 with podman) for testing.
#   tools/build-local.sh           build the image as localhost/peplowpc-os:dev
#   tools/build-local.sh iso       also build an installer ISO into ./output
#   tools/build-local.sh qcow2     also build a VM disk (qcow2) into ./output
# ISO and disk builds need root (sudo) and about 20 GB free.
set -euo pipefail

cd "$(dirname "$0")/.."
TARGET="${1:-image}"
IMAGE=localhost/peplowpc-os:dev
BIB=quay.io/centos-bootc/bootc-image-builder:latest

sudo podman build \
    --pull=newer \
    --build-arg IMAGE_VERSION="dev-$(date +%Y%m%d%H%M)" \
    -t "$IMAGE" -f Containerfile .

case "$TARGET" in
image)
    echo "Built $IMAGE"
    ;;
iso | qcow2)
    type=anaconda-iso
    cfg=()
    if [[ "$TARGET" == iso ]]; then
        cfg=(-v ./disk_config/iso.toml:/config.toml:ro)
    else
        type=qcow2
    fi
    mkdir -p output
    sudo podman run --rm --privileged --pull=newer \
        --security-opt label=type:unconfined_t \
        "${cfg[@]}" \
        -v ./output:/output \
        -v /var/lib/containers/storage:/var/lib/containers/storage \
        "$BIB" --type "$type" --rootfs btrfs --local "$IMAGE"
    echo "Output in ./output"
    ;;
*)
    echo "Unknown target: $TARGET (use image, iso or qcow2)" >&2
    exit 2
    ;;
esac
