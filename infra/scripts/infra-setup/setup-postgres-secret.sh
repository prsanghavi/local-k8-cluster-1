#!/bin/bash
# Creates the postgres-credentials secret that the CNPG Cluster bootstrap references.
# Run this BEFORE pushing infra/postgres/ to the repo or syncing the postgres ArgoCD app.
set -euo pipefail

NAMESPACE="postgres"
SECRET_NAME="postgres-credentials"
USERNAME="homeuser"

echo "=== Postgres credentials setup ==="
echo "Namespace: $NAMESPACE"
echo "Secret:    $SECRET_NAME"
echo "Username:  $USERNAME"
echo ""

# Prompt for password (hidden input)
read -rsp "Password for '${USERNAME}': " PASSWORD
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

# Create namespace if it doesn't exist
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# Create / update the secret
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
