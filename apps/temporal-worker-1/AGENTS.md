# AGENTS.md — temporal-worker-1

App-specific context for AI agents. Supplements the root `AGENTS.md`.

## What this app does

Temporal worker. Connects to the Temporal server in the `temporal` namespace and
processes workflows on the `main` task queue. Currently implements:

- **AddThenMultiplyWorkflow** — takes `(a, b, c)` floats, runs `add(a, b)` then
  `multiply(result, c)` via two activities, returns the final float.

## Language / runtime

Python 3.12, `temporalio` SDK (latest 1.x)

## Key files

| Path | Purpose |
|------|---------|
| `src/worker.py` | Entry point — registers all workflows + activities, starts the worker |
| `src/config.py` | Environment-based settings (host, namespace, task queue) |
| `src/workflows/` | One file per workflow |
| `src/activities/` | One file per activity group |
| `k8s/deployment.yaml` | Kubernetes Deployment (image tag is patched by build script) |
| `k8s/kustomization.yaml` | Kustomize root |
| `scripts/build-push.sh` | Build → push to `registry.local` → patch `deployment.yaml` |
| `Dockerfile` | Multi-stage Python 3.12-slim image |

## App type

- [x] Temporal worker — connects to `temporal-frontend.temporal.svc.cluster.local:7233`

## Adding a new workflow

1. Create `src/workflows/<name>_workflow.py` with a `@workflow.defn` class.
2. Import it in `src/worker.py` and append to `WORKFLOWS`.

## Adding a new activity

1. Create or add to a file in `src/activities/`.
2. Decorate each function with `@activity.defn`.
3. Import in `src/worker.py` and append to `ACTIVITIES`.

## Deploying

```bash
./apps/temporal-worker-1/scripts/build-push.sh
git add apps/temporal-worker-1/k8s/deployment.yaml
git commit -m "deploy: temporal-worker-1 <sha>"
git push
```

ArgoCD auto-syncs from `HEAD` — the updated `deployment.yaml` image tag triggers a rollout.

## Environment variables

| Variable | Default | Description |
|----------|---------|-------------|
| `TEMPORAL_HOST` | `temporal-frontend.temporal.svc.cluster.local:7233` | Temporal frontend gRPC address |
| `TEMPORAL_NAMESPACE` | `default` | Temporal namespace |
| `TEMPORAL_TASK_QUEUE` | `main` | Task queue this worker listens on |

## Important conventions

- Activities are async functions — keep them short and idempotent.
- Workflows must be deterministic — no `datetime.now()`, `random`, or direct I/O inside `@workflow.defn` methods.
- Use `workflow.unsafe.imports_passed_through()` when importing activity modules inside workflow files.

## What NOT to do

- Don't modify `k8s/deployment.yaml` image tag by hand — always use `build-push.sh`.
- Don't commit `.env` files or secret values.
- Don't put non-deterministic code inside workflow definitions.
