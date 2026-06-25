#!/bin/bash
# Creates the k3d local-cluster-1 cluster.
# Run once. Data persists to ~/k3d-data/local-cluster-1 across restarts and upgrades.
set -euo pipefail

CLUSTER_NAME="local-cluster-1"
REGISTRY_NAME="registry"        # k3d prefixes this → container/hostname: k3d-registry
REGISTRY_PORT="5001"
DATA_DIR="$HOME/k3d-data/local-cluster-1"

# ── Preflight ──────────────────────────────────────────────────────────────────
if ! command -v k3d &>/dev/null; then
  echo "ERROR: k3d not found. Install it first: brew install k3d" >&2
  exit 1
fi

if k3d cluster list | grep -q "^${CLUSTER_NAME} "; then
  echo "Cluster '${CLUSTER_NAME}' already exists. Run start-cluster.sh to start it."
  exit 0
fi

# ── Create local registry ──────────────────────────────────────────────────────
# Container name: k3d-registry  (k3d prepends "k3d-" to the name)
# Push from host : localhost:5001
# Pull in-cluster: k3d-registry:5001
if k3d registry list 2>/dev/null | grep -q "k3d-${REGISTRY_NAME}"; then
  echo "Registry 'k3d-${REGISTRY_NAME}' already exists, reusing it."
else
  echo "Creating registry 'k3d-${REGISTRY_NAME}' on port ${REGISTRY_PORT}..."
  k3d registry create "$REGISTRY_NAME" --port "$REGISTRY_PORT"
fi

# ── Create cluster ─────────────────────────────────────────────────────────────
# Volume: maps ~/k3d-data/local-cluster-1 into the k3s local-path storage dir.
#   → All PVCs using the default 'local-path' StorageClass will land here.
#
# Ports:
#   80/443   → Traefik ingress (HTTP/HTTPS) via loadbalancer
#   30432    → PostgreSQL primary NodePort (postgres-cluster-1-nodeport)
#   30233    → Temporal gRPC frontend NodePort
#
# NOTE: The full 30000-32767 NodePort range is intentionally NOT mapped here.
# Mapping the entire range caused k3d to fail with "bufio.Scanner: token too long"
# because nginx's startup log line exceeded the 64 KB scanner buffer when
# configured for ~2768 ports. Use `kubectl port-forward` for any other NodePorts.
#
# Two small ranges are mapped, one around each assigned NodePort:
#   30230-30249  → Temporal gRPC frontend (30233)
#   30430-30449  → PostgreSQL primary (30432)
k3d cluster create "$CLUSTER_NAME" \
  --servers 1 \
  --agents 0 \
  --registry-use "k3d-${REGISTRY_NAME}:5000" \
  --volume "$DATA_DIR:/var/lib/rancher/k3s/storage@server:0" \
  --port "80:80@loadbalancer" \
  --port "443:443@loadbalancer" \
  --port "30230-30249:30230-30249@server:0" \
  --port "30430-30449:30430-30449@server:0" \
  --k3s-arg "--tls-san=host.k3d.internal@server:0" \
  --wait

echo ""
echo "✓ Cluster '${CLUSTER_NAME}' created."
echo "  Registry : k3d-${REGISTRY_NAME}:${REGISTRY_PORT}  (push via localhost:${REGISTRY_PORT})"
echo "  kubectl config use-context k3d-${CLUSTER_NAME}"
echo "  Data stored at: $DATA_DIR"
