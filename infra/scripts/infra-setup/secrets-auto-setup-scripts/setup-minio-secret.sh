#!/bin/bash
# Creates the root credentials secret consumed by the local MinIO deployment.
# Run this before syncing the MinIO ArgoCD app. Skips an existing secret; delete
# the secret first to rotate its credentials.
set -euo pipefail

NAMESPACE="minio"
SECRET_NAME="minio-credentials"
ROOT_USER="minioadmin"

echo "=== MinIO credentials setup ==="
echo "Namespace: $NAMESPACE"
echo "Secret:    $SECRET_NAME"
echo "Root user: $ROOT_USER"
echo ""

if kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" >/dev/null 2>&1; then
  echo "⊘ Secret '$SECRET_NAME' already exists in namespace '$NAMESPACE' — skipping."
  echo ""
  echo "Retrieve credentials with:"
  echo "  kubectl get secret $SECRET_NAME -n $NAMESPACE -o jsonpath='{.data.root-user}' | base64 -d && echo"
  echo "  kubectl get secret $SECRET_NAME -n $NAMESPACE -o jsonpath='{.data.root-password}' | base64 -d && echo"
  exit 0
fi

ROOT_PASSWORD="$(openssl rand -base64 48 | tr -dc 'a-zA-Z0-9' | head -c 32)"
echo "Root password: auto-generated (32 chars, alphanumeric)"

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
kubectl create secret generic "$SECRET_NAME" \
  --namespace "$NAMESPACE" \
  --from-literal=root-user="$ROOT_USER" \
  --from-literal=root-password="$ROOT_PASSWORD" \
  --save-config \
  --dry-run=client -o yaml | kubectl apply -f -

echo ""
echo "✓ Secret '$SECRET_NAME' created in namespace '$NAMESPACE'."
echo ""
echo "Retrieve credentials with:"
echo "  kubectl get secret $SECRET_NAME -n $NAMESPACE -o jsonpath='{.data.root-user}' | base64 -d && echo"
echo "  kubectl get secret $SECRET_NAME -n $NAMESPACE -o jsonpath='{.data.root-password}' | base64 -d && echo"
