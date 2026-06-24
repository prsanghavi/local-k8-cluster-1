#!/bin/bash
# Creates the pgadmin-credentials secret for the PgAdmin4 Helm chart.
# Run this BEFORE pushing infra/pgadmin/ or syncing the pgadmin ArgoCD app.
# Skips if the secret already exists (delete it first to rotate the password).
#
# Login URL after deploy: http://pgadmin.local
# Add to /etc/hosts first:  127.0.0.1 pgadmin.local
set -euo pipefail

NAMESPACE="pgadmin"
SECRET_NAME="pgadmin-credentials"
EMAIL="admin@local.dev"

echo "=== PgAdmin credentials setup ==="
echo "Namespace: $NAMESPACE"
echo "Secret:    $SECRET_NAME"
echo "Email:     $EMAIL  (set in infra/pgadmin/values.yaml)"
echo ""

if kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" >/dev/null 2>&1; then
  echo "⊘ Secret '$SECRET_NAME' already exists in namespace '$NAMESPACE' — skipping."
  echo ""
  echo "Retrieve the password with:"
  echo "  kubectl get secret $SECRET_NAME -n $NAMESPACE -o jsonpath='{.data.password}' | base64 -d && echo"
  exit 0
fi

# Auto-generate a secure random password — retrieve later with:
#   kubectl get secret pgadmin-credentials -n pgadmin -o jsonpath='{.data.password}' | base64 -d
PASSWORD=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c 32)
echo "Password: auto-generated (32 chars, alphanumeric)"

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# The runix/pgadmin4 chart reads the password from existingSecretPasswordKey: "password"
kubectl create secret generic "$SECRET_NAME" \
  --namespace "$NAMESPACE" \
  --from-literal=password="$PASSWORD" \
  --save-config \
  --dry-run=client -o yaml | kubectl apply -f -

echo ""
echo "✓ Secret '$SECRET_NAME' created in namespace '$NAMESPACE'."
echo ""
echo "After syncing the ArgoCD app, add to /etc/hosts:"
echo "  127.0.0.1 pgadmin.local"
echo ""
echo "Retrieve the password with:"
echo "  kubectl get secret $SECRET_NAME -n $NAMESPACE -o jsonpath='{.data.password}' | base64 -d && echo"
