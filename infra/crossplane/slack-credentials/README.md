# Slack provider credentials

The Slack bot token is stored only in Vault at KV v2 path `v1/slack`, key
`slack_operator`. Vault Secrets Operator copies it to the generated Kubernetes
Secret `crossplane-system/slack-creds`, which the Slack `ProviderConfig` reads.

Before Argo CD can sync the `VaultStaticSecret`, configure the least-privilege
Vault policy and Kubernetes auth role. Run this locally with an authenticated
Vault CLI; do not save or export the root token in this repository.

```bash
cat <<'EOF' | vault policy write crossplane-slack -
path "v1/slack" {
  capabilities = ["read"]
}
EOF

vault write auth/kubernetes/role/crossplane-slack \
  bound_service_account_names=slack-vault-auth \
  bound_service_account_namespaces=crossplane-system \
  policies=crossplane-slack \
  audience=vault \
  ttl=1h
```

The repository's Vault runbook documents the one-time Kubernetes auth setup.
Afterward, verify the sync without revealing data:

```bash
kubectl -n crossplane-system get vaultstaticsecret slack-operator-token
kubectl -n crossplane-system get secret slack-creds
```
