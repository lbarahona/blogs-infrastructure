#!/bin/bash
# Kubernetes Cluster Optimization and Security Hardening Script
# For lesterbarahona.com infrastructure

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if kubectl is available
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed or not in PATH"
        exit 1
    fi
    
    # Check if helm is available
    if ! command -v helm &> /dev/null; then
        log_error "helm is not installed or not in PATH"
        exit 1
    fi
    
    # Check cluster connectivity
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster"
        exit 1
    fi
    
    log_info "Prerequisites check passed"
}

optimize_node_performance() {
    log_info "Applying node performance optimizations..."
    
    # Create node performance optimization DaemonSet
    cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: node-optimizer
  namespace: kube-system
spec:
  selector:
    matchLabels:
      name: node-optimizer
  template:
    metadata:
      labels:
        name: node-optimizer
    spec:
      hostPID: true
      hostNetwork: true
      containers:
      - name: node-optimizer
        image: busybox:1.35
        command:
        - /bin/sh
        - -c
        - |
          # Optimize kernel parameters
          echo 'net.core.somaxconn = 65535' >> /proc/sys/net/core/somaxconn || true
          echo 'net.ipv4.tcp_max_syn_backlog = 65535' >> /proc/sys/net/ipv4/tcp_max_syn_backlog || true
          echo 'net.ipv4.ip_local_port_range = 1024 65535' >> /proc/sys/net/ipv4/ip_local_port_range || true
          echo 'fs.file-max = 1048576' >> /proc/sys/fs/file-max || true
          
          # Sleep forever
          while true; do sleep 3600; done
        securityContext:
          privileged: true
        resources:
          requests:
            cpu: 10m
            memory: 10Mi
          limits:
            cpu: 100m
            memory: 50Mi
      tolerations:
      - key: node-role.kubernetes.io/master
        effect: NoSchedule
EOF

    log_info "Node performance optimizations applied"
}

setup_pod_security_policies() {
    log_info "Setting up Pod Security Standards..."
    
    # Apply Pod Security Standards to critical namespaces
    kubectl label namespace lbarahona-blog pod-security.kubernetes.io/enforce=restricted --overwrite
    kubectl label namespace lbarahona-blog pod-security.kubernetes.io/audit=restricted --overwrite
    kubectl label namespace lbarahona-blog pod-security.kubernetes.io/warn=restricted --overwrite
    
    kubectl label namespace mariadb pod-security.kubernetes.io/enforce=restricted --overwrite
    kubectl label namespace mariadb pod-security.kubernetes.io/audit=restricted --overwrite
    kubectl label namespace mariadb pod-security.kubernetes.io/warn=restricted --overwrite
    
    kubectl label namespace monitoring pod-security.kubernetes.io/enforce=baseline --overwrite
    kubectl label namespace monitoring pod-security.kubernetes.io/audit=baseline --overwrite
    kubectl label namespace monitoring pod-security.kubernetes.io/warn=baseline --overwrite
    
    log_info "Pod Security Standards configured"
}

setup_network_policies() {
    log_info "Setting up network policies..."
    
    # Default deny all network policy for blog namespace
    cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: lbarahona-blog
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-blog-traffic
  namespace: lbarahona-blog
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: wordpress
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: ingress-nginx
  - from:
    - namespaceSelector:
        matchLabels:
          name: monitoring
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          name: mariadb
    ports:
    - protocol: TCP
      port: 3306
  - to:
    - namespaceSelector:
        matchLabels:
          name: lbarahona-blog
    ports:
    - protocol: TCP
      port: 6379
  - {} # Allow all outbound for external APIs
EOF

    log_info "Network policies configured"
}

enable_audit_logging() {
    log_info "Configuring audit logging..."
    
    # Note: This would require cluster-level configuration
    # For DigitalOcean Managed Kubernetes, this is handled by the platform
    log_warn "Audit logging requires cluster-level configuration (managed by DigitalOcean)"
}

setup_resource_quotas() {
    log_info "Setting up resource quotas..."
    
    # Resource quota for blog namespace
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ResourceQuota
metadata:
  name: blog-quota
  namespace: lbarahona-blog
spec:
  hard:
    requests.cpu: "1000m"
    requests.memory: 2Gi
    limits.cpu: "2000m"
    limits.memory: 4Gi
    persistentvolumeclaims: "5"
    services: "5"
    secrets: "10"
    configmaps: "10"
---
apiVersion: v1
kind: LimitRange
metadata:
  name: blog-limits
  namespace: lbarahona-blog
spec:
  limits:
  - default:
      cpu: 500m
      memory: 512Mi
    defaultRequest:
      cpu: 100m
      memory: 128Mi
    type: Container
EOF

    log_info "Resource quotas configured"
}

cleanup_unused_resources() {
    log_info "Cleaning up unused resources..."
    
    # Remove unused images
    kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' | while read node; do
        log_info "Cleaning up images on node: $node"
        kubectl debug node/$node -it --image=busybox -- sh -c "crictl rmi --prune" || true
    done
    
    # Clean up completed pods
    kubectl delete pods --field-selector=status.phase=Succeeded --all-namespaces || true
    kubectl delete pods --field-selector=status.phase=Failed --all-namespaces || true
    
    log_info "Cleanup completed"
}

main() {
    log_info "Starting cluster optimization and security hardening..."
    
    check_prerequisites
    optimize_node_performance
    setup_pod_security_policies
    setup_network_policies
    enable_audit_logging
    setup_resource_quotas
    cleanup_unused_resources
    
    log_info "Cluster optimization completed successfully!"
    log_info "Next steps:"
    echo "  1. Monitor cluster performance with: kubectl top nodes"
    echo "  2. Check security policies with: kubectl get psp,networkpolicies --all-namespaces"
    echo "  3. Review monitoring in Grafana at: https://monitoring.lesterbarahona.com"
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi