# infra/

Helm-managed shared infrastructure and cluster lifecycle scripts.

## Contents

| Directory | Purpose |
|-----------|---------|
| `postgres/` | Helm values + ArgoCD app for PostgreSQL |
| `pgadmin/` | Helm values + ArgoCD app for PgAdmin |
| `temporal/` | Helm values + ArgoCD app for Temporal server + UI |
| `vault/` | Helm values + ArgoCD app for local Vault + JWT plugin |
| `minio/` | Single-node MinIO manifests + persistent storage |
| `namespaces/` | GitOps-managed shared Kubernetes namespaces |
| `scripts/infra-setup/` | k3d cluster lifecycle scripts (create, start, stop, auto-start, secrets) |

## Services

| Service | Chart | Namespace |
|---------|-------|-----------|
| `postgres/` | bitnami/postgresql | `postgres` |
| `pgadmin/` | runix/pgadmin4 | `pgadmin` |
| `temporal/` | temporal/temporal | `temporal` |
| `vault/` | hashicorp/vault | `vault` |
| `minio/` | MinIO | `minio` |

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

See `scripts/infra-setup/` for k3d cluster lifecycle management. Run `create-cluster.sh` once before deploying anything here. Persistent data lands in `~/k3d-data/local-cluster-1/` on the host.

| Script | Purpose |
|--------|---------|
| `create-cluster.sh` | One-time cluster creation |
| `argocd/install-argocd.sh` | Install ArgoCD via Helm |
| `setup-secrets.sh` | Run all auto secret scripts (postgres, temporal, pgadmin) |
| `argocd/setup-repo-secret.sh` | Interactive — ArgoCD GitHub App credentials |
| `start-cluster.sh` / `stop-cluster.sh` | Start or stop the cluster |

## Secrets

Helm values files should NOT contain real secret values. Use Kubernetes `Secret` objects created on the cluster, then reference them via `existingSecret` fields in values.

**Before syncing postgres, temporal, or pgadmin**, run:

```bash
./infra/scripts/infra-setup/setup-secrets.sh
```

This runs the scripts in `secrets-auto-setup-scripts/` in order. Each script auto-generates passwords and **skips secrets that already exist** (delete a secret first if you need to rotate it).

Individual scripts (same skip-if-exists behaviour):

| Script | Secret | Namespace(s) |
|--------|--------|--------------|
| `secrets-auto-setup-scripts/setup-postgres-secret.sh` | `postgres-credentials` | `postgres` |
| `secrets-auto-setup-scripts/setup-temporal-secret.sh` | `temporal-db-credentials` | `postgres`, `temporal` |
| `secrets-auto-setup-scripts/setup-pgadmin-secret.sh` | `pgadmin-credentials` | `pgadmin` |
| `secrets-auto-setup-scripts/setup-minio-secret.sh` | `minio-credentials` | `minio` |

Retrieve passwords:

```bash
kubectl get secret postgres-credentials    -n postgres -o jsonpath='{.data.password}' | base64 -d && echo
kubectl get secret temporal-db-credentials -n temporal -o jsonpath='{.data.password}' | base64 -d && echo
kubectl get secret pgadmin-credentials     -n pgadmin  -o jsonpath='{.data.password}' | base64 -d && echo
kubectl get secret minio-credentials       -n minio    -o jsonpath='{.data.root-user}' | base64 -d && echo
kubectl get secret minio-credentials       -n minio    -o jsonpath='{.data.root-password}' | base64 -d && echo
```
