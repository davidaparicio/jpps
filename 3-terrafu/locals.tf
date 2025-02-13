locals {
  nodes = {
    for cn in setproduct(
      range(1, 1 + var.how_many_clusters),
      range(1, 1 + var.nodes_per_cluster)
    ) :
    format("c%03dn%03d", cn[0], cn[1]) => {
      cluster_key  = format("c%03d", cn[0])
      cluster_name = format("%s-%03d", var.tag, cn[0])
      node_name    = format("%s-%03d-%03d", var.tag, cn[0], cn[1])
      node_index   = cn[0] * var.nodes_per_cluster + cn[1]
    }
  }
}
