# apps/

Custom application code. Each subdirectory is one deployable service with its source code and Kubernetes manifests colocated.

## Structure per app

```
apps/<app-name>/
├── README.md            ← What the app does, how to build/run it locally
├── AGENTS.md            ← AI agent context specific to this app
├── .claude/
│   └── skills/          ← App-specific Claude skills
├── k8s/
│   ├── deployment.yaml
│   ├── service.yaml
│   └── kustomization.yaml
└── src/                 ← Application source code
```

## Creating a new app

```bash
cp -r apps/_template apps/<your-app-name>
```

Then:
1. Edit `README.md` and `AGENTS.md` in the new folder
2. Update `k8s/deployment.yaml` with the correct image and config
3. Add `argocd/apps/<your-app-name>.yaml` pointing ArgoCD at `apps/<your-app-name>/k8s`

## Apps

| App | Description |
|-----|-------------|
| `_template` | Template — copy to create a new app |
