#!/bin/sh
#set -eu

# https://factory.talos.dev/image/ce4c980550dd2ab1b17bbf2b08801c7eb59418eafe8f279833297925d67c7515/v1.8.4/nocloud-amd64.iso
# https://factory.talos.dev/?arch=amd64&cmdline-set=true&extensions=-&extensions=siderolabs%2Fzfs&platform=nocloud&target=cloud&version=1.8.4
# https://factory.talos.dev/image/4dd8e3a8b6203d3c14f049da8db4d3bb0d6d3e70c5e89dfcc1e709e81914f63c/v1.8.4/nocloud-amd64.raw.xz

### Here are a few schematic ids:
# ZFS and Intel microcode
#SCHEMATIC_ID="32b1861f04a8e2e7c5458116534762912e2c87f3880fe3dbeaa9da5675fa46fb"
# Qemu agent
SCHEMATIC_ID="ce4c980550dd2ab1b17bbf2b08801c7eb59418eafe8f279833297925d67c7515"
TALOS_VERSION=v1.8.4
CDROM_IMAGE_PATH=/mnt/pve/cephfs/template/iso/talos-$SCHEMATIC_ID-$TALOS_VERSION.iso 
CDROM_IMAGE_URL=https://factory.talos.dev/image/$SCHEMATIC_ID/$TALOS_VERSION/nocloud-amd64.iso
CDROM_IMAGE_REF=cephfs:iso/talos-$SCHEMATIC_ID-$TALOS_VERSION.iso
DISK_IMAGE_PATH=/mnt/pve/cephfs/template/iso/talos-$SCHEMATIC_ID-$TALOS_VERSION.raw
DISK_IMAGE_URL=https://factory.talos.dev/image/$SCHEMATIC_ID/$TALOS_VERSION/nocloud-amd64.raw.xz

BRIDGE=vmbr0
EXTERNAL_IPV6_PREFIX="2001:41d0:d00:7c00"  # OVH VRACK
INTERNAL_IPV6_PREFIX="fdfd:0000:0000:0000"

# IPv6 alloc plan:
# - we have a /64
# - VMs use MAC addresses bc:24:11:00:XX:XX
# - their SLAAC addr will be  EXTERNAL::be24:11ff:fe00:XXXX
# - each cluster will have an ID (let's assume 8 bits for now), noted ZZ
# - podCIDR will be    INTERNAL::00ZZ:0001:0000:0000/96
# - clusterIP range will be  INTERNAL::00ZZ:0002:0000:0000/112
# - LoadBalancer range will be  EXTERNAL::00ZZ:0000:0000:0000/112

_set_node() {
  NODE=$(
    pvesh get /nodes -o json |
    jq -r \
    '[ .[] | {node: .node, freemem: (.maxmem - .mem)} | select(.freemem > 10000000000) ] 
     | sort_by(-.freemem) | .[].node' |
    shuf -n 1
  )
  if [ ! "$NODE" ]; then
    echo "CLUSTER IS FULL. PRESS CTRL-C TO ABORT."
    read
  fi
}

# Apparently the "Proxmox way" would be to use templates.
# I'm not convinced yet; but here is a start :)
_create_template() {
  VMID=$(pvesh get /cluster/nextid)
  qm create $VMID \
    --scsi0 ceph:0,import-from=/root/nocloud-amd64.raw
  qm template $VMID
}

_check_cdrom_image() {
  if ! [ -f "$CDROM_IMAGE_PATH" ]; then
    curl "$CDROM_IMAGE_URL" > "$CDROM_IMAGE_PATH"
  fi
}

_check_disk_image() {
  if ! [ -f "$DISK_IMAGE_PATH" ]; then
    curl "$DISK_IMAGE_URL" | unzstd > "$DISK_IMAGE_PATH"
  fi
}

_create_vm() {
  _check_cdrom_image
  _check_disk_image
  _set_node
  VMID=$(pvesh get /cluster/nextid)
  MACADDR=bc:24:11:00:$(printf "%04x\n" $VMID | sed 's/\(..\)\(..\)/\1:\2/')
  IPV6ADDR="$(printf "$EXTERNAL_IPV6_PREFIX:be24:11ff:fe00:%04x" $VMID)"
  echo "Creating VM $VMID on node $NODE with options $*..." >/dev/tty

  # If we wanted to create from a template, we could use a call like this:
  #pvesh create /nodes/pve-lsd-1/qemu/100/clone \
  #  --newid $VMID \
  #  --target $NODE \
  #  >/dev/tty
  # And then a call like this, to fine-tune the VM configuration:
  #pvesh set /nodes/$NODE/qemu/$VMID/config \
  # ...followed by all the VM options.

  # To create a VM locally, we could use a call like this:
  #qm create $VMID \

  # And to create a call on another node, we can use a call like this:
  pvesh create /nodes/$NODE/qemu --vmid $VMID \
    --agent 1 \
    --bios ovmf \
    --efidisk0 ceph:0 \
    --cores 2 \
    --cpu x86-64-v2-AES \
    --memory 4096 \
    --ostype l26 \
    --net0 virtio=$MACADDR,bridge=$BRIDGE \
    --scsihw virtio-scsi-single \
    --scsi0 ceph:32 \
    --cdrom $CDROM_IMAGE_REF \
    --description "Talos VM #$VMID <br/> $IPV6ADDR" \
    --tags talos \
    "$@" \
    >/dev/tty
  #pvesh set /nodes/$NODE/qemu/$VMID/resize --disk=scsi0 --size=32G >/dev/tty
  pvesh create /nodes/$NODE/qemu/$VMID/status/start >/dev/tty
  echo "$IPV6ADDR"
}

_wait_for() {
        echo -n "Waiting for node $1 to be up..."
        while ! ping -q -c 1 -w 10 $1 >/dev/null; do echo -n .; sleep 1; done
        echo ""
        echo "Node $1 is up."
}

_set_cluster_id () {
  CLUSTER_ID=0
  CONF_DIR=.
  while [ -d $CONF_DIR ]; do
    CLUSTER_ID=$((CLUSTER_ID+1))
    CLUSTER_NAME=$(printf "talos-%03d" $CLUSTER_ID)
    CONF_DIR=conf/$CLUSTER_NAME
  done
  echo "CLUSTER_ID=$CLUSTER_ID"
  echo "CONF_DIR=$CONF_DIR"
}

_inventory_36() {
  echo "$CLUSTER_NAME-cp-1 controlplane $(_create_vm --name $CLUSTER_NAME-cp-1 --cores 2 --memory 4096)"
  echo "$CLUSTER_NAME-cp-2 controlplane $(_create_vm --name $CLUSTER_NAME-cp-2 --cores 2 --memory 4096)"
  echo "$CLUSTER_NAME-cp-3 controlplane $(_create_vm --name $CLUSTER_NAME-cp-3 --cores 2 --memory 4096)"
  echo "$CLUSTER_NAME-worker-1 worker $(_create_vm --name $CLUSTER_NAME-worker-1 --cores 6 --memory 16384)"
  echo "$CLUSTER_NAME-worker-2 worker $(_create_vm --name $CLUSTER_NAME-worker-2 --cores 6 --memory 16384)"
  echo "$CLUSTER_NAME-worker-3 worker $(_create_vm --name $CLUSTER_NAME-worker-3 --cores 6 --memory 16384)"
  echo "$CLUSTER_NAME-worker-4 worker $(_create_vm --name $CLUSTER_NAME-worker-4 --cores 6 --memory 16384)"
  echo "$CLUSTER_NAME-worker-5 worker $(_create_vm --name $CLUSTER_NAME-worker-5 --cores 6 --memory 16384)"
  echo "$CLUSTER_NAME-worker-6 worker $(_create_vm --name $CLUSTER_NAME-worker-6 --cores 6 --memory 16384)"
}

_inventory_12() {
  echo "$CLUSTER_NAME-cp-1 controlplane $(_create_vm --name $CLUSTER_NAME-cp-1 --cores 2 --memory 3072)"
  echo "$CLUSTER_NAME-worker-1 worker $(_create_vm --name $CLUSTER_NAME-worker-1 --cores 2 --memory 3072)"
  echo "$CLUSTER_NAME-worker-2 worker $(_create_vm --name $CLUSTER_NAME-worker-2 --cores 2 --memory 3072)"
}

_create_cluster() {
  _set_cluster_id
  echo "$(date) $CLUSTER_ID start" >>log

  INVENTORY="$(_inventory_12)"

  ENDPOINTS=""
  NODES=""

  while read NAME ROLE ADDR; do
    [ "$NAME" ] || continue
    API_SERVER="https://[$ADDR]:6443"
    break
  done <<EOF
$INVENTORY
EOF

  talosctl gen config $CLUSTER_NAME $API_SERVER \
    --output-dir $CONF_DIR \
    --config-patch '[
      {"op": "add", "path": "/machine/kubelet/extraArgs", "value": {"cloud-provider": "external"}},
      {"op": "add", "path": "/cluster/network/podSubnets/-", "value": "'$INTERNAL_IPV6_PREFIX:$CLUSTER_ID:1:0:0/96'"},
      {"op": "add", "path": "/cluster/network/serviceSubnets/-", "value": "'$INTERNAL_IPV6_PREFIX:$CLUSTER_ID:2:0:0/112'"},
      {"op": "add", "path": "/cluster/network/cni", "value": {"name": "none"}}
    ]' \
    --config-patch-control-plane '[
      {"op": "add", "path": "/machine/features/kubernetesTalosAPIAccess", "value": {"enabled": true, "allowedRoles": ["os:reader"], "allowedKubernetesNamespaces": ["kube-system"]}},
      {"op": "add", "path": "/cluster/controllerManager/extraArgs", "value": {"node-cidr-mask-size-ipv6": "112"}}
    ]' \
    --install-image factory.talos.dev/installer/$SCHEMATIC_ID:$TALOS_VERSION

  (
  while read NAME ROLE ADDR; do
    [ "$NAME" ] || continue
    _wait_for $ADDR
    echo "Applying config to $ROLE node $NAME..."
    talosctl apply-config --insecure --nodes $ADDR --file $CONF_DIR/$ROLE.yaml \
      --config-patch '[
        {"op": "add", "path": "/machine/network/hostname", "value": "'$NAME'"}
      ]'
    NODES="$NODES $ADDR"
    if [ "$ROLE" = "controlplane" ]; then
      ENDPOINTS="$ENDPOINTS $ADDR"
    fi
  done <<EOF
$INVENTORY
EOF

  echo "Waiting 10 seconds for nodes to reboot..."
  sleep 10

  export TALOSCONFIG=$CONF_DIR/talosconfig
  talosctl config endpoints $ENDPOINTS
  talosctl config nodes $NODES

  echo "Waiting for nodes to be back up..."
  echo "(You will see some error messages here. They are expected.)"
  while ! talosctl version >/dev/null; do sleep 10; done
  echo "Nodes are back. We can continue."

  export KUBECONFIG=$CONF_DIR/kubeconfig
  for ADDR in $ENDPOINTS; do
    echo "Bootstrapping with node $ADDR..."
    talosctl bootstrap -e $ADDR -n $ADDR
    talosctl kubeconfig -n $ADDR $KUBECONFIG
    break
  done

  echo "Waiting for Kubernetes control plane to come up..."
  while ! kubectl get nodes 2>/dev/null; do
    sleep 1
  done
  echo "Control plane is up."

  _install_ccm
  _install_csi
  _install_sc

  echo "Installing CNI and MetalLB."
  _install_cilium
  _install_metallb
  echo "Done."
  echo "$(date) $CLUSTER_ID done" >>log
  ) &
}

_install_ccm() {
  pvesh get /access/roles/kubernetes-ccm || 
    pvesh create /access/roles --roleid kubernetes-ccm --privs VM.Audit
  pvesh get /access/users/kubernetes-ccm@pve ||
    pvesh create /access/users --userid kubernetes-ccm@pve
  pvesh set /access/acl --path=/ --roles=kubernetes-ccm --users=kubernetes-ccm@pve
  if pvesh get /access/users/kubernetes-ccm@pve/token/$CLUSTER_NAME; then
    pvesh delete /access/users/kubernetes-ccm@pve/token/$CLUSTER_NAME
  fi
  TOKEN_SECRET=$(pvesh create /access/users/kubernetes-ccm@pve/token/$CLUSTER_NAME --privsep=0 --output-format json | jq -r .value)
  while ! kubectl get namespace kube-system 2>/dev/null; do
    echo "Waiting for kube-system namespace to be available..."
    sleep 1
  done
  kubectl apply -f- <<YAML
apiVersion: v1
kind: Secret
metadata:
  name: proxmox-cloud-controller-manager
  namespace: kube-system
stringData:
  config.yaml: |
    clusters:
      - url: https://10.0.0.1:8006/api2/json
        insecure: true
        token_id: "kubernetes-ccm@pve!$CLUSTER_NAME"
        token_secret: $TOKEN_SECRET
        region: pve-lsd
YAML
  kubectl apply -f https://raw.githubusercontent.com/sergelogvinov/proxmox-cloud-controller-manager/main/docs/deploy/cloud-controller-manager.yml
}

_install_csi() {
  pvesh get /access/roles/kubernetes-csi ||
    pvesh create /access/roles --roleid kubernetes-csi --privs "VM.Audit VM.Config.Disk Datastore.Allocate Datastore.AllocateSpace Datastore.Audit"
  pvesh get /access/users/kubernetes-csi@pve ||
    pvesh create /access/users --userid kubernetes-csi@pve
  pvesh set /access/acl --path=/ --roles=kubernetes-csi --users=kubernetes-csi@pve
  if pvesh get /access/users/kubernetes-csi@pve/token/$CLUSTER_NAME; then
    pvesh delete /access/users/kubernetes-csi@pve/token/$CLUSTER_NAME
  fi
  TOKEN_SECRET=$(pvesh create /access/users/kubernetes-csi@pve/token/$CLUSTER_NAME --privsep=0 --output-format json | jq -r .value)
  kubectl apply -f- <<YAML
apiVersion: v1
kind: Secret
metadata:
  name: proxmox-csi-plugin
  namespace: kube-system
stringData:
  config.yaml: |
    clusters:
      - url: https://10.0.0.1:8006/api2/json
        insecure: true
        token_id: "kubernetes-csi@pve!$CLUSTER_NAME"
        token_secret: $TOKEN_SECRET
        region: pve-lsd
YAML
  curl -fsSL https://raw.githubusercontent.com/sergelogvinov/proxmox-csi-plugin/main/docs/deploy/proxmox-csi-plugin-release.yml |
    sed "s/namespace: csi-proxmox/namespace: kube-system/" |
    kubectl apply -f-
}

_install_sc() {
  kubectl apply -f- <<YAML
---
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: pve-ceph
  annotations:
    storageclass.kubernetes.io/is-default-class: "true" 
parameters:
  csi.storage.k8s.io/fstype: xfs
  storage: ceph
  #cache: directsync|none|writeback|writethrough
  #ssd: "true|false"
provisioner: csi.proxmox.sinextra.dev
allowVolumeExpansion: true
reclaimPolicy: Delete
volumeBindingMode: Immediate
---
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: pve-local
parameters:
  csi.storage.k8s.io/fstype: xfs
  storage: local
  #cache: directsync|none|writeback|writethrough
  #ssd: "true|false"
provisioner: csi.proxmox.sinextra.dev
allowVolumeExpansion: true
reclaimPolicy: Delete
volumeBindingMode: WaitForFirstConsumer
YAML
}

_install_cilium() {
  helm upgrade -i  \
     cilium \
     cilium \
     --repo https://helm.cilium.io/ \
     --version 1.16.4 \
     --namespace kube-system \
     --set autoDirectNodeRoutes=true \
     --set cgroup.autoMount.enabled=false \
     --set cgroup.hostRoot=/sys/fs/cgroup \
     --set ipam.mode=kubernetes \
     --set ipv4NativeRoutingCIDR=10.244.0.0/16 \
     --set ipv6NativeRoutingCIDR=$EXTERNAL_IPV6_PREFIX::/64 \
     --set ipv6.enabled=true \
     --set routingMode=native \
     --set securityContext.capabilities.ciliumAgent="{CHOWN,KILL,NET_ADMIN,NET_RAW,IPC_LOCK,SYS_ADMIN,SYS_RESOURCE,DAC_OVERRIDE,FOWNER,SETGID,SETUID}" \
     --set securityContext.capabilities.cleanCiliumState="{NET_ADMIN,SYS_ADMIN,SYS_RESOURCE}" \
     #
}

_install_metallb() {
helm upgrade -i \
  metallb \
  metallb \
  --repo https://metallb.github.io/metallb \
  --version 0.14.9 \
  --namespace kube-system \
  #
  echo "Waiting for metallb controller to become availlable..."
  kubectl wait deployment metallb-controller --for=condition=Available --namespace kube-system --timeout=5m
kubectl apply -f- <<YAML
---
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: ipv6
  namespace: kube-system
spec:
  addresses:
    - $EXTERNAL_IPV6_PREFIX:$CLUSTER_ID:0:0:1-$EXTERNAL_IPV6_PREFIX:$CLUSTER_ID:0:0:ffff
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: ipv6
  namespace: kube-system
YAML
}

_wait_until_cpu_is_low() {
  echo "Checking which hypervisors have a high CPU or RAM load at the moment..."
  while pvesh get /cluster/resources --output-format json | 
          jq '.[] | select(.type=="node") | select(.cpu>0.5 or .mem/.maxmem>0.9)' | grep .
  do 
    echo "Waiting a bit."
    sleep 10
    echo "Checking again..."
  done
}

_create_many_clusters() {
  N=$1
  for i in $(seq $N); do
    _wait_until_cpu_is_low
    _create_cluster
  done
  wait
  echo "Done."
}

cat <<EOF
Reminder: this script should be sourced, not executed as-is.
After sourcing the script, you can do e.g.:
_create_many_clusters 5
EOF

