#!/bin/bash
# Creates the postgres-credentials secret that the CNPG Cluster bootstrap references.
# Run this BEFORE pushing infra/postgres/ to the repo or syncing the postgres ArgoCD app.
# Skips if the secret already exists (delete it first to rotate the password).
set -euo pipefail

NAMESPACE="postgres"
SECRET_NAME="postgres-credentials"
USERNAME="homeuser"

echo "=== Postgres credentials setup ==="
echo "Namespace: $NAMESPACE"
echo "Secret:    $SECRET_NAME"
echo "Username:  $USERNAME"
echo ""

if kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" >/dev/null 2>&1; then
  echo "⊘ Secret '$SECRET_NAME' already exists in namespace '$NAMESPACE' — skipping."
  echo ""
  echo "Retrieve the password with:"
  echo "  kubectl get secret $SECRET_NAME -n $NAMESPACE -o jsonpath='{.data.password}' | base64 -d && echo"
  exit 0
fi

# Auto-generate a secure random password — retrieve later with:
#   kubectl get secret postgres-credentials -n postgres -o jsonpath='{.data.password}' | base64 -d
PASSWORD=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c 32)
echo "Password: auto-generated (32 chars, alphanumeric)"

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# CNPG bootstrap expects keys: username, password
kubectl create secret generic "$SECRET_NAME" \
  --namespace "$NAMESPACE" \
  --from-literal=username="$USERNAME" \
  --from-literal=password="$PASSWORD" \
  --save-config \
  --dry-run=client -o yaml | kubectl apply -f -

echo ""
echo "✓ Secret '$SECRET_NAME' created in namespace '$NAMESPACE'."
echo "  You can now push infra/postgres/ and sync the postgres ArgoCD app."
echo ""
echo "Retrieve the password with:"
echo "  kubectl get secret $SECRET_NAME -n $NAMESPACE -o jsonpath='{.data.password}' | base64 -d && echo"
