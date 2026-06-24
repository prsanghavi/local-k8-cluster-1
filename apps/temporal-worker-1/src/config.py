"""Worker configuration — all values from environment variables with sane defaults."""
import os
from dataclasses import dataclass


@dataclass(frozen=True)
class Settings:
    temporal_host: str
    temporal_namespace: str
    task_queue: str


settings = Settings(
    temporal_host=os.getenv(
        "TEMPORAL_HOST",
        "temporal-frontend.temporal.svc.cluster.local:7233",
    ),
    temporal_namespace=os.getenv("TEMPORAL_NAMESPACE", "default"),
    task_queue=os.getenv("TEMPORAL_TASK_QUEUE", "main"),
)
