# Configure terraform remote state {
terraform {
  cloud {
    organization = "lbarahona"

    workspaces {
      name = "lbarahona-blog"
    }
  }
}

# Configure the DigitalOcean Provider
provider "digitalocean" {
  token = var.digitalocean_token
}

# Configure the kubernetes provider
provider "kubernetes" {
  config_path = local_file.kubernetes_config.filename
}