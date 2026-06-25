#!/bin/bash
# Creates credentials for the context-cluster file provider in two namespaces:
#
#   postgres               — CNPG reads it to create/manage the context_cluster_file_user role
#   k8-context-cluster-ns-1 — file-provider reads DATABASE_URL from `file-provider-db` secret
#
# CNPG service (read-write primary):
#   postgres-cluster-1-rw.postgres.svc.cluster.local:5432
#
# Run this BEFORE syncing infra/postgres/context-cluster-databases.yaml or deploying
# the context-cluster Helm chart. Idempotent: skips namespaces where secrets already exist.
set -euo pipefail

ROLE_SECRET_NAME="context-cluster-file-db-credentials"
APP_SECRET_NAME="file-provider-db"
USERNAME="context_cluster_file_user"
DB_NAME="context_cluster_file_db"
POSTGRES_HOST="postgres-cluster-1-rw.postgres.svc.cluster.local"
APP_NAMESPACE="k8-context-cluster-ns-1"

echo "=== Context cluster file-provider DB credentials setup ==="
echo "Role secret:   postgres/$ROLE_SECRET_NAME  (CNPG role management)"
echo "App secret:    ${APP_NAMESPACE}/${APP_SECRET_NAME}  (DATABASE_URL for file-provider)"
echo "Username:      $USERNAME"
echo "Database:      $DB_NAME"
echo ""

secret_exists() {
  kubectl get secret "$2" -n "$1" >/dev/null 2>&1
}

# ── Resolve / generate password ───────────────────────────────────────────────
PASSWORD=""
if secret_exists postgres "$ROLE_SECRET_NAME"; then
  PASSWORD="$(kubectl get secret "$ROLE_SECRET_NAME" -n postgres -o jsonpath='{.data.password}' | base64 -d)"
  echo "Password: reusing from existing postgres/$ROLE_SECRET_NAME"
elif secret_exists "$APP_NAMESPACE" "$APP_SECRET_NAME"; then
  # Extract password from DATABASE_URL in the app secret if role secret was wiped
  DB_URL="$(kubectl get secret "$APP_SECRET_NAME" -n "$APP_NAMESPACE" -o jsonpath='{.data.DATABASE_URL}' | base64 -d)"
  PASSWORD="$(echo "$DB_URL" | sed -E 's|.*://[^:]+:([^@]+)@.*|\1|')"
  echo "Password: reusing from existing ${APP_NAMESPACE}/${APP_SECRET_NAME}"
fi

if [ -z "$PASSWORD" ]; then
  PASSWORD=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c 32)
  echo "Password: auto-generated (32 chars, alphanumeric)"
fi

DATABASE_URL="postgres://${USERNAME}:${PASSWORD}@${POSTGRES_HOST}:5432/${DB_NAME}?sslmode=require"

# ── postgres namespace: CNPG role secret (username + password) ────────────────
if secret_exists postgres "$ROLE_SECRET_NAME"; then
  echo "⊘ postgres/$ROLE_SECRET_NAME already exists — skipping"
else
  kubectl create namespace postgres --dry-run=client -o yaml | kubectl apply -f -

  kubectl create secret generic "$ROLE_SECRET_NAME" \
    --namespace postgres \
    --from-literal=username="$USERNAME" \
    --from-literal=password="$PASSWORD" \
    --save-config \
    --dry-run=client -o yaml | kubectl apply -f -

  echo "✓ postgres/$ROLE_SECRET_NAME created"
fi

# ── app namespace: DATABASE_URL secret ────────────────────────────────────────
if secret_exists "$APP_NAMESPACE" "$APP_SECRET_NAME"; then
  echo "⊘ ${APP_NAMESPACE}/${APP_SECRET_NAME} already exists — skipping"
else
  kubectl create namespace "$APP_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

  kubectl create secret generic "$APP_SECRET_NAME" \
    --namespace "$APP_NAMESPACE" \
    --from-literal=DATABASE_URL="$DATABASE_URL" \
    --save-config \
    --dry-run=client -o yaml | kubectl apply -f -

  echo "✓ ${APP_NAMESPACE}/${APP_SECRET_NAME} created"
fi

echo ""
echo "✓ Done. Next steps:"
echo "  1. Sync infra/postgres/ in ArgoCD — CNPG will create the role and database"
echo "  2. Deploy (or sync) the context-cluster Helm chart into ${APP_NAMESPACE}"
echo ""
echo "Retrieve credentials:"
echo "  kubectl get secret $ROLE_SECRET_NAME -n postgres -o jsonpath='{.data.password}' | base64 -d && echo"
echo "  kubectl get secret $APP_SECRET_NAME -n $APP_NAMESPACE -o jsonpath='{.data.DATABASE_URL}' | base64 -d && echo"
