#!/bin/bash
# Runs all non-interactive secret setup scripts in secrets-auto-setup-scripts/.
# Run after the cluster is up and kubectl context is set (k3d-local-cluster-1).
# Idempotent: each child script skips secrets that already exist.
#
# Does NOT run argocd/setup-repo-secret.sh — that script is interactive (GitHub App PEM).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
AUTO_SCRIPTS_DIR="$SCRIPT_DIR"

# Add new auto-setup scripts here, in run order.
# postgres before temporal: CNPG bootstrap needs postgres-credentials first,
# and the temporal_user managed role reads temporal-db-credentials from postgres ns.
AUTO_SECRET_SCRIPTS=(
  setup-postgres-secret.sh
  setup-temporal-secret.sh
  setup-pgadmin-secret.sh
)

echo "=== Auto secret setup ==="
echo "Scripts dir: $AUTO_SCRIPTS_DIR"
echo ""

if ! kubectl cluster-info >/dev/null 2>&1; then
  echo "ERROR: kubectl cannot reach the cluster. Is k3d-local-cluster-1 running?" >&2
  exit 1
fi

CURRENT_CONTEXT="$(kubectl config current-context 2>/dev/null || true)"
echo "kubectl context: ${CURRENT_CONTEXT:-<none>}"
echo ""

for script in "${AUTO_SECRET_SCRIPTS[@]}"; do
  script_path="$AUTO_SCRIPTS_DIR/$script"

  if [ ! -f "$script_path" ]; then
    echo "ERROR: script not found: $script_path" >&2
    exit 1
  fi
  if [ ! -x "$script_path" ]; then
    echo "ERROR: script is not executable: $script_path" >&2
    echo "  Run: chmod +x \"$script_path\"" >&2
    exit 1
  fi

  echo "────────────────────────────────────────"
  echo "Running: $script"
  echo "────────────────────────────────────────"
  "$script_path"
  echo ""
done

echo "✓ All auto secret setup scripts completed."
echo ""
echo "Retrieve passwords:"
echo "  kubectl get secret postgres-credentials                -n postgres               -o jsonpath='{.data.password}'    | base64 -d && echo"
echo "  kubectl get secret temporal-db-credentials             -n temporal               -o jsonpath='{.data.password}'    | base64 -d && echo"
echo "  kubectl get secret pgadmin-credentials                 -n pgadmin                -o jsonpath='{.data.password}'    | base64 -d && echo"
echo "  kubectl get secret context-cluster-file-db-credentials -n postgres               -o jsonpath='{.data.password}'    | base64 -d && echo"
echo "  kubectl get secret file-provider-db                    -n k8-context-cluster-ns-1 -o jsonpath='{.data.DATABASE_URL}' | base64 -d && echo"
echo ""
echo "Repo credentials (interactive, run separately):"
echo "  $SCRIPT_DIR/argocd/setup-repo-secret.sh"
