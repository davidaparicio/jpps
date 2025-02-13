data "proxmox_virtual_environment_nodes" "_" {}

locals {
  pve_nodes = data.proxmox_virtual_environment_nodes._.names
}

resource "proxmox_virtual_environment_vm" "_" {
  node_name       = local.pve_nodes[each.value.node_index % length(local.pve_nodes)]
  for_each        = local.nodes
  name            = each.value.node_name
  tags            = ["container.training", var.tag]
  stop_on_destroy = true
  disk {
    datastore_id = "ceph"
    file_id      = "cephfs:iso/noble-server-cloudimg-amd64.img"
    interface    = "scsi0"
    size         = 30
  }
  agent {
    enabled = false
  }
  initialization {
    datastore_id = "local"
    user_account {
      username = "ubuntu"
      keys     = [trimspace(tls_private_key.ssh.public_key_openssh)]
    }
    ip_config {
      ipv6 {
        address = "dhcp"
      }
    }
  }
  network_device {
    bridge = "vmbr0"
  }
  operating_system {
    type = "l26"
  }
}
