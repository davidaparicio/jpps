#!/bin/sh
set -eu
TAG=$1

_list_vms() {
  pvesh get /cluster/resources --output-format json | 
    jq -r '.[] | select(.type=="qemu") | select((if .tags then (.tags | split(";")) else [""] end )|index("'$TAG'")) | "/nodes/\(.node)/qemu/\(.vmid)"'
}

echo "I will delete the following VMs:"
_list_vms
echo "Press ENTER to continue, or Ctrl-C to abort."
read junk

for VM in $(_list_vms); do
{
  while ! pvesh create $VM/status/stop; do sleep 3; done
  while ! pvesh delete $VM; do sleep 3; done
} &
done
wait
