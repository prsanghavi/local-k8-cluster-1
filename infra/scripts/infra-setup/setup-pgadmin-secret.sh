#!/bin/bash
# Creates the pgadmin-credentials secret for the PgAdmin4 Helm chart.
# Run this BEFORE pushing infra/pgadmin/ or syncing the pgadmin ArgoCD app.
#
# Login URL after deploy: http://pgadmin.local
# Add to /etc/hosts first:  127.0.0.1 pgadmin.local
set -euo pipefail

NAMESPACE="pgadmin"
SECRET_NAME="pgadmin-credentials"
DEFAULT_EMAIL="admin@home.dev"  # .local is reserved (mDNS) — pgadmin rejects it

echo "=== PgAdmin credentials setup ==="
echo "Namespace: $NAMESPACE"
echo "Secret:    $SECRET_NAME"
echo ""

read -rp "Login email [${DEFAULT_EMAIL}]: " EMAIL
EMAIL="${EMAIL:-$DEFAULT_EMAIL}"

read -rsp "Login password: " PASSWORD
echo ""
read -rsp "Confirm password: " PASSWORD_CONFIRM
echo ""

if [ "$PASSWORD" != "$PASSWORD_CONFIRM" ]; then
  echo "ERROR: passwords do not match." >&2
  exit 1
fi

if [ -z "$PASSWORD" ]; then
  echo "ERROR: password cannot be empty." >&2
  exit 1
fi

# Create namespace if needed
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# The runix/pgadmin4 chart reads the password from existingSecretPasswordKey: "password"
kubectl create secret generic "$SECRET_NAME" \
  --namespace "$NAMESPACE" \
  --from-literal=password="$PASSWORD" \
  --save-config \
  --dry-run=client -o yaml | kubectl apply -f -

echo ""
echo "✓ Secret '$SECRET_NAME' created in namespace '$NAMESPACE'."
echo "  Email:    $EMAIL  (set in infra/pgadmin/values.yaml)"
echo "  Password: (stored in secret)"
echo ""
echo "After syncing the ArgoCD app, add to /etc/hosts:"
echo "  127.0.0.1 pgadmin.local"
