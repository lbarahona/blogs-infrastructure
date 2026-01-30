# Infrastructure for my personal blog and projects

## Working with Terraform

This repository uses Terraform version `1.6.6`, the `digitalocean/digitalocean` provider version `>2.19.0` and the `hashicorp/kubernetes` provider version `>2.11.0`

## Global Services

All global services are installed/configured with Helm charts.
the helm values files are located in the `global-services` directory.

### Prerequisites

Add required Helm repositories:

```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo add jetstack https://charts.jetstack.io
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
```

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

## 📊 Monitoring Stack

Complete monitoring solution with Prometheus, Grafana, and AlertManager for comprehensive observability.

### Install Monitoring Stack

```bash
# Create monitoring namespace
kubectl create namespace monitoring

# Install kube-prometheus-stack (Prometheus + Grafana + AlertManager)
helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  -f global-services/prometheus-values.yml \
  -n monitoring

# Apply custom AlertManager configuration
kubectl apply -f global-services/alertmanager-config.yml

# Apply custom Prometheus rules for WordPress monitoring
kubectl apply -f global-services/wordpress-prometheus-rules.yml

# Apply ServiceMonitors for database metrics
kubectl apply -f global-services/database-servicemonitors.yml
```

### Access Monitoring Services

- **Grafana**: https://monitoring.lesterbarahona.com (admin/SREDashboard2026!)
- **Prometheus**: Port-forward with `kubectl port-forward svc/kube-prometheus-stack-prometheus 9090:9090 -n monitoring`
- **AlertManager**: Port-forward with `kubectl port-forward svc/kube-prometheus-stack-alertmanager 9093:9093 -n monitoring`

### Monitoring Features

- 🎯 **WordPress-specific alerts**: Response time, error rates, database connectivity
- 📊 **Infrastructure monitoring**: Node CPU/memory, disk usage, network
- 🚨 **Smart alerting**: Critical alerts via email, severity-based routing
- 📈 **Custom dashboards**: Pre-built WordPress performance dashboard
- 💾 **Persistent storage**: 30-day metric retention, persistent Grafana configs

### Import WordPress Dashboard

After Grafana is running, import the WordPress dashboard:

```bash
kubectl create configmap wordpress-dashboard \
  --from-file=global-services/wordpress-dashboard.json \
  -n monitoring

# Dashboard will be automatically imported on next Grafana restart
kubectl rollout restart deployment/kube-prometheus-stack-grafana -n monitoring
```

## 🛡️ Security & Backup

### Install Backup Solution (Velero)

```bash
# Create DigitalOcean Spaces bucket for backups first
# Update credentials in global-services/velero-credentials-secret.yml

kubectl create namespace velero
kubectl apply -f global-services/velero-credentials-secret.yml

helm repo add vmware-tanzu https://vmware-tanzu.github.io/helm-charts
helm install velero vmware-tanzu/velero -f global-services/velero-backup-values.yml -n velero
```

### Install Runtime Security (Falco)

```bash
# Install Falco for runtime security monitoring
helm repo add falcosecurity https://falcosecurity.github.io/charts
helm install falco falcosecurity/falco -f global-services/falco-values.yml -n monitoring
```

### Cluster Optimization & Security Hardening

```bash
# Run the comprehensive optimization script
chmod +x scripts/optimize-cluster.sh
./scripts/optimize-cluster.sh
```

### Self-hosted CI/CD Runner

```bash
# Install self-hosted GitHub Actions runner
kubectl create namespace ci-cd
kubectl apply -f global-services/github-actions-runner.yml
```

## 🚀 Quick Deploy Everything

Deploy the complete stack in order:

```bash
# 1. Prerequisites
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo add jetstack https://charts.jetstack.io
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add vmware-tanzu https://vmware-tanzu.github.io/helm-charts
helm repo add falcosecurity https://falcosecurity.github.io/charts
helm repo update

# 2. Core infrastructure
helm install -n ingress-nginx --create-namespace -f global-services/ingress-nginx-values.yml ingress-nginx ingress-nginx/ingress-nginx
helm install -n cert-manager --create-namespace cert-manager jetstack/cert-manager --version v1.13.2 --set installCRDs=true
kubectl apply -f global-services/cert-manager-cluster-issuer.yml

# 3. Databases
kubectl create namespace mariadb && kubectl apply -f global-services/mariadb-secret.yml
helm install mariadb bitnami/mariadb -f global-services/mariadb-values.yml -n mariadb
kubectl create namespace lbarahona-blog && kubectl apply -f global-services/redis-secret.yml
helm install redis bitnami/redis -f global-services/redis-values.yml -n lbarahona-blog

# 4. Monitoring & Security
kubectl create namespace monitoring
helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack -f global-services/prometheus-values.yml -n monitoring
kubectl apply -f global-services/wordpress-prometheus-rules.yml
helm install falco falcosecurity/falco -f global-services/falco-values.yml -n monitoring

# 5. Backup
kubectl create namespace velero && kubectl apply -f global-services/velero-credentials-secret.yml
helm install velero vmware-tanzu/velero -f global-services/velero-backup-values.yml -n velero

# 6. Optimization
./scripts/optimize-cluster.sh
```

## 📊 Monitoring & Observability Features

- **📈 Prometheus**: Metrics collection with 30-day retention
- **📊 Grafana**: Custom WordPress performance dashboards
- **🚨 AlertManager**: Email alerts for critical issues
- **🔍 WordPress Monitoring**: Response time, error rate, database health
- **⚡ Node Metrics**: CPU, memory, disk usage monitoring
- **🛡️ Security Monitoring**: Falco runtime security detection
- **💾 Automated Backups**: Daily/weekly backups to DigitalOcean Spaces

## 🔧 Performance Optimizations

- **Node-level optimizations**: Kernel parameter tuning
- **Resource quotas**: Prevent resource exhaustion
- **Network policies**: Micro-segmentation for security
- **Pod Security Standards**: Enforce security baselines
- **Persistent storage**: Optimized for DigitalOcean Block Storage