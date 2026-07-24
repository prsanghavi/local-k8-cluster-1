#!/usr/bin/env bash
set -euo pipefail

PUSH_REGISTRY="localhost:5001"
CLUSTER_REGISTRY="k3d-registry:5000"
IMAGE_NAME="temporal-payload-relay"
TAG="local-$(date +%Y%m%d%H%M%S)"
DESKTOP_ROOT="/Users/pratiksanghavi/Desktop"
REPO_ROOT="$DESKTOP_ROOT/experiments/local-k8-cluster-1"

docker build --platform linux/arm64 \
  -f "$REPO_ROOT/apps/temporal-payload-relay/Dockerfile" \
  -t "$PUSH_REGISTRY/$IMAGE_NAME:$TAG" \
  -t "$PUSH_REGISTRY/$IMAGE_NAME:local" \
  "$DESKTOP_ROOT"
docker push "$PUSH_REGISTRY/$IMAGE_NAME:$TAG"
docker push "$PUSH_REGISTRY/$IMAGE_NAME:local"

echo "Built and pushed: $CLUSTER_REGISTRY/$IMAGE_NAME:$TAG"
echo "The manifests use the local tag for this first local validation."
