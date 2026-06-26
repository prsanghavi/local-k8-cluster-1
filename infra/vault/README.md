# Vault JWT Engine

Local Vault for this repo runs in `dev` mode and auto-mounts the Outfoxx JWT
secrets engine at `jwt/`.

This document covers the manual steps to configure that engine so it can mint
JWTs for Temporal auth testing.

## Prerequisites

- Vault app is synced in ArgoCD
- `vault.local` resolves to `127.0.0.1`
- You can log into Vault with the local dev root token:

```bash
export VAULT_ADDR=http://vault.local
vault login root
```

If ingress is not working yet, port-forward instead:

```bash
kubectl -n vault port-forward svc/vault-ui 8200:8200
export VAULT_ADDR=http://127.0.0.1:8200
vault login root
```

## Confirm the JWT engine is mounted

The local values file auto-registers and mounts the Outfoxx JWT plugin at
`jwt/`.

Check it:

```bash
vault secrets list
vault path-help jwt
```

Expected output includes:

- mount path `jwt/`
- type `vault-plugin-secrets-jwt`
- supported paths like `config`, `jwks`, `roles/<name>`, and `sign/<name>`

## Configure the JWT engine

The JWT engine needs backend-wide defaults before it can sign Temporal-shaped
tokens.

Use the HTTP API here instead of `vault write`. For this plugin, list/map
fields like `allowed_claims` and `claims` were not serialized correctly by the
CLI during local testing.

Recommended local config:

```bash
curl -s \
  -H "X-Vault-Token: root" \
  -H "Content-Type: application/json" \
  -X POST \
  -d '{
    "issuer": "http://vault.local/v1/jwt",
    "sig_alg": "RS256",
    "rsa_key_bits": 2048,
    "key_ttl": "24h",
    "jwt_ttl": "1h",
    "set_iat": true,
    "set_jti": true,
    "set_nbf": true,
    "allowed_claims": ["sub", "aud", "permissions"],
    "audience_pattern": "^temporal$",
    "subject_pattern": "^(svc|user):.*$",
    "max_audiences": 1
  }' \
  http://vault.local/v1/jwt/config
```

What this does:

- `issuer`: sets the `iss` claim
- `sig_alg`: uses RSA signing so Vault can publish JWKS for Temporal
- `allowed_claims`: permits setting `sub`, `aud`, and `permissions`
- `audience_pattern`: restricts tokens to the `temporal` audience
- `subject_pattern`: restricts callers to `svc:*` and `user:*`

## Create a worker role

Create a reusable role for a Temporal worker:

```bash
curl -s \
  -H "X-Vault-Token: root" \
  -H "Content-Type: application/json" \
  -X POST \
  -d '{
    "issuer": "http://vault.local/v1/jwt",
    "allowed_claims": ["sub", "aud", "permissions"],
    "claims": {
      "permissions": ["default:worker", "default:read", "default:write"]
    }
  }' \
  http://vault.local/v1/jwt/roles/temporal-worker-1
```

This role defines the default `permissions` claim that Temporal will use for
authorization decisions.

Check the stored role:

```bash
vault read jwt/roles/temporal-worker-1
```

Expected output includes:

- `issuer = http://vault.local/v1/jwt`
- `claims = map[permissions:[default:worker default:read default:write]]`

## Mint a test token

Mint a JWT for the worker:

```bash
curl -s \
  -H "X-Vault-Token: root" \
  -H "Content-Type: application/json" \
  -X POST \
  -d '{"claims":{"sub":"svc:temporal-worker-1","aud":"temporal"}}' \
  http://vault.local/v1/jwt/sign/temporal-worker-1
```

The response should include a signed JWT in `data.token`.

## Decode the token locally

Inspect the claims:

```bash
TOKEN="<paste-data.token-here>"
export TOKEN

python3 - <<'PY'
import base64, json, os
parts = os.environ["TOKEN"].split(".")
payload = parts[1] + "=" * (-len(parts[1]) % 4)
print(json.dumps(json.loads(base64.urlsafe_b64decode(payload)), indent=2))
PY
```

Expected claims include:

- `iss`: `http://vault.local/v1/jwt`
- `sub`: `svc:temporal-worker-1`
- `aud`: `temporal`
- `permissions`: includes `default:worker`

## Check the JWKS endpoint

Temporal will need Vault's public keys to verify JWT signatures.

Check that Vault exposes them:

```bash
curl -s http://vault.local/v1/jwt/jwks
```

Expected output includes a `keys` array. One of the keys should have a `kid`
matching the JWT header.

Later, Temporal's `authorization.jwtKeyProvider` should trust this JWKS source.
From inside the cluster, Temporal should use the in-cluster Vault service URL,
not `vault.local`.

## Enable Vault Kubernetes auth for the worker

The Temporal worker does not use the Vault `root` token at runtime.
Instead, it:

1. reads its Kubernetes service account token
2. logs into Vault at `auth/kubernetes/login`
3. receives a short-lived Vault token
4. uses that Vault token to call `jwt/sign/temporal-worker-1`

### Enable the auth method

```bash
vault auth enable kubernetes
```

### Configure Kubernetes auth

Use the Vault pod's own service account token as the token reviewer JWT:

```bash
VAULT_POD=$(kubectl -n vault get pod -l app.kubernetes.io/name=vault,component=server -o jsonpath='{.items[0].metadata.name}')
TOKEN_REVIEW_JWT=$(kubectl -n vault exec "$VAULT_POD" -- cat /var/run/secrets/kubernetes.io/serviceaccount/token)
KUBE_CA_CERT=$(kubectl -n vault exec "$VAULT_POD" -- cat /var/run/secrets/kubernetes.io/serviceaccount/ca.crt)
vault write auth/kubernetes/config \
  kubernetes_host="https://kubernetes.default.svc.cluster.local" \
  token_reviewer_jwt="$TOKEN_REVIEW_JWT" \
  kubernetes_ca_cert="$KUBE_CA_CERT"
```

### Create a policy that can mint the Temporal worker JWT

```bash
printf 'path "jwt/sign/temporal-worker-1" {\n  capabilities = ["update"]\n}\n' | vault policy write temporal-worker-1 -
```

### Bind the worker service account to that policy

```bash
vault write auth/kubernetes/role/temporal-worker-1 \
  bound_service_account_names=temporal-worker-1 \
  bound_service_account_namespaces=temporal \
  policies=temporal-worker-1 \
  ttl=1h
```

Read the role back to verify it:

```bash
vault read auth/kubernetes/role/temporal-worker-1
```

Expected output includes:

- `bound_service_account_names = [temporal-worker-1]`
- `bound_service_account_namespaces = [temporal]`
- `policies = [temporal-worker-1]`

## Validate the end-to-end worker flow

After the worker image with Vault minting support is deployed, it should:

- log into Vault using service account `temporal-worker-1`
- mint a Temporal JWT from `jwt/sign/temporal-worker-1`
- connect successfully to Temporal without a manually supplied bearer token

If it fails before Temporal startup, check:

- `vault auth list`
- `vault read auth/kubernetes/config`
- `vault read auth/kubernetes/role/temporal-worker-1`

## Notes

- `jwt/` is a Vault secrets engine, not Vault's `auth/jwt` auth method.
- A greyed-out `jwt/` path in the Vault UI is normal for a custom secrets
  engine. Use CLI/API checks to validate it.
- The Vault CLI worked for simple scalar reads, but HTTP JSON writes were needed
  for this plugin's list/map fields.
- This local setup is intentionally insecure and disposable:
  - Vault runs in `dev` mode
  - root token is `root`
  - HTTP is used instead of TLS
