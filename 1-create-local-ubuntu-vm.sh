#!/bin/sh
set -eu

BRIDGE=vmbr0
STORAGE=local
SSHKEY=id_rsa.pub
DISKSIZE=20G
TAGS=ubuntu
IPV6_NET="2001:41d0:d00:7c00"

[ -f "$SSHKEY" ] || {
  echo "Copy or generate an SSH key first; e.g.:"
  echo "ssh-keygen -f id_rsa"
  exit 1
}

IMAGE_URL=https://cloud-images.ubuntu.com/daily/server/noble/current/noble-server-cloudimg-amd64.img
IMAGE_PATH=$PWD/noble-server-cloudimg-amd64.img
[ -f "$IMAGE_PATH" ] || curl -fsSL "$IMAGE_URL" -o "$IMAGE_PATH"

VMID=$(pvesh get /cluster/nextid)
MACADDR=bc:24:11:00:$(printf "%04x\n" $VMID | sed 's/\(..\)\(..\)/\1:\2/')
IPV6_HOST="$(printf "be24:11ff:fe00:%04x" $VMID)"

qm create $VMID \
  --scsihw virtio-scsi-single --scsi0 $STORAGE:0,import-from=$IMAGE_PATH \
  --net0 virtio=$MACADDR,bridge=$BRIDGE \
  --ipconfig0 ip6=auto \
  --ide2 $STORAGE:cloudinit \
  --boot order=scsi0 \
  --ostype l26 \
  --sshkey "$SSHKEY" \
  --tags "$TAGS" \
  #

qm disk resize $VMID scsi0 $DISKSIZE
qm start $VMID

echo "VMID=$VMID"
echo "GLOBAL_IPV6=$IPV6_NET:$IPV6_HOST"
echo "LOCAL_IPV6=fe80::$IPV6_HOST%$BRIDGE"

