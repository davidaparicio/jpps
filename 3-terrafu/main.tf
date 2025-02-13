resource "proxmox_virtual_environment_vm" "_" {
  node_name       = each.value.hv_name
  for_each        = local.vms
  name            = each.value.vm_name
  tags            = ["container.training", var.tag]
  stop_on_destroy = true
  disk {
    datastore_id = "local"
    file_id      = proxmox_virtual_environment_download_file._[each.value.hv_name].id
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

resource "proxmox_virtual_environment_download_file" "_" {
  for_each     = toset(local.hvs)
  content_type = "iso" # mandatory; "iso" for disk images or "vztmpl" for LXC images
  datastore_id = "local"
  node_name    = each.value
  url          = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
}
