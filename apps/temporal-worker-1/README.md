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
