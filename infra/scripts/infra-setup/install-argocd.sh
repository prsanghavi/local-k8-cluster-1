#!/bin/bash
# Installs ArgoCD via Helm into the home-1 cluster.
# Run once after the cluster is up. After install, hand control to ArgoCD itself:
#   1. ./setup-repo-secret.sh
#   2. kubectl apply -f argocd/apps/argocd.yaml
#   3. kubectl apply -f argocd/root-app.yaml
set -euo pipefail

NAMESPACE="argocd"
RELEASE="argocd"
CHART="argo/argo-cd"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
VALUES_FILE="$REPO_ROOT/infra/argocd/values.yaml"

if [ ! -f "$VALUES_FILE" ]; then
  echo "ERROR: values file not found at $VALUES_FILE" >&2
  exit 1
fi

# ── Helm repo ──────────────────────────────────────────────────────────────────
echo "Adding argo Helm repo..."
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update argo

# ── Namespace ─────────────────────────────────────────────────────────────────
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# ── Install / upgrade ─────────────────────────────────────────────────────────
echo "Installing ArgoCD (this takes ~2 min)..."
helm upgrade --install "$RELEASE" "$CHART" \
  --namespace "$NAMESPACE" \
  --values "$VALUES_FILE" \
  --wait \
  --timeout 5m

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo "✓ ArgoCD installed."
echo ""
echo "Initial admin password:"
kubectl -n "$NAMESPACE" get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d
echo ""
echo ""
echo "Next steps:"
echo "  1. Add to /etc/hosts:      127.0.0.1 argocd.local"
echo "  2. Add repo credentials:   ./setup-repo-secret.sh"
echo "  3. Enable self-management: kubectl apply -f $REPO_ROOT/argocd/apps/argocd.yaml"
echo "  4. Bootstrap root app:     kubectl apply -f $REPO_ROOT/argocd/root-app.yaml"
