#!/bin/sh
set -eu

NODE=pve-lsd-2
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
IMAGE_PATH=/mnt/pve/cephfs/template/iso/noble-server-cloudimg-amd64.img
[ -f "$IMAGE_PATH" ] || curl -fsSL "$IMAGE_URL" -o "$IMAGE_PATH"

VMID=$(pvesh get /cluster/nextid)
MACADDR=bc:24:11:00:$(printf "%04x\n" $VMID | sed 's/\(..\)\(..\)/\1:\2/')
IPV6_HOST="$(printf "be24:11ff:fe00:%04x" $VMID)"

RANDOM_NODE=$(
  pvesh get /cluster/resources --output-format json | 
  jq -r '.[] | select (.type=="node") | .node' |
  shuf -n 1
  )
# Uncomment the following line to put the new VM on a random node
#NODE=$RANDOM_NODE

pvesh create /nodes/$NODE/qemu --vmid $VMID \
  --scsihw virtio-scsi-single --scsi0 $STORAGE:0,import-from=$IMAGE_PATH \
  --net0 virtio=$MACADDR,bridge=$BRIDGE \
  --ipconfig0 ip6=auto \
  --ide2 $STORAGE:cloudinit \
  --boot order=scsi0 \
  --ostype l26 \
  --sshkeys "$(jq -Rr @uri < $SSHKEY)" \
  --tags "$TAGS" \
  #

pvesh set /nodes/$NODE/qemu/$VMID/resize --disk scsi0 --size $DISKSIZE
pvesh create /nodes/$NODE/qemu/$VMID/status/start

echo "NODE=$NODE"
echo "VMID=$VMID"
echo "GLOBAL_IPV6=$IPV6_NET:$IPV6_HOST"
echo "LOCAL_IPV6=fe80::$IPV6_HOST%$BRIDGE"

