#!/bin/bash
# Upgrades ArgoCD via Helm.
#
# Typical workflow:
#   1. ArgoCD UI shows the app OutOfSync (new 9.x chart available).
#   2. Run this script, enter the target version when prompted.
#   3. ArgoCD reconciles back to Synced once it's healthy.
set -euo pipefail

NAMESPACE="argocd"
RELEASE="argocd"
CHART="argo/argo-cd"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
VALUES_FILE="$REPO_ROOT/infra/argocd/values.yaml"

# ── Show available 9.x versions ───────────────────────────────────────────────
echo "Fetching available argo/argo-cd versions..."
helm repo update argo -q
echo ""
helm search repo argo/argo-cd --versions | grep '^argo/argo-cd\s*9\.' | head -10
echo ""

# ── Prompt for version ────────────────────────────────────────────────────────
read -rp "Version to install (e.g. 9.7.0): " TARGET_VERSION

if [ -z "$TARGET_VERSION" ]; then
  echo "ERROR: no version entered." >&2
  exit 1
fi

echo ""
echo "Upgrading ArgoCD to chart ${TARGET_VERSION}..."

# ── Upgrade ────────────────────────────────────────────────────────────────────
helm upgrade "$RELEASE" "$CHART" \
  --namespace "$NAMESPACE" \
  --version "$TARGET_VERSION" \
  --values "$VALUES_FILE" \
  --wait \
  --timeout 5m

echo ""
echo "✓ ArgoCD upgraded to chart ${TARGET_VERSION}."
echo "  ArgoCD will reconcile to Synced once it detects the running version matches 9.*"
