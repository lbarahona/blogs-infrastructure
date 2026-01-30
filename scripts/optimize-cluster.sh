#!/bin/bash
# Kubernetes Cluster Optimization Script (Safe Version)
# For lesterbarahona.com infrastructure
#
# This script applies safe, non-destructive optimizations:
# - Resource quotas and limit ranges
# - Pod Security Standards (baseline - not overly restrictive)
# - Cleanup of completed/failed pods
# - Namespace labels for organization

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }

DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
    log_warn "Running in DRY-RUN mode - no changes will be applied"
fi

check_prerequisites() {
    log_step "Checking prerequisites..."
    
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed"
        exit 1
    fi
    
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster"
        exit 1
    fi
    
    log_info "Prerequisites OK"
}

apply_manifest() {
    local description="$1"
    local manifest="$2"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would apply: $description"
        echo "$manifest" | head -20
        echo "..."
    else
        echo "$manifest" | kubectl apply -f -
        log_info "Applied: $description"
    fi
}

setup_resource_quotas() {
    log_step "Setting up resource quotas and limit ranges..."
    
    # LimitRange ensures pods have reasonable defaults
    apply_manifest "LimitRange for lbarahona-blog" "$(cat <<EOF
apiVersion: v1
kind: LimitRange
metadata:
  name: default-limits
  namespace: lbarahona-blog
spec:
  limits:
  - default:
      cpu: 500m
      memory: 512Mi
    defaultRequest:
      cpu: 50m
      memory: 64Mi
    max:
      cpu: "2"
      memory: 2Gi
    min:
      cpu: 10m
      memory: 16Mi
    type: Container
EOF
)"

    # ResourceQuota prevents runaway resource consumption
    apply_manifest "ResourceQuota for lbarahona-blog" "$(cat <<EOF
apiVersion: v1
kind: ResourceQuota
metadata:
  name: compute-quota
  namespace: lbarahona-blog
spec:
  hard:
    requests.cpu: "2"
    requests.memory: 3Gi
    limits.cpu: "4"
    limits.memory: 6Gi
    pods: "20"
    services: "10"
    persistentvolumeclaims: "10"
EOF
)"
}

setup_pod_security() {
    log_step "Setting up Pod Security Standards (baseline)..."
    
    # Baseline is safe for most workloads including WordPress
    # It prevents the most dangerous configurations without being overly restrictive
    
    local namespaces=("lbarahona-blog" "mariadb" "secondbrain")
    
    for ns in "${namespaces[@]}"; do
        if kubectl get namespace "$ns" &>/dev/null; then
            if [[ "$DRY_RUN" == "true" ]]; then
                log_info "[DRY-RUN] Would label namespace $ns with baseline security"
            else
                kubectl label namespace "$ns" \
                    pod-security.kubernetes.io/enforce=baseline \
                    pod-security.kubernetes.io/audit=baseline \
                    pod-security.kubernetes.io/warn=restricted \
                    --overwrite
                log_info "Applied Pod Security Standards to namespace: $ns"
            fi
        else
            log_warn "Namespace $ns not found, skipping"
        fi
    done
}

cleanup_resources() {
    log_step "Cleaning up completed and failed pods..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would delete completed pods:"
        kubectl get pods --field-selector=status.phase=Succeeded --all-namespaces 2>/dev/null || true
        log_info "[DRY-RUN] Would delete failed pods:"
        kubectl get pods --field-selector=status.phase=Failed --all-namespaces 2>/dev/null || true
    else
        local succeeded=$(kubectl delete pods --field-selector=status.phase=Succeeded --all-namespaces 2>&1 || true)
        local failed=$(kubectl delete pods --field-selector=status.phase=Failed --all-namespaces 2>&1 || true)
        log_info "Cleanup complete"
    fi
}

show_cluster_status() {
    log_step "Current cluster status..."
    
    echo ""
    echo "=== Node Resources ==="
    kubectl top nodes 2>/dev/null || kubectl get nodes -o wide
    
    echo ""
    echo "=== Namespaces ==="
    kubectl get namespaces -o custom-columns="NAME:.metadata.name,STATUS:.status.phase,AGE:.metadata.creationTimestamp"
    
    echo ""
    echo "=== Resource Quotas ==="
    kubectl get resourcequota --all-namespaces 2>/dev/null || echo "No resource quotas found"
    
    echo ""
    echo "=== Pod Security Labels ==="
    kubectl get namespaces -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.metadata.labels.pod-security\.kubernetes\.io/enforce}{"\n"}{end}' | column -t
}

main() {
    echo ""
    echo "=========================================="
    echo "  Kubernetes Cluster Optimization Script"
    echo "=========================================="
    echo ""
    
    check_prerequisites
    setup_resource_quotas
    setup_pod_security
    cleanup_resources
    
    echo ""
    log_info "Optimization complete!"
    echo ""
    
    show_cluster_status
    
    echo ""
    echo "=========================================="
    echo "  Next Steps"
    echo "=========================================="
    echo "  1. Monitor resources: kubectl top nodes && kubectl top pods -A"
    echo "  2. Check quotas: kubectl describe quota -n lbarahona-blog"
    echo "  3. Review security: kubectl get pods -A -o jsonpath='{range .items[*]}{.metadata.namespace}/{.metadata.name}: {.spec.securityContext}{\"\\n\"}{end}'"
    echo ""
}

main "$@"
