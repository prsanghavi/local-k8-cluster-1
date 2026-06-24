#!/bin/bash
# Called by launchd on login. Waits for OrbStack/Docker to be ready,
# then starts the k3d local-cluster-1 cluster if it isn't already running.
set -euo pipefail

CLUSTER_NAME="local-cluster-1"
REGISTRY_NAME="k3d-registry"   # full container name (k3d prepends "k3d-")
DOCKER_SOCKET="/var/run/docker.sock"
MAX_WAIT=120  # seconds to wait for Docker

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

# ── Wait for Docker (OrbStack) ─────────────────────────────────────────────────
log "Waiting for Docker socket..."
elapsed=0
until [ -S "$DOCKER_SOCKET" ] && docker info &>/dev/null; do
  if (( elapsed >= MAX_WAIT )); then
    log "ERROR: Docker not ready after ${MAX_WAIT}s. Giving up."
    exit 1
  fi
  sleep 5
  (( elapsed += 5 ))
done
log "Docker is ready."

# ── Ensure registry is running ────────────────────────────────────────────────
REG_STATE=$(docker inspect --format '{{.State.Running}}' "$REGISTRY_NAME" 2>/dev/null || echo "missing")
if [[ "$REG_STATE" == "true" ]]; then
  log "Registry '${REGISTRY_NAME}' already running."
elif [[ "$REG_STATE" == "false" ]]; then
  log "Starting registry '${REGISTRY_NAME}'..."
  docker start "$REGISTRY_NAME"
else
  log "WARNING: Registry '${REGISTRY_NAME}' not found — run create-cluster.sh to set it up."
fi

# ── Ensure cluster exists ──────────────────────────────────────────────────────
if ! k3d cluster list | grep -q "^${CLUSTER_NAME} "; then
  log "Cluster '${CLUSTER_NAME}' not found — run create-cluster.sh to set it up."
  exit 1
fi

# ── Start if not running ───────────────────────────────────────────────────────
STATE=$(k3d cluster list --no-headers 2>/dev/null | awk -v name="$CLUSTER_NAME" '$1==name {print $2}')
if [[ "$STATE" == *"1/1"* ]]; then
  log "Cluster '${CLUSTER_NAME}' already running."
else
  log "Starting cluster '${CLUSTER_NAME}'..."
  k3d cluster start "$CLUSTER_NAME" --wait
  log "Cluster started."
fi

kubectl config use-context "k3d-${CLUSTER_NAME}" 2>/dev/null || true
log "Done."
