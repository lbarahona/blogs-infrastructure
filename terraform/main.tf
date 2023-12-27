#Kubernetes Cluster
resource "digitalocean_kubernetes_cluster" "lbarahona" {
  name    = "lbarahona"
  region  = "nyc1"
  version = "1.28.2-do.0"

  node_pool {
    name       = "lbarahona-nodes"
    size       = "s-1vcpu-2gb"
    node_count = 2
  }
}