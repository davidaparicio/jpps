variable "tag" {
  type    = string
  default = "deployed-with-terraform"
}

variable "how_many_clusters" {
  type    = number
  default = 2
}

variable "vms_per_cluster" {
  type    = number
  default = 3
}
