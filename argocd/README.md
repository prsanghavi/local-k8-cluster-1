# argocd/

ArgoCD configuration for the home cluster, using the **app-of-apps** pattern.

## How it works

```
root-app.yaml
    └── watches argocd/apps/
            ├── postgres.yaml
            ├── temporal-worker-foo.yaml
            └── ...
```

`root-app.yaml` is the single Application you bootstrap manually (once). After that, every file dropped into `argocd/apps/` is automatically picked up and synced by ArgoCD.

## Bootstrap (first time only)

```bash
kubectl apply -f argocd/root-app.yaml
```

## Adding a service

Create a new `Application` manifest in `argocd/apps/<service-name>.yaml`. Use the existing files as a template. ArgoCD will detect it on the next sync.

## Folder structure

```
argocd/
├── root-app.yaml        ← Bootstrap this once; manages everything in apps/
└── apps/                ← One Application YAML per service
```
