#!/bin/bash
# Starts the k3d local-cluster-1 cluster and waits for nodes to be ready.
set -euo pipefail

CLUSTER_NAME="local-cluster-1"

if ! k3d cluster list | grep -q "^${CLUSTER_NAME} "; then
  echo "Cluster '${CLUSTER_NAME}' not found. Run create-cluster.sh first."
  exit 1
fi

STATE=$(k3d cluster list --no-headers 2>/dev/null | awk -v name="$CLUSTER_NAME" '$1==name {print $2}')
if [[ "$STATE" == *"1/1"* ]]; then
  echo "Cluster '${CLUSTER_NAME}' is already running."
  kubectl config use-context "k3d-${CLUSTER_NAME}" 2>/dev/null || true
  exit 0
fi

echo "Starting cluster '${CLUSTER_NAME}'..."
k3d cluster start "$CLUSTER_NAME" --wait

kubectl config use-context "k3d-${CLUSTER_NAME}"
echo "Waiting for node to be Ready..."
kubectl wait node --all --for=condition=Ready --timeout=60s

echo "✓ Cluster '${CLUSTER_NAME}' is up."
