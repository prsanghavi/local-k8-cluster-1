# kohli-home-mono-repo

Mono repo for Samay's home Kubernetes infrastructure. Runs on a local k8s cluster and is managed via ArgoCD (GitOps).

## What lives here

| Folder | Purpose |
|--------|---------|
| `argocd/` | ArgoCD app-of-apps root application and child Application manifests |
| `apps/` | Custom application code (Temporal workers, API services) with colocated k8s manifests |
| `infra/` | Helm-managed shared infrastructure (Postgres, PgAdmin, Temporal server, etc.) |
| `infra/scripts/` | Cluster lifecycle scripts — create, start, stop, auto-start |

## How it works

1. **ArgoCD** watches this repo. The root app (`argocd/root-app.yaml`) manages all child apps under `argocd/apps/`.
2. **Custom apps** live in `apps/<app-name>/`. Each has its own `k8s/` folder with Kubernetes manifests and a `kustomization.yaml`. Adding a new app means: write the code, add k8s manifests, add an ArgoCD `Application` YAML in `argocd/apps/`.
3. **Shared infra** (databases, workflow engine, admin UIs) is deployed via Helm charts configured in `infra/`.

## Adding a new app

```bash
cp -r apps/_template apps/<your-app-name>
# Edit apps/<your-app-name>/k8s/deployment.yaml
# Add apps/<your-app-name>/argocd-app.yaml → copy to argocd/apps/
```

## Cluster

The cluster is a **k3d** (k3s-in-Docker) single-server cluster running on a Mac via OrbStack. It is long-running and survives Mac restarts.

- **Cluster name**: `local-cluster-1`
- **Persistent data**: `~/k3d-data/local-cluster-1/` — lives outside the repo; back this up
- **Datastore**: SQLite (default k3s — correct for a single-node personal cluster)
- **Auto-start**: launchd agent starts the cluster on login (see `infra/scripts/infra-setup/`)

### First-time setup

```bash
# 1. Create the cluster (run once)
./infra/scripts/infra-setup/create-cluster.sh

# 2. Install ArgoCD (run once)
./infra/scripts/infra-setup/argocd/install-argocd.sh

# 3. Create infra secrets — postgres, temporal, pgadmin (safe to re-run; skips existing)
./infra/scripts/infra-setup/setup-secrets.sh

# 4. Add ArgoCD repo credentials (interactive — prompts for GitHub App PEM)
./infra/scripts/infra-setup/argocd/setup-repo-secret.sh

# 5. Bootstrap ArgoCD self-management and root app
kubectl apply -f argocd/apps/argocd.yaml
kubectl apply -f argocd/root-app.yaml

# 6. Install the launchd auto-start agent (run once)
./infra/scripts/infra-setup/install-autostart.sh
```

### Port mappings

| Port | Service |
|------|---------|
| 80 / 443 | Traefik ingress |
| 5432 | PostgreSQL |
| 7233 | Temporal gRPC (frontend) |
| 8080 | Temporal Web UI |
| 8233 | Temporal membership/metrics |
| 5050 | PgAdmin |

> **Note:** Port mappings are fixed at cluster creation time. Add any new ports to `create-cluster.sh` before running it, or use `kubectl port-forward` for one-off access.

Local ingress hostnames configured in `/etc/hosts`:
`argocd.local`, `temporal.local`, `pgadmin.local`, `vault.local`
