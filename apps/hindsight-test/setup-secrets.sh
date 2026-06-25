#!/bin/bash
# Auto-configures namespaces and secrets for hindsight-test.
# Reads database password from existing CNPG credentials.
set -euo pipefail

NAMESPACE="hindsight-test"
SECRET_NAME="hindsight-credentials"

echo "=== Hindsight Test Credentials Setup ==="
echo "Target Namespace: $NAMESPACE"
echo "Secret Name:      $SECRET_NAME"
echo ""

# Get postgres password from existing CNPG default credentials
if ! kubectl get secret postgres-credentials -n postgres >/dev/null 2>&1; then
  echo "ERROR: postgres-credentials secret not found in namespace 'postgres'." >&2
  exit 1
fi

PG_PASSWORD=$(kubectl get secret postgres-credentials -n postgres -o jsonpath='{.data.password}' | base64 -d)

# Retrieve existing LLM key if secret exists, else default to placeholder
LLM_API_KEY="placeholder-openai-api-key"
if kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" >/dev/null 2>&1; then
  EXISTING_KEY=$(kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" -o jsonpath='{.data.HINDSIGHT_API_LLM_API_KEY}' 2>/dev/null | base64 -d || true)
  if [ -n "$EXISTING_KEY" ] && [ "$EXISTING_KEY" != "placeholder-openai-api-key" ]; then
    LLM_API_KEY="$EXISTING_KEY"
    echo "Reusing existing LLM API Key."
  fi
fi

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic "$SECRET_NAME" \
  --namespace "$NAMESPACE" \
  --from-literal=postgres-password="$PG_PASSWORD" \
  --from-literal=HINDSIGHT_API_LLM_API_KEY="$LLM_API_KEY" \
  --save-config \
  --dry-run=client -o yaml | kubectl apply -f -

echo ""
echo "✓ Secret '$SECRET_NAME' configured in namespace '$NAMESPACE'."
echo "To set a real OpenAI key, run:"
echo "  kubectl create secret generic $SECRET_NAME -n $NAMESPACE --from-literal=postgres-password=$PG_PASSWORD --from-literal=HINDSIGHT_API_LLM_API_KEY='sk-...' --dry-run=client -o yaml | kubectl apply -f -"
