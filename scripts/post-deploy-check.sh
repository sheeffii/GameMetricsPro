#!/bin/bash
#
# GameMetrics Pro - Post Deployment Health Check
# Verifies infra, platform, Kafka, ArgoCD, and app workloads after running production-deploy.sh
#
# Usage:
#   ./scripts/post-deploy-check.sh [namespace-prefix]
#   Example: ./scripts/post-deploy-check.sh gamemetrics
#
# Notes:
# - Read-only checks (kubectl/argocd); no writes.
# - Exits non-zero on critical failures; warnings are printed but do not fail the script.
# - Optional deeper checks (HTTP/Ingress, ArgoCD sync status, HPA) run when supporting tools/APIs are available.

set -euo pipefail

NS_PREFIX="${1:-gamemetrics}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_ok()    { echo -e "${GREEN}✓${NC} $1"; }
print_warn()  { echo -e "${YELLOW}⚠${NC} $1"; }
print_err()   { echo -e "${RED}✗${NC} $1"; }
print_info()  { echo -e "${BLUE}ℹ${NC} $1"; }
section() {
  echo ""
  echo -e "${GREEN}════════════════════════════════════════════${NC}"
  echo -e "${GREEN}  $1${NC}"
  echo -e "${GREEN}════════════════════════════════════════════${NC}"
  echo ""
}

require_cmds() {
  local missing=()
  for c in kubectl jq; do
    command -v "$c" >/dev/null 2>&1 || missing+=("$c")
  done
  if [ ${#missing[@]} -gt 0 ]; then
    print_err "Missing required tools: ${missing[*]}"
    exit 1
  fi
}

check_cluster() {
  section "Cluster Connectivity"
  if kubectl cluster-info >/dev/null 2>&1; then
    print_ok "kubectl can reach the cluster"
  else
    print_err "kubectl cannot reach the cluster"
    exit 1
  fi
  local ready
  ready=$(kubectl get nodes --no-headers 2>/dev/null | grep -c " Ready " || true)
  print_info "Nodes Ready: ${ready}"
  if [ "$ready" -lt 1 ]; then
    print_err "No ready nodes"
    exit 1
  fi
}

check_namespaces() {
  section "Namespaces"
  local required=(argocd kafka monitoring "${NS_PREFIX}")
  for ns in "${required[@]}"; do
    if kubectl get ns "$ns" >/dev/null 2>&1; then
      print_ok "Namespace exists: $ns"
    else
      print_warn "Namespace missing: $ns"
    fi
  done
}

check_crds() {
  section "CRDs"
  local crds=(kafkas.kafka.strimzi.io kafkatopics.kafka.strimzi.io applications.argoproj.io appprojects.argoproj.io applicationsets.argoproj.io)
  for crd in "${crds[@]}"; do
    if kubectl get crd "$crd" >/dev/null 2>&1; then
      print_ok "CRD present: $crd"
    else
      print_warn "CRD missing: $crd"
    fi
  done
}

check_pods() {
  section "Core Pods"
  local targets=("argocd" "kafka" "monitoring" "${NS_PREFIX}")
  for ns in "${targets[@]}"; do
    if ! kubectl get ns "$ns" >/dev/null 2>&1; then
      print_warn "Skipping pods; namespace missing: $ns"
      continue
    fi
    local bad
    bad=$(kubectl get pods -n "$ns" --no-headers 2>/dev/null | grep -vE 'Running|Completed' || true)
    if [ -z "$bad" ]; then
      print_ok "Pods healthy in $ns"
    else
      print_warn "Non-running pods in $ns:"
      echo "$bad"
    fi
  done
}

check_kafka() {
  section "Kafka (Strimzi)"
  if kubectl get kafka -n kafka >/dev/null 2>&1; then
    kubectl get kafka -n kafka
    kubectl get pods -n kafka -l strimzi.io/cluster=gamemetrics-kafka
    kubectl get kafkatopic -n kafka || true
    print_ok "Kafka resources listed"
  else
    print_warn "Kafka CR not found in namespace kafka"
  fi
}

check_argocd() {
  section "ArgoCD"
  if ! kubectl get ns argocd >/dev/null 2>&1; then
    print_warn "Namespace argocd missing; skipping"
    return
  fi
  kubectl get applications -n argocd 2>/dev/null || print_warn "ArgoCD Application CRs not found"
  kubectl get appprojects -n argocd 2>/dev/null || true
  kubectl get pods -n argocd
  print_ok "ArgoCD status listed"
}

# Optional: show ArgoCD app sync/health via kubectl (no argocd CLI needed)
check_argocd_status() {
  section "ArgoCD Application Status (kubectl)"
  if ! kubectl get ns argocd >/dev/null 2>&1; then
    print_warn "Namespace argocd missing; skipping"
    return
  fi
  local apps
  apps=$(kubectl get applications -n argocd -o json 2>/dev/null || true)
  if [ -z "$apps" ]; then
    print_warn "No ArgoCD applications found"
    return
  fi
  echo "$apps" | jq -r '.items[] | "\(.metadata.name)\tSync:\(.status.sync.status // "Unknown")\tHealth:\(.status.health.status // "Unknown")"' || true
  local desynced
  desynced=$(echo "$apps" | jq -r '.items[] | select(.status.sync.status != "Synced") | .metadata.name' || true)
  if [ -n "$desynced" ]; then
    print_warn "Desynced apps:"
    echo "$desynced"
  else
    print_ok "All ArgoCD apps synced (per status field)"
  fi
}

check_services() {
  section "Workloads & Services"
  if kubectl get ns "${NS_PREFIX}" >/dev/null 2>&1; then
    kubectl get deploy,sts,ds,svc,ing -n "${NS_PREFIX}" 2>/dev/null || true
    kubectl get hpa -n "${NS_PREFIX}" 2>/dev/null || true
    # Check deployment availability
    local bad
    bad=$(kubectl get deploy -n "${NS_PREFIX}" --no-headers 2>/dev/null | awk '$4!="0/0"{if($4!=$5)print}')
    if [ -z "$bad" ]; then
      print_ok "All deployments available in ${NS_PREFIX}"
    else
      print_warn "Deployments not fully available in ${NS_PREFIX}:"
      echo "$bad"
    fi
    # Check endpoints existence
    local ep_bad
    ep_bad=$(kubectl get endpoints -n "${NS_PREFIX}" --no-headers 2>/dev/null | awk '$2=="<none>"{print}')
    if [ -z "$ep_bad" ]; then
      print_ok "Service endpoints populated in ${NS_PREFIX}"
    else
      print_warn "Services without endpoints in ${NS_PREFIX}:"
      echo "$ep_bad"
    fi
    # Expected services (warn if missing)
    local expected_svcs=(event-ingestion event-processor-service recommendation-engine analytics-api notification-service user-service minio qdrant timescaledb)
    for svc in "${expected_svcs[@]}"; do
      if ! kubectl get svc -n "${NS_PREFIX}" "$svc" >/dev/null 2>&1; then
        print_warn "Expected service missing: $svc"
      fi
    done
  else
    print_warn "Namespace ${NS_PREFIX} missing; skipping service checks"
  fi
}

# Optional: HPA detail (detect missing metrics API or missing targets)
check_hpa_detail() {
  section "HPA Detail"
  if ! kubectl get ns "${NS_PREFIX}" >/dev/null 2>&1; then
    print_warn "Namespace ${NS_PREFIX} missing; skipping HPA detail"
    return
  fi
  kubectl get hpa -n "${NS_PREFIX}" -o wide 2>/dev/null || { print_warn "No HPAs found"; return; }
  # Flag HPAs with unknown metrics or missing target ref
  local warn
  warn=$(kubectl get hpa -n "${NS_PREFIX}" -o json 2>/dev/null | jq -r '.items[] | select((.status.conditions[]? | select(.type=="AbleToScale" and .status!="True")) or (.status.currentMetrics==null)) | .metadata.name' || true)
  if [ -n "$warn" ]; then
    print_warn "HPAs with missing metrics/scale issues:"
    echo "$warn"
  fi
}

check_observability() {
  section "Observability"
  if kubectl get ns monitoring >/dev/null 2>&1; then
    kubectl get deploy,sts,svc -n monitoring 2>/dev/null | grep -E "prometheus|grafana|loki|tempo|thanos|alertmanager" || true
    print_ok "Monitoring components listed"
  else
    print_warn "Namespace monitoring missing; skipping"
  fi
}

check_events() {
  section "Recent Events (warning/error)"
  kubectl get events --all-namespaces --field-selector=type!=Normal --sort-by=.lastTimestamp | tail -n 40 || true
}

# Optional: ArgoCD sync/health if argocd CLI is available
check_argocd_sync() {
  section "ArgoCD Sync/Health (optional)"
  if ! command -v argocd >/dev/null 2>&1; then
    print_warn "argocd CLI not installed; skipping"
    return
  fi
  if ! kubectl get ns argocd >/dev/null 2>&1; then
    print_warn "Namespace argocd missing; skipping"
    return
  fi
  # Using port-forward-free approach (argocd CLI talks via port-forward/env); assume in-cluster service
  if ! ARGOCD_OPTS="--grpc-web" argocd app list >/dev/null 2>&1; then
    print_warn "argocd CLI could not list apps (may need ARGOCD_SERVER env/port-forward)"
    return
  fi
  ARGOCD_OPTS="--grpc-web" argocd app list
  ARGOCD_OPTS="--grpc-web" argocd app list | awk 'NR>2 && $6!="Synced"{print}' >/tmp/argocd_desynced || true
  if [ -s /tmp/argocd_desynced ]; then
    print_warn "Desynced apps detected:"
    cat /tmp/argocd_desynced
  else
    print_ok "All ArgoCD apps synced"
  fi
}

# Optional: Simple HTTP checks against internal services using curl pod
http_smoke() {
  section "HTTP Smoke (optional, best-effort)"
  if ! kubectl get ns "${NS_PREFIX}" >/dev/null 2>&1; then
    print_warn "Namespace ${NS_PREFIX} missing; skipping HTTP smoke"
    return
  fi
  # Try to run a transient curl pod (will pull image)
  local targets=("event-ingestion:8080/health" "analytics-api:8080/health" "recommendation-engine:8080/health" "notification-service:8080/health" "event-processor-service:8080/health")
  for t in "${targets[@]}"; do
    local svc="${t%%:*}"
    if ! kubectl get svc -n "${NS_PREFIX}" "$svc" >/dev/null 2>&1; then
      print_warn "Service $svc not found; skipping"
      continue
    fi
    local hostport="${t%%/*}"
    local path="${t#*/}"
    print_info "Probing http://$hostport/$path"
    if kubectl -n "${NS_PREFIX}" run tmp-curl-$$ --rm -i --restart=Never --image=curlimages/curl --quiet --command -- curl -sf "http://$hostport/$path" >/dev/null 2>&1; then
      print_ok "$svc healthcheck OK"
    else
      print_warn "$svc healthcheck failed (curl pod or endpoint issue)"
    fi
  done
}

# Optional: Kafka topic sanity (counts) without produce/consume
check_kafka_topics() {
  section "Kafka Topics Sanity (counts only)"
  if ! kubectl get ns kafka >/dev/null 2>&1; then
    print_warn "Namespace kafka missing; skipping"
    return
  fi
  kubectl get kafkatopic -n kafka || { print_warn "KafkaTopic CRs not found"; return; }
}

main() {
  require_cmds
  check_cluster
  check_namespaces
  check_crds
  check_pods
  check_kafka
  check_argocd
  check_services
  check_observability
  check_argocd_status
  check_argocd_sync
  check_kafka_topics
  check_hpa_detail
  http_smoke
  check_events
  section "Summary"
  print_ok "Post-deploy checks completed (warnings above do not stop exit 0)"
}

main "$@"

