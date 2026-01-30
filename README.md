# Infrastructure for my personal blog and projects

## Cluster Optimization

Safe cluster optimizations are available in `scripts/optimize-cluster.sh`. This script applies:

- **Resource Quotas**: Prevent runaway resource consumption
- **Limit Ranges**: Ensure pods have reasonable defaults
- **Pod Security Standards**: Baseline security (blocks dangerous configurations)
- **Cleanup**: Remove completed/failed pods

### Usage

```bash
# Preview changes (dry-run)
./scripts/optimize-cluster.sh --dry-run

# Apply optimizations
./scripts/optimize-cluster.sh
```

### What it does NOT do (intentionally)
- No kernel parameter modifications (risky on managed K8s)
- No privileged containers
- No network policies (can break things if misconfigured)

## Working with Terraform

This repository uses Terraform version `1.6.6`, the `digitalocean/digitalocean` provider version `>2.19.0` and the `hashicorp/kubernetes` provider version `>2.11.0`

## Global Services

All global services are installed/configured with Helm charts.
the helm values files are located in the `global-services` directory.

### Install ingress-nginx

```bash
helm install -n ingress-nginx --create-namespace -f global-services/ingress-nginx-values.yml --set controller.ingressClassResource.default=true ingress-nginx ingress-nginx/ingress-nginx
```

### Install cert-manager

```bash
helm install -n cert-manager --create-namespace cert-manager jetstack/cert-manager --version v1.13.2 --set installCRDs=true
kubectl apply -f global-services/cert-manager-cluster-issuer.yml -n cert-manager
```

### Install Cloudflare external-dns

```bash
kubectl create namespace external-dns
kubectl apply -f global-services/cloudflare-secret.yaml
helm install external-dns bitnami/external-dns -f global-services/external-dns-values.yml -n external-dns
```

### Install MariaDB database for WordPress

```bash
kubectl create namespace mariadb
kubectl apply -f global-services/mariadb-secret.yml
helm install mariadb bitnami/mariadb -f global-services/mariadb-values.yml -n mariadb --set global.storageClass=do-block-storage
```

### Install Redis

```bash
kubectl create namespace lbarahona-blog
kubectl apply -f global-services/redis-secret.yml
helm install redis bitnami/redis -f global-services/redis-values.yml -n lbarahona-blog
```