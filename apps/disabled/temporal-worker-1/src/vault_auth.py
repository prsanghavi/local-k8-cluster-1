"""Helpers for minting Temporal JWTs from Vault using Kubernetes auth."""
import json
import urllib.request
from dataclasses import dataclass
from pathlib import Path


SERVICE_ACCOUNT_TOKEN_FILE = "/var/run/secrets/kubernetes.io/serviceaccount/token"


@dataclass(frozen=True)
class MintedToken:
    token: str
    refresh_after_seconds: int


def _post_json(url: str, payload: dict, token: str | None = None) -> dict:
    request = urllib.request.Request(
        url,
        data=json.dumps(payload).encode("utf-8"),
        headers={
            "Content-Type": "application/json",
            **({"X-Vault-Token": token} if token else {}),
        },
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=15) as response:
        return json.loads(response.read().decode("utf-8"))


def mint_temporal_jwt(
    *,
    vault_addr: str,
    vault_k8s_auth_path: str,
    vault_k8s_role: str,
    vault_jwt_sign_role: str,
    vault_jwt_audience: str,
    vault_jwt_subject: str,
    service_account_token_file: str = SERVICE_ACCOUNT_TOKEN_FILE,
) -> MintedToken:
    service_account_jwt = Path(service_account_token_file).read_text(
        encoding="utf-8"
    ).strip()

    auth_response = _post_json(
        f"{vault_addr}/v1/{vault_k8s_auth_path}/login",
        {"role": vault_k8s_role, "jwt": service_account_jwt},
    )
    vault_token = auth_response["auth"]["client_token"]

    sign_response = _post_json(
        f"{vault_addr}/v1/jwt/sign/{vault_jwt_sign_role}",
        {"claims": {"sub": vault_jwt_subject, "aud": vault_jwt_audience}},
        token=vault_token,
    )

    jwt_token = sign_response["data"]["token"]
    lease_duration = int(sign_response.get("lease_duration") or 3600)
    refresh_after = max(60, int(lease_duration * 0.8))
    return MintedToken(token=jwt_token, refresh_after_seconds=refresh_after)
