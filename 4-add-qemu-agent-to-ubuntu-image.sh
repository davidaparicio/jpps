#!/bin/sh
set -eu

DOWNLOAD_LINK=https://cloud-images.ubuntu.com/daily/server/noble/current/noble-server-cloudimg-amd64.img
IMAGE_NAME=noble-server-cloudimg-amd64.img

if [ -f "$IMAGE_NAME" ]; then
  echo "Image $IMAGE_NAME already exists. Doing nothing."
  exit 1
fi

echo "Downloading $DOWNLOAD_LINK..."
curl -fSL "$DOWNLOAD_LINK" > "$IMAGE_NAME"

virt-customize -a $IMAGE_NAME --update --install qemu-guest-agent --run-command "apt clean"
virt-sysprep -a $IMAGE_NAME --operations defaults,-customize
virt-sparsify --in-place $IMAGE_NAME

echo "Done. You can now run a VM with that image. Don't forget:"
echo "--agent=1 --netconfig0 ip=dhcp"
