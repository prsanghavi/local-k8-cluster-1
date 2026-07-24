#!/usr/bin/env bash
# build-push.sh — Build, tag, push temporal-worker-1 to OrbStack local registry,
#                 then patch deployment.yaml with the SHA tag.
#
# Usage:  ./apps/temporal-worker-1/scripts/build-push.sh
#
# Requirements: docker, git
set -euo pipefail

APP="temporal-worker-1"
# Push from the host Mac via localhost; k3s nodes pull via the container hostname.
# k3d registry listens on 5000 inside Docker; --port 5001 is only the host mapping.
# Push from Mac  → localhost:5001  (host port)
# Pull in-cluster → k3d-registry:5000  (container port, same Docker network)
PUSH_REGISTRY="localhost:5001"
CLUSTER_REGISTRY="k3d-registry:5000"

# Resolve repo root regardless of where the script is called from
REPO_ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
APP_DIR="$REPO_ROOT/apps/$APP"
DEPLOY_FILE="$APP_DIR/k8s/deployment.yaml"

# Determine image tags
SHA="$(git -C "$REPO_ROOT" rev-parse --short HEAD)"
# Build/push use the localhost address; deployment.yaml uses the in-cluster address.
IMG_PUSH_SHA="$PUSH_REGISTRY/$APP:$SHA"
IMG_PUSH_LATEST="$PUSH_REGISTRY/$APP:latest"
IMG_CLUSTER_SHA="$CLUSTER_REGISTRY/$APP:$SHA"

echo "▶ Building $IMG_PUSH_SHA ..."
docker build \
  --platform linux/arm64 \
  -t "$IMG_PUSH_SHA" \
  -t "$IMG_PUSH_LATEST" \
  "$APP_DIR"

echo "▶ Pushing $IMG_PUSH_SHA ..."
docker push "$IMG_PUSH_SHA"

echo "▶ Pushing $IMG_PUSH_LATEST ..."
docker push "$IMG_PUSH_LATEST"

echo "▶ Patching $DEPLOY_FILE → image: $IMG_CLUSTER_SHA"
# macOS-compatible sed (no -i '' backup needed when using a temp file)
sed -i '' "s|image: [^/]*/\{0,1\}[^/]*/$APP:.*|image: $IMG_CLUSTER_SHA|" "$DEPLOY_FILE"

echo ""
echo "✅ Done."
echo "   Image : $IMG_CLUSTER_SHA"
echo "   Commit and push this repo — ArgoCD will sync the new deployment."
