# To avoid hardcoding the Digital Ocean API key, we'll use environment variables.
#Example: export TF_VAR_digitalocean_token="<your_token>"

variable "digitalocean_token" {
  description = "Digital Ocean API Token"
}