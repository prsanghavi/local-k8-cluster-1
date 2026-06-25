#!/bin/bash
# Creates the ArgoCD GitHub App credential template for the prsanghavi org.
# This is a repo-creds secret — a wildcard that covers all repos under
# https://github.com/prsanghavi without needing per-repo secrets.
#
# Run after install-argocd.sh.
set -euo pipefail

NAMESPACE="argocd"
SECRET_NAME="github-app-repo-creds-1"
ORG_URL="https://github.com/prsanghavi"
APP_ID="4147919"
INSTALLATION_ID="142650815"

echo "=== ArgoCD GitHub App repo credentials ==="
echo "Org:             $ORG_URL"
echo "App ID:          $APP_ID"
echo "Installation ID: $INSTALLATION_ID"
echo ""

# ── Prompt for PEM file ────────────────────────────────────────────────────────
read -rp "Path to GitHub App private key (.pem file): " PEM_PATH
PEM_PATH="${PEM_PATH/#\~/$HOME}"  # expand ~ if used

if [ ! -f "$PEM_PATH" ]; then
  echo "ERROR: File not found: $PEM_PATH" >&2
  exit 1
fi

# ── Write to a temp file and apply ────────────────────────────────────────────
# Using a temp file avoids quoting issues with the multi-line PEM key.
TMPFILE=$(mktemp /tmp/argocd-repo-creds-XXXXXX.yaml)
trap 'rm -f "$TMPFILE"' EXIT

# Indent the PEM content for YAML block scalar
INDENTED_PEM=$(awk '{print "    " $0}' "$PEM_PATH")

cat > "$TMPFILE" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: ${SECRET_NAME}
  namespace: ${NAMESPACE}
  labels:
    argocd.argoproj.io/secret-type: repo-creds
stringData:
  type: git
  url: ${ORG_URL}
  githubAppID: "${APP_ID}"
  githubAppInstallationID: "${INSTALLATION_ID}"
  githubAppPrivateKey: |
${INDENTED_PEM}
EOF

kubectl apply -f "$TMPFILE"

echo ""
echo "✓ Repo credential template created: $SECRET_NAME"
echo "  Covers all repos under: $ORG_URL"
echo ""

# ── Restart ArgoCD to pick up new credentials ─────────────────────────────────
echo "Restarting ArgoCD to pick up new credentials..."
kubectl rollout restart deployment argocd-server        -n "$NAMESPACE"
kubectl rollout restart deployment argocd-repo-server   -n "$NAMESPACE"
kubectl rollout status  deployment argocd-server        -n "$NAMESPACE" --timeout=90s
kubectl rollout status  deployment argocd-repo-server   -n "$NAMESPACE" --timeout=90s

echo ""
echo "✓ Done. ArgoCD can now access all prsanghavi repos."
