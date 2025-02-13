data "proxmox_virtual_environment_nodes" "_" {}

locals {

  hvs = data.proxmox_virtual_environment_nodes._.names

  vms = {
    for cn in setproduct(
      range(1, 1 + var.how_many_clusters),
      range(1, 1 + var.vms_per_cluster)
    ) :
    format("c%03dn%03d", cn[0], cn[1]) => {
      cluster_key  = format("c%03d", cn[0])
      cluster_name = format("%s-%03d", var.tag, cn[0])
      vm_name      = format("%s-%03d-%03d", var.tag, cn[0], cn[1])
      vm_index     = cn[0] * var.vms_per_cluster + cn[1]
      hv_name      = local.hvs[(cn[0] * var.vms_per_cluster + cn[1]) % length(local.hvs)]
    }
  }
}
