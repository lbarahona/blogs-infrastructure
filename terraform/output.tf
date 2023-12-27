resource "local_file" "kubernetes_config" {
  content  = digitalocean_kubernetes_cluster.lbarahona.kube_config.0.raw_config
  filename = "kubeconfig.yml"
}

output "kubeconfig" {
  value = digitalocean_kubernetes_cluster.lbarahona.kube_config.0.raw_config
  sensitive = true
}