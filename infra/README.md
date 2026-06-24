# infra/

Helm-managed shared infrastructure and cluster lifecycle scripts.

## Contents

| Directory | Purpose |
|-----------|---------|
| `postgres/` | Helm values + ArgoCD app for PostgreSQL |
| `pgadmin/` | Helm values + ArgoCD app for PgAdmin |
| `temporal/` | Helm values + ArgoCD app for Temporal server + UI |
| `scripts/infra-setup/` | k3d cluster lifecycle scripts (create, start, stop, auto-start) |

## Services

| Service | Chart | Namespace |
|---------|-------|-----------|
| `postgres/` | bitnami/postgresql | `postgres` |
| `pgadmin/` | runix/pgadmin4 | `pgadmin` |
| `temporal/` | temporal/temporal | `temporal` |

## Structure per service

```
infra/<service>/
├── values.yaml          ← Helm values overrides
└── argocd-app.yaml      ← ArgoCD Application manifest (copy to argocd/apps/)
```

## Adding a new Helm-managed service

1. Create `infra/<service>/values.yaml` with your overrides
2. Copy `infra/<service>/argocd-app.yaml` to `argocd/apps/<service>.yaml`
3. Commit — ArgoCD picks it up automatically

## Cluster scripts (`scripts/infra-setup/`)

See `scripts/infra-setup/` for k3d cluster lifecycle management. Run `create-cluster.sh` once before deploying anything here. Persistent data lands in `~/k3d-data/home-1/` on the host.

## Secrets

Helm values files should NOT contain real secret values. Use Kubernetes `Secret` objects created manually on the cluster, then reference them via `existingSecret` fields in values (most Bitnami charts support this pattern).
