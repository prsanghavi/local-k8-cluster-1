# <app-name>

> Replace this with a one-line description of what this app does.

## Overview

What problem does this solve? What does it connect to?

## Local development

```bash
# How to run locally
```

## Building & deploying

```bash
# How to build the Docker image
docker build -t <app-name>:<tag> .

# Load into local k8s cluster (if using kind or k3s)
# kind: kind load docker-image <app-name>:<tag>
# k3s: k3s ctr images import ...
```

Deployment is handled by ArgoCD — commit changes and ArgoCD syncs automatically.

## Kubernetes resources

All manifests are in `k8s/`. Applied via Kustomize.

| Resource | Purpose |
|----------|---------|
| `deployment.yaml` | App workload |
| `service.yaml` | Internal k8s service |

## Configuration / Secrets

| Key | Description | How to set |
|-----|-------------|-----------|
| `EXAMPLE_SECRET` | Example secret | Create a k8s Secret manually |

> Do NOT commit real secret values. Use placeholder comments in manifests.

## Dependencies

- List external services this app talks to (e.g., Temporal, Postgres)
