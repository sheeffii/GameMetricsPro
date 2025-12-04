#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
KUSTOMIZE_PATH="$ROOT_DIR/k8s/argocd/base"
APPS_ROOT="$ROOT_DIR/argocd"

info()  { echo -e "\033[1;34m[INFO]\033[0m $*"; }
ok()    { echo -e "\033[1;32m[OK]\033[0m   $*"; }
warn()  { echo -e "\033[1;33m[WARN]\033[0m $*"; }
error() { echo -e "\033[1;31m[ERR]\033[0m  $*"; }

# 1) Install ArgoCD CRDs + controllers via Kustomize
info "Installing ArgoCD (Kustomize base)..."
kubectl apply -k "$KUSTOMIZE_PATH"

# 2) Wait for ArgoCD components to be ready
info "Waiting for ArgoCD deployments to become ready..."
set +e
for deploy in argocd-server argocd-repo-server argocd-application-controller argocd-applicationset-controller; do
  kubectl -n argocd rollout status deploy/$deploy --timeout=180s || ROLLOUT_ERR=1
done
set -e
if [[ "${ROLLOUT_ERR:-0}" == "1" ]]; then
  warn "Some ArgoCD components did not report ready in time; continuing."
else
  ok "ArgoCD components are ready."
fi

# 3) Apply App of Apps and application manifests (after CRDs exist)
if [[ -f "$APPS_ROOT/app-of-apps.yml" ]]; then
  info "Applying app-of-apps..."
  kubectl apply -f "$APPS_ROOT/app-of-apps.yml"
  ok "App-of-apps applied."
else
  warn "app-of-apps.yml not found at $APPS_ROOT/app-of-apps.yml"
fi

if [[ -f "$APPS_ROOT/apps/applications.yml" ]]; then
  info "Applying applications..."
  kubectl apply -f "$APPS_ROOT/apps/applications.yml"
  ok "Applications applied."
else
  warn "applications.yml not found at $APPS_ROOT/apps/applications.yml"
fi

info "ArgoCD deployed. Access with: kubectl -n argocd port-forward svc/argocd-server 8082:80"
