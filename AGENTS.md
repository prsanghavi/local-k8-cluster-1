# AGENTS.md — Repo Context for AI Agents

This file gives AI coding assistants the context they need to work effectively in this repo.

## What this repo is

Home Kubernetes infrastructure mono repo. Everything here deploys to a **local k3d cluster** via **ArgoCD (GitOps)**. There is no CI/CD pipeline that pushes to the cluster — ArgoCD pulls from this repo.

Owner: Samay (ksamay@budy.bot)

## Repo layout

```
kohli-home-mono-repo-1/
├── AGENTS.md              ← you are here
├── README.md
├── argocd/
│   ├── root-app.yaml      ← ArgoCD app-of-apps root; targets argocd/apps/
│   └── apps/              ← one ArgoCD Application manifest per deployed service
├── apps/
│   ├── _template/         ← copy this to create a new app
│   └── <app-name>/        ← each app: src code + colocated k8s/ manifests
└── infra/                 ← Helm values files for shared infrastructure
    ├── postgres/
    ├── pgadmin/
    ├── temporal/
    └── scripts/
        └── infra-setup/   ← cluster lifecycle + secret setup scripts
```

## Key conventions

- **GitOps only**: never apply manifests with `kubectl apply` directly — commit to this repo and let ArgoCD sync.
- **Kustomize** is the preferred manifest tool for custom apps. Each `apps/<name>/k8s/` has a `kustomization.yaml`.
- **Helm** is used for third-party infra (Postgres, PgAdmin, Temporal server). Helm config lives in `infra/`.
- **App-of-apps**: `argocd/root-app.yaml` is the single entry point. Adding a service means adding an `Application` YAML to `argocd/apps/`.
- **Per-folder skills**: each app folder may have its own `.claude/skills/` for app-specific AI workflows.

## Cluster

- **Type**: k3d (k3s in Docker), running on Mac via OrbStack
- **Cluster name**: `local-cluster-1` — kubectl context is `k3d-local-cluster-1`
- **Nodes**: 1 server, SQLite datastore (correct for single-node personal use — do not change to etcd)
- **Persistent data**: stored at `~/k3d-data/local-cluster-1/` on the host, outside this repo
- **Auto-start**: launchd agent (`com.samay.k3d-home`) starts the cluster on login

### Cluster management scripts (`infra/scripts/infra-setup/`)

| Script | Purpose |
|--------|---------|
| `create-cluster.sh` | One-time cluster creation with volume mounts and port mappings |
| `install-argocd.sh` | Install ArgoCD via Helm (`argocd/install-argocd.sh`) |
| `setup-secrets.sh` | Run all auto secret scripts (postgres, temporal, pgadmin); skips existing secrets |
| `setup-repo-secret.sh` | Interactive — ArgoCD GitHub App repo credentials (`argocd/setup-repo-secret.sh`) |
| `start-cluster.sh` | Start an existing stopped cluster |
| `stop-cluster.sh` | Stop the cluster (data is preserved) |
| `auto-start.sh` | Called by launchd on login; waits for Docker then starts cluster |
| `install-autostart.sh` | Installs the launchd plist to `~/Library/LaunchAgents/` |

Auto secret scripts live in `infra/scripts/infra-setup/secrets-auto-setup-scripts/`. Add new ones to the `AUTO_SECRET_SCRIPTS` list in `setup-secrets.sh`.

### Port mappings (fixed at cluster creation)

Two mapping strategies are in use:

| Port | Strategy | Service |
|------|----------|---------|
| 80 / 443 | `@loadbalancer` | Traefik ingress (Temporal UI at `temporal.local`, PgAdmin at `pgadmin.local`) |
| 30000–32767 | `@server:0` | Full Kubernetes NodePort range |

**NodePort assignments** (memorable numbers within the range):

| Host port | NodePort | Service |
|-----------|----------|---------|
| 30432 | 30432 | PostgreSQL primary (`postgres-cluster-1-nodeport` Service) |
| 30233 | 30233 | Temporal gRPC frontend |

Port mappings cannot be added after cluster creation. Use `kubectl port-forward` for ad-hoc access to unlisted ports.

> **Note**: Exposing the full NodePort range causes Docker to create ~2768 proxy processes at cluster creation time — startup takes longer than usual. This is expected and acceptable for a local dev cluster.

## Deployed infrastructure (via Helm, in infra/)

- **PostgreSQL** — primary database
- **PgAdmin** — Postgres admin UI
- **Temporal** — workflow orchestration engine (server + UI)

## Custom apps (in apps/)

- **Temporal workers** — Go or Python workers connecting to the Temporal server
- **Custom API services** — any bespoke HTTP backends

## When creating or editing Kubernetes manifests

- Target namespace is usually the app name or `default` — check existing manifests for the pattern.
- Image pull policy for local dev: `IfNotPresent` (images built and loaded into cluster directly).
- Resource requests/limits: keep them conservative for a home cluster.
- Secrets: use Kubernetes `Secret` objects; do NOT commit plaintext secret values — use placeholders and note them in the app's README.

## When creating a new app

1. Copy `apps/_template/` to `apps/<new-app-name>/`
2. Update `apps/<new-app-name>/README.md` and `AGENTS.md`
3. Edit manifests in `apps/<new-app-name>/k8s/`
4. Copy `apps/_template/argocd-app.yaml` to `argocd/apps/<new-app-name>.yaml` and update it
5. Commit — ArgoCD will pick it up

## What NOT to do

- Don't run `helm install` or `kubectl apply` directly — use GitOps.
- Don't commit `.env` files or raw secret values.
- Don't add a global `node_modules/`, `__pycache__/`, or build artifacts — each app manages its own ignores.
