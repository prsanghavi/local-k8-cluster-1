#!/bin/bash
# Creates the temporal-db-credentials secret in two namespaces:
#   - postgres  — CNPG reads it to create/manage the temporal_user role
#   - temporal  — the Temporal chart reads it to connect to postgres
#
# Run this BEFORE pushing infra/postgres/ or infra/temporal/ changes.
set -euo pipefail

SECRET_NAME="temporal-db-credentials"
USERNAME="temporal_user"

echo "=== Temporal DB credentials setup ==="
echo "Secret:   $SECRET_NAME"
echo "Username: $USERNAME"
echo ""

# Auto-generate a secure random password — retrieve later with:
#   kubectl get secret temporal-db-credentials -n temporal -o jsonpath='{.data.password}' | base64 -d
PASSWORD=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c 32)
echo "Password: auto-generated (32 chars, alphanumeric)"

create_secret() {
  local ns="$1"
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
create_secret "postgres"   # CNPG managed role reads from here
create_secret "temporal"   # Temporal chart reads from here

echo ""
echo "✓ Done. Next steps:"
echo "  1. Push infra/postgres/ — CNPG will create temporal_user and the two databases"
echo "  2. Push infra/temporal/ and argocd/apps/temporal.yaml — ArgoCD syncs Temporal"
echo "  3. Add to /etc/hosts:  127.0.0.1 temporal.local"
echo "run following to retrieve the password for temporal_user:"
echo " kubectl get secret temporal-db-credentials -n temporal -o jsonpath='{.data.password}' | base64 -d && echo "