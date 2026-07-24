# MinIO

Single-node, S3-compatible object storage for the local k3d cluster.

- Console: `http://minio.local`
- S3 API: `http://s3.local`
- Storage: 10 GiB `local-path` PVC
- Bootstrap bucket: `temporal-worker-payloads`

The bootstrap Job only ensures the bucket exists. Configure an external payload
converter/data codec in a Temporal worker before expecting workflow payloads to
be stored in this S3 bucket.

## First-time credentials setup

Before ArgoCD syncs this application, create the credentials secret:

```bash
./infra/scripts/infra-setup/secrets-auto-setup-scripts/setup-minio-secret.sh
```

The script creates `minio/minio-credentials` with generated root credentials and
is safe to rerun. To rotate credentials, delete that secret and rerun the script.

Add these hostnames to `/etc/hosts` if they are not already present:

```text
127.0.0.1 minio.local s3.local
```

Retrieve the generated credentials with:

```bash
kubectl get secret minio-credentials -n minio -o jsonpath='{.data.root-user}' | base64 -d && echo
kubectl get secret minio-credentials -n minio -o jsonpath='{.data.root-password}' | base64 -d && echo
```
