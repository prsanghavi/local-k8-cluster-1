#!/bin/bash
# Creates the temporal-db-credentials secret in two namespaces:
#   - postgres  — CNPG reads it to create/manage the temporal_user role
#   - temporal  — the Temporal chart reads it to connect to postgres
#
# Run this BEFORE pushing infra/postgres/ or infra/temporal/ changes.
# Skips namespaces where the secret already exists (delete to rotate).
# Reuses the password from an existing copy so both namespaces stay in sync.
set -euo pipefail

SECRET_NAME="temporal-db-credentials"
USERNAME="temporal_user"
NAMESPACES=(postgres temporal)

echo "=== Temporal DB credentials setup ==="
echo "Secret:   $SECRET_NAME"
echo "Username: $USERNAME"
echo ""

secret_exists() {
  kubectl get secret "$SECRET_NAME" -n "$1" >/dev/null 2>&1
}

PASSWORD=""
for ns in "${NAMESPACES[@]}"; do
  if secret_exists "$ns"; then
    PASSWORD="$(kubectl get secret "$SECRET_NAME" -n "$ns" -o jsonpath='{.data.password}' | base64 -d)"
    break
  fi
done

all_exist=true
for ns in "${NAMESPACES[@]}"; do
  if ! secret_exists "$ns"; then
    all_exist=false
    break
  fi
done

if [ "$all_exist" = true ]; then
  echo "⊘ Secret '$SECRET_NAME' already exists in postgres and temporal — skipping."
  echo ""
  echo "Retrieve the password with:"
  echo "  kubectl get secret $SECRET_NAME -n temporal -o jsonpath='{.data.password}' | base64 -d && echo"
  exit 0
fi

if [ -n "$PASSWORD" ]; then
  echo "Password: reusing from existing secret"
else
  # Auto-generate a secure random password — retrieve later with:
  #   kubectl get secret temporal-db-credentials -n temporal -o jsonpath='{.data.password}' | base64 -d
  PASSWORD=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c 32)
  echo "Password: auto-generated (32 chars, alphanumeric)"
fi

create_secret() {
  local ns="$1"

  if secret_exists "$ns"; then
    echo "  ⊘ $ns/$SECRET_NAME already exists — skipping"
    return 0
  fi

  kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f -

  kubectl create secret generic "$SECRET_NAME" \
    --namespace "$ns" \
    --from-literal=username="$USERNAME" \
    --from-literal=password="$PASSWORD" \
    --save-config \
    --dry-run=client -o yaml | kubectl apply -f -

  echo "  ✓ $ns/$SECRET_NAME"
}

echo "Creating secret in required namespaces..."
create_secret "postgres"
create_secret "temporal"

echo ""
echo "✓ Done. Next steps:"
echo "  1. Push infra/postgres/ — CNPG will create temporal_user and the two databases"
echo "  2. Push infra/temporal/ and argocd/apps/temporal.yaml — ArgoCD syncs Temporal"
echo "  3. Add to /etc/hosts:  127.0.0.1 temporal.local"
echo ""
echo "Retrieve the password with:"
echo "  kubectl get secret $SECRET_NAME -n temporal -o jsonpath='{.data.password}' | base64 -d && echo"
