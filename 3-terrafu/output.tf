locals {
  mac_addresses_bytes = {
    for key, value in local.nodes :
    key => split(":", lower(proxmox_virtual_environment_vm._[key].network_device[0].mac_address))
  }
  # Note: that part assumes that the MAC addresses are in the Proxmox range (BC:24:11).
  # This should be updated if other MAC addresses are used.
  # Note that SLAAC requires flipping one bit in the first byte of the address (BC becomes BE).
  ipv6_addresses = {
    for key, value in local.mac_addresses_bytes :
    key => format("fe80::be24:11ff:fe%s:%s%s%%vmbr0", value[3], value[4], value[5])
  }
}

resource "local_file" "ip_addresses" {
  content = join("", formatlist("%s\n", [
    for key, value in local.ipv6_addresses : value
  ]))
  filename        = "hosts"
  file_permission = "0600"
}
