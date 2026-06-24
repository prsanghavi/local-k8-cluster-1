#!/bin/bash
# Stops the k3d home-1 cluster (data is preserved in ~/k3d-data).
set -euo pipefail

CLUSTER_NAME="home-1"

if ! k3d cluster list | grep -q "^${CLUSTER_NAME} "; then
  echo "Cluster '${CLUSTER_NAME}' not found."
  exit 1
fi

echo "Stopping cluster '${CLUSTER_NAME}'..."
k3d cluster stop "$CLUSTER_NAME"
echo "✓ Cluster stopped. Data at ~/k3d-data is intact."
