#!/usr/bin/env bash
# DNS Cutover Script — Envoy Gateway Migration
# Created: 2026-03-06 (Nightly Session #18)
#
# This script cuts DNS from the old ingress-nginx LB to the new Envoy Gateway LB.
# It uses Cloudflare API to update DNS records (near-instant with Cloudflare proxy).
#
# ROLLBACK: Run with --rollback flag to point DNS back to the old LB.
#
# Usage:
#   ./cutover.sh                     # Dry run (default)
#   ./cutover.sh --execute           # Actually flip DNS
#   ./cutover.sh --execute --service secondbrain  # Flip one service
#   ./cutover.sh --rollback          # Revert to old LB
#   ./cutover.sh --status            # Show current DNS state
#   ./cutover.sh --test              # Test all routes via new gateway

set -euo pipefail

# Config
OLD_LB_IP="164.90.253.196"
NEW_LB_IP="104.248.108.100"
KUBECONFIG="${KUBECONFIG:-/root/clawd/kubeconfig.yml}"
export KUBECONFIG

# Cloudflare config — reads from environment or ~/.cloudflare
CF_API_TOKEN="${CF_API_TOKEN:-}"
if [[ -z "$CF_API_TOKEN" && -f "$HOME/.cloudflare/token" ]]; then
  CF_API_TOKEN=$(cat "$HOME/.cloudflare/token")
fi

# DNS records to migrate (order: least critical → most critical)
# Format: "hostname zone_name record_type"
declare -a SERVICES=(
  "2ndbrain.lesterbarahona.com lesterbarahona.com A secondbrain"
  "mission.lesterbarahona.com lesterbarahona.com A mission-control"
  "dashboard-kubementor.lesterbarahona.com lesterbarahona.com A kubementor-dashboard"
  "kubementor-api.lesterbarahona.com lesterbarahona.com A kubementor-api"
  # NOTE: kubementor.io is NOT in the same CF account — update manually
  # "kubementor.io kubementor.io A kubementor-landing"
  "argocd.lesterbarahona.com lesterbarahona.com A argocd"
  "lesterbarahona.com lesterbarahona.com A blog"
  "www.lesterbarahona.com lesterbarahona.com A blog-www"
)

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()   { echo -e "${GREEN}[✓]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
error() { echo -e "${RED}[✗]${NC} $*"; }
info()  { echo -e "${BLUE}[i]${NC} $*"; }

# Get Cloudflare zone ID
cf_zone_id() {
  local zone_name="$1"
  curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=${zone_name}" \
    -H "Authorization: Bearer ${CF_API_TOKEN}" \
    -H "Content-Type: application/json" | jq -r '.result[0].id'
}

# Get DNS record ID
cf_record_id() {
  local zone_id="$1" hostname="$2" record_type="$3"
  curl -s -X GET "https://api.cloudflare.com/client/v4/zones/${zone_id}/dns_records?name=${hostname}&type=${record_type}" \
    -H "Authorization: Bearer ${CF_API_TOKEN}" \
    -H "Content-Type: application/json" | jq -r '.result[0].id'
}

# Get current DNS record content
cf_record_content() {
  local zone_id="$1" hostname="$2" record_type="$3"
  curl -s -X GET "https://api.cloudflare.com/client/v4/zones/${zone_id}/dns_records?name=${hostname}&type=${record_type}" \
    -H "Authorization: Bearer ${CF_API_TOKEN}" \
    -H "Content-Type: application/json" | jq -r '.result[0].content // "NOT_FOUND"'
}

# Update DNS record
cf_update_record() {
  local zone_id="$1" record_id="$2" hostname="$3" record_type="$4" content="$5" proxied="${6:-true}"
  curl -s -X PATCH "https://api.cloudflare.com/client/v4/zones/${zone_id}/dns_records/${record_id}" \
    -H "Authorization: Bearer ${CF_API_TOKEN}" \
    -H "Content-Type: application/json" \
    --data "{\"content\":\"${content}\",\"proxied\":${proxied}}" | jq -r '.success'
}

# Test a service through the new gateway
test_service() {
  local hostname="$1" expected_code="${2:-200}"
  local code
  code=$(curl -s -o /dev/null -w "%{http_code}" \
    --resolve "${hostname}:443:${NEW_LB_IP}" \
    "https://${hostname}/" -k --max-time 10 2>/dev/null || echo "000")
  
  if [[ "$code" == "$expected_code" || "$code" == "301" || "$code" == "302" || "$code" == "307" ]]; then
    log "${hostname} → HTTP ${code}"
    return 0
  else
    error "${hostname} → HTTP ${code} (expected ${expected_code})"
    return 1
  fi
}

# Show current DNS status
cmd_status() {
  echo -e "\n${BLUE}═══ DNS Status ═══${NC}\n"
  echo -e "Old LB (ingress-nginx): ${OLD_LB_IP}"
  echo -e "New LB (envoy gateway): ${NEW_LB_IP}\n"
  
  printf "%-45s %-16s %-10s\n" "HOSTNAME" "CURRENT IP" "STATUS"
  printf "%-45s %-16s %-10s\n" "--------" "----------" "------"
  
  for entry in "${SERVICES[@]}"; do
    read -r hostname zone_name record_type label <<< "$entry"
    local resolved
    resolved=$(dig +short "$hostname" @1.1.1.1 2>/dev/null | tail -1)
    
    local status
    if [[ "$resolved" == "$NEW_LB_IP" ]]; then
      status="${GREEN}MIGRATED${NC}"
    elif [[ "$resolved" == "$OLD_LB_IP" ]]; then
      status="${YELLOW}OLD LB${NC}"
    else
      status="${BLUE}PROXIED${NC}"
    fi
    
    printf "%-45s %-16s " "$hostname" "${resolved:-unknown}"
    echo -e "$status"
  done
  echo
}

# Test all routes through new gateway
cmd_test() {
  echo -e "\n${BLUE}═══ Route Testing (via ${NEW_LB_IP}) ═══${NC}\n"
  
  local failures=0
  test_service "2ndbrain.lesterbarahona.com" || ((failures++))
  test_service "mission.lesterbarahona.com" || ((failures++))
  test_service "dashboard-kubementor.lesterbarahona.com" || ((failures++))
  test_service "kubementor-api.lesterbarahona.com" "404" || ((failures++))
  test_service "kubementor.io" || ((failures++))
  test_service "argocd.lesterbarahona.com" || ((failures++))
  test_service "lesterbarahona.com" || ((failures++))
  
  echo
  # Test redirects
  local www_code
  www_code=$(curl -s -o /dev/null -w "%{http_code}" \
    --resolve "www.lesterbarahona.com:80:${NEW_LB_IP}" \
    "http://www.lesterbarahona.com/" --max-time 10 2>/dev/null)
  if [[ "$www_code" == "301" ]]; then
    log "www→apex redirect → HTTP ${www_code}"
  else
    error "www→apex redirect → HTTP ${www_code}"
    ((failures++))
  fi
  
  local http_code
  http_code=$(curl -s -o /dev/null -w "%{http_code}" \
    --resolve "lesterbarahona.com:80:${NEW_LB_IP}" \
    "http://lesterbarahona.com/" --max-time 10 2>/dev/null)
  if [[ "$http_code" == "301" ]]; then
    log "HTTP→HTTPS redirect → HTTP ${http_code}"
  else
    error "HTTP→HTTPS redirect → HTTP ${http_code}"
    ((failures++))
  fi
  
  echo
  if [[ $failures -eq 0 ]]; then
    log "All routes passing! Ready for DNS cutover."
  else
    error "${failures} route(s) failed. Fix before cutover."
  fi
  return $failures
}

# Execute DNS cutover
cmd_cutover() {
  local target_ip="$1"
  local filter_service="${2:-}"
  local dry_run="${3:-true}"
  local direction
  
  if [[ "$target_ip" == "$NEW_LB_IP" ]]; then
    direction="CUTOVER → Envoy Gateway"
  else
    direction="ROLLBACK → ingress-nginx"
  fi
  
  echo -e "\n${BLUE}═══ DNS ${direction} ═══${NC}\n"
  
  if [[ -z "$CF_API_TOKEN" ]]; then
    error "CF_API_TOKEN not set. Export it or create ~/.cloudflare/token"
    exit 1
  fi
  
  if [[ "$dry_run" == "true" ]]; then
    warn "DRY RUN — no changes will be made. Use --execute to apply."
    echo
  fi
  
  local success=0
  local skipped=0
  
  for entry in "${SERVICES[@]}"; do
    read -r hostname zone_name record_type label <<< "$entry"
    
    if [[ -n "$filter_service" && "$label" != "$filter_service" ]]; then
      continue
    fi
    
    info "Processing: ${hostname}"
    
    local zone_id
    zone_id=$(cf_zone_id "$zone_name")
    if [[ -z "$zone_id" || "$zone_id" == "null" ]]; then
      error "  Could not find zone ID for ${zone_name}"
      continue
    fi
    
    local current
    current=$(cf_record_content "$zone_id" "$hostname" "$record_type")
    
    if [[ "$current" == "$target_ip" ]]; then
      warn "  Already pointing to ${target_ip} — skipping"
      ((skipped++))
      continue
    fi
    
    info "  Current: ${current} → Target: ${target_ip}"
    
    if [[ "$dry_run" == "true" ]]; then
      warn "  Would update (dry run)"
    else
      local record_id
      record_id=$(cf_record_id "$zone_id" "$hostname" "$record_type")
      if [[ -z "$record_id" || "$record_id" == "null" ]]; then
        error "  Could not find record ID"
        continue
      fi
      
      local result
      result=$(cf_update_record "$zone_id" "$record_id" "$hostname" "$record_type" "$target_ip")
      if [[ "$result" == "true" ]]; then
        log "  Updated successfully"
        ((success++))
      else
        error "  Update failed"
      fi
    fi
  done
  
  echo
  if [[ "$dry_run" == "false" ]]; then
    log "Cutover complete: ${success} updated, ${skipped} already correct"
    info "Verify with: $0 --status"
    info "Test with: $0 --test"
  fi
}

# Main
case "${1:-}" in
  --status)
    cmd_status
    ;;
  --test)
    cmd_test
    ;;
  --execute)
    service_filter="${3:-}"
    if [[ "${2:-}" == "--service" ]]; then
      service_filter="$3"
    fi
    cmd_cutover "$NEW_LB_IP" "$service_filter" "false"
    ;;
  --rollback)
    service_filter=""
    if [[ "${2:-}" == "--service" ]]; then
      service_filter="$3"
    fi
    cmd_cutover "$OLD_LB_IP" "$service_filter" "false"
    ;;
  --help|-h)
    echo "Usage: $0 [--status|--test|--execute [--service NAME]|--rollback [--service NAME]]"
    echo
    echo "Options:"
    echo "  (default)    Dry run — show what would change"
    echo "  --status     Show current DNS state"
    echo "  --test       Test all routes via new gateway"
    echo "  --execute    Flip DNS to new gateway"
    echo "  --rollback   Revert DNS to old ingress-nginx"
    echo "  --service X  Target a single service (secondbrain, blog, argocd, etc.)"
    echo
    echo "Services (cutover order):"
    for entry in "${SERVICES[@]}"; do
      read -r hostname _ _ label <<< "$entry"
      echo "  ${label}: ${hostname}"
    done
    ;;
  *)
    cmd_cutover "$NEW_LB_IP" "" "true"
    ;;
esac
