#!/usr/bin/env bash
set -euo pipefail

PUSH_REGISTRY="localhost:5001"
CLUSTER_REGISTRY="k3d-registry:5000"
IMAGE_NAME="temporal-codec-server"
TAG="local-$(date +%Y%m%d%H%M%S)"
DESKTOP_ROOT="/Users/pratiksanghavi/Desktop"
REPO_ROOT="$DESKTOP_ROOT/experiments/local-k8-cluster-1"

docker build --platform linux/arm64 \
  -f "$REPO_ROOT/apps/temporal-codec-server/Dockerfile" \
  -t "$PUSH_REGISTRY/$IMAGE_NAME:$TAG" \
  "$DESKTOP_ROOT"
docker push "$PUSH_REGISTRY/$IMAGE_NAME:$TAG"

echo "Built and pushed: $CLUSTER_REGISTRY/$IMAGE_NAME:$TAG"
