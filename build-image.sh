#!/bin/bash
set -e

if [ "$(whoami)" != 'root' ]; then
    echo "You must be root to run this script"
    echo "Try \`sudo su -\` or \`sudo ./build-image.sh\`"
    exit 1
fi

# Ensure standard binaries and root tools are in PATH
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"

# Clear SUDO_USER so build.sh does not reject running under sudo in CI environments
unset SUDO_USER

IMAGE_NAME=${1:-"asahi-fedora-usb.raw"}
IMAGE_SIZE=${2:-"3700M"}

echo "### Creating sparse raw disk image: $IMAGE_NAME ($IMAGE_SIZE)"
rm -f "$IMAGE_NAME" "${IMAGE_NAME}.zst" "${IMAGE_NAME}.zst.sha256"
truncate -s "$IMAGE_SIZE" "$IMAGE_NAME"

echo "### Setting up loopback block device"
LOOP_DEV=$(losetup -Pf --show "$IMAGE_NAME")
echo "### Attached $IMAGE_NAME to $LOOP_DEV"

cleanup() {
    echo "### Cleaning up loop device $LOOP_DEV"
    if [[ -n "$LOOP_DEV" ]]; then
        for part in ${LOOP_DEV}p*; do
            if [[ -e "$part" ]] && [[ -n "$(findmnt -n $part)" ]]; then
                umount $part 2>/dev/null || true
            fi
        done
        losetup -d "$LOOP_DEV" 2>/dev/null || true
    fi
}
trap cleanup EXIT

echo "### Running build.sh on $LOOP_DEV"
./build.sh -d "$LOOP_DEV"

echo "### Build complete. Detaching loop device"
cleanup
trap - EXIT

echo "### Compressing $IMAGE_NAME with zstd"
zstd -T0 --rm "$IMAGE_NAME" -o "${IMAGE_NAME}.zst"
sha256sum "${IMAGE_NAME}.zst" > "${IMAGE_NAME}.zst.sha256"

echo "### Successfully created ${IMAGE_NAME}.zst"
ls -lh "${IMAGE_NAME}.zst"*
