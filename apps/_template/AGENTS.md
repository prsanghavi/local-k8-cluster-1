# AGENTS.md — <app-name>

App-specific context for AI agents. Supplements the root `AGENTS.md`.

## What this app does

> Replace with a concise description.

## Language / runtime

> e.g., Go 1.22, Python 3.12, Node 20

## Key files

| Path | Purpose |
|------|---------|
| `src/main.go` | Entry point |
| `k8s/deployment.yaml` | Kubernetes Deployment |
| `k8s/kustomization.yaml` | Kustomize root |

## App type

- [ ] Temporal worker — connects to Temporal server at `temporal.default.svc:7233`
- [ ] HTTP API service — exposes port `8080`
- [ ] Other: ___

## Important conventions for this app

- List any app-specific patterns, naming conventions, or gotchas here.

## What NOT to do

- Don't modify `k8s/` manifests without also updating the ArgoCD Application in `argocd/apps/`.
