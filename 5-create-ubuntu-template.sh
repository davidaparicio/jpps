#!/bin/sh
set -eu

DOWNLOAD_LINK=https://cloud-images.ubuntu.com/daily/server/noble/current/noble-server-cloudimg-amd64.img
IMAGE_NAME=noble-server-cloudimg-amd64.img
IMAGE_SIZE=30G
TEMPLATE_ID=9001
PVE_STORAGE=ceph

if ! [ -f "$IMAGE_NAME.orig" ]; then
  curl -fSL "$DOWNLOAD_LINK" > "$IMAGE_NAME.orig"
fi

cp "$IMAGE_NAME.orig" "$IMAGE_NAME"
qemu-img resize -f qcow2 $IMAGE_NAME $IMAGE_SIZE
virt-customize -a $IMAGE_NAME --update --install qemu-guest-agent --run-command "apt clean"
virt-sysprep -a $IMAGE_NAME --operations defaults,-customize
virt-sparsify --in-place $IMAGE_NAME

qm create $TEMPLATE_ID \
  --agent 1 \
  --cpu x86-64-v2-AES \
  --ostype l26 \
  --scsihw virtio-scsi-single \
  --scsi0 $PVE_STORAGE:0,import-from=$PWD/$IMAGE_NAME \
  --template 1 \
  --tags template \
  "$@"
