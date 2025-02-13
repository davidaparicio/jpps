terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.70.1"
    }
  }
}

provider "proxmox" {
  endpoint = "https://localhost:8006"
  insecure = true

  # Set these, or set PROXMOX_VE_USERNAME and PROXMOX_VE_PASSWORD
  #username = var.proxmox_username
  #password = var.proxmox_password

  #ssh {
  #  agent       = false
  #  private_key = file("~/.ssh/id_rsa")
  #  username    = "root"
  #}
}
