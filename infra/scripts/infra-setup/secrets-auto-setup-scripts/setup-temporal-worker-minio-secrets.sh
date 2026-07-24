#!/bin/bash
# Copies the local MinIO credentials into the four payload-relay namespaces.
# Values never enter Git; this is intentionally local-development-only.
set -euo pipefail

SOURCE_NAMESPACE="minio"
SOURCE_SECRET="minio-credentials"
TARGET_SECRET="temporal-worker-minio-credentials"
TARGET_NAMESPACES=(
  ob1-tf-eks-de-v2-comms-ns-1
  ob1-tf-eks-de-v2-llm-1-ns-1
  uo-bpo1-de-v2-budy-gilfoyle-ns-1
  uo-bpo1-de-v2-hwhrn-hope-ns-1
)

access_key="$(kubectl get secret "$SOURCE_SECRET" -n "$SOURCE_NAMESPACE" -o jsonpath='{.data.root-user}' | base64 -d)"
secret_key="$(kubectl get secret "$SOURCE_SECRET" -n "$SOURCE_NAMESPACE" -o jsonpath='{.data.root-password}' | base64 -d)"

for namespace in "${TARGET_NAMESPACES[@]}"; do
  if kubectl get secret "$TARGET_SECRET" -n "$namespace" >/dev/null 2>&1; then
    echo "⊘ $namespace/$TARGET_SECRET already exists — skipping."
    continue
  fi
  kubectl create secret generic "$TARGET_SECRET" \
    -n "$namespace" \
    --from-literal=root-user="$access_key" \
    --from-literal=root-password="$secret_key"
  echo "✓ Created $namespace/$TARGET_SECRET"
done
