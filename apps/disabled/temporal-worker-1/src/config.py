"""Worker configuration — all values from environment variables with sane defaults."""
import os
from dataclasses import dataclass
from pathlib import Path


def _load_temporal_auth_token() -> str | None:
    token_file = os.getenv("TEMPORAL_AUTH_TOKEN_FILE")
    if token_file:
        token = Path(token_file).read_text(encoding="utf-8").strip()
        if token:
            return token

    token = os.getenv("TEMPORAL_AUTH_TOKEN", "").strip()
    return token or None


@dataclass(frozen=True)
class Settings:
    temporal_host: str
    temporal_namespace: str
    task_queue: str
    temporal_auth_token: str | None
    temporal_use_vault_auth: bool
    vault_addr: str
    vault_k8s_auth_path: str
    vault_k8s_role: str
    vault_jwt_sign_role: str
    vault_jwt_audience: str
    vault_jwt_subject: str


settings = Settings(
    temporal_host=os.getenv(
        "TEMPORAL_HOST",
        "temporal-frontend.temporal.svc.cluster.local:7233",
    ),
    temporal_namespace=os.getenv("TEMPORAL_NAMESPACE", "default"),
    task_queue=os.getenv("TEMPORAL_TASK_QUEUE", "main"),
    temporal_auth_token=_load_temporal_auth_token(),
    temporal_use_vault_auth=os.getenv("TEMPORAL_USE_VAULT_AUTH", "").lower()
    in {"1", "true", "yes"},
    vault_addr=os.getenv("VAULT_ADDR", "http://vault.vault.svc.cluster.local:8200"),
    vault_k8s_auth_path=os.getenv("VAULT_K8S_AUTH_PATH", "auth/kubernetes"),
    vault_k8s_role=os.getenv("VAULT_K8S_ROLE", "temporal-worker-1"),
    vault_jwt_sign_role=os.getenv("VAULT_JWT_SIGN_ROLE", "temporal-worker-1"),
    vault_jwt_audience=os.getenv("VAULT_JWT_AUDIENCE", "temporal"),
    vault_jwt_subject=os.getenv("VAULT_JWT_SUBJECT", "svc:temporal-worker-1"),
)
