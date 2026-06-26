# temporal-worker-1

Temporal worker for the home cluster. Listens on the `main` task queue in the `default` Temporal namespace.

## Workflows

| Workflow | Input | Output |
|----------|-------|--------|
| `AddThenMultiplyWorkflow` | `MathInput(a, b, c)` | `(a + b) * c` |

## Build & deploy

```bash
# From repo root
./apps/temporal-worker-1/scripts/build-push.sh

# Then commit and push — ArgoCD handles the rest
git add apps/temporal-worker-1/k8s/deployment.yaml
git commit -m "deploy: temporal-worker-1 $(git rev-parse --short HEAD)"
git push
```

## Local dev

```bash
cd apps/temporal-worker-1/src
pip install -e ..   # installs from pyproject.toml

# Point at a local Temporal (e.g. temporal server start-dev)
TEMPORAL_HOST=localhost:7233 python worker.py
```

When Temporal auth is enabled, you can still provide a bearer token manually with either:

```bash
TEMPORAL_AUTH_TOKEN="<jwt>" python worker.py
```

or:

```bash
TEMPORAL_AUTH_TOKEN_FILE=/path/to/token.txt python worker.py
```

## Vault minting via service account

In-cluster, the worker is configured to mint its own Temporal JWT from Vault by:

1. reading the pod's Kubernetes service account token
2. logging into Vault Kubernetes auth
3. calling `jwt/sign/<role>` to mint a Temporal JWT
4. refreshing that JWT before it expires

The deployment enables this with:

```bash
TEMPORAL_USE_VAULT_AUTH=true
VAULT_ADDR=http://vault.vault.svc.cluster.local:8200
VAULT_K8S_AUTH_PATH=auth/kubernetes
VAULT_K8S_ROLE=temporal-worker-1
VAULT_JWT_SIGN_ROLE=temporal-worker-1
```

Vault still needs a Kubernetes auth role and policy that allow the worker service
account to authenticate and call `jwt/sign/temporal-worker-1`. See
[`infra/vault/README.md`](/Users/pratiksanghavi/Desktop/experiments/local-k8-cluster-1/infra/vault/README.md:1)
for the Vault-side setup steps.

## Structure

```
temporal-worker-1/
├── Dockerfile
├── scripts/
│   └── build-push.sh       # build → tag (SHA + latest) → push → patch deployment.yaml
├── src/
│   ├── pyproject.toml
│   ├── config.py           # env-based settings
│   ├── worker.py           # entry point
│   ├── workflows/
│   │   └── math_workflow.py
│   └── activities/
│       └── math_activities.py
└── k8s/
    ├── deployment.yaml     # image tag patched by build-push.sh
    └── kustomization.yaml
```
