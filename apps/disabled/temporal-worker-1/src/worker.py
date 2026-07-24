"""
Entry point for temporal-worker-1.

To add a new workflow:   import it and append to WORKFLOWS list.
To add a new activity:   import it and append to ACTIVITIES list.
"""
import asyncio
import logging

from temporalio.client import Client
from temporalio.worker import Worker

from config import settings
from vault_auth import mint_temporal_jwt

# ── Workflows ──────────────────────────────────────────────────────────────────
from workflows.math_workflow import AddThenMultiplyWorkflow

WORKFLOWS = [
    AddThenMultiplyWorkflow,
    # add more workflow classes here
]

# ── Activities ─────────────────────────────────────────────────────────────────
from activities.math_activities import add, multiply

ACTIVITIES = [
    add,
    multiply,
    # add more activity functions here
]


async def _mint_temporal_jwt() -> tuple[str, int]:
    minted = await asyncio.to_thread(
        mint_temporal_jwt,
        vault_addr=settings.vault_addr,
        vault_k8s_auth_path=settings.vault_k8s_auth_path,
        vault_k8s_role=settings.vault_k8s_role,
        vault_jwt_sign_role=settings.vault_jwt_sign_role,
        vault_jwt_audience=settings.vault_jwt_audience,
        vault_jwt_subject=settings.vault_jwt_subject,
    )
    return minted.token, minted.refresh_after_seconds


async def _refresh_client_auth(client: Client) -> None:
    log = logging.getLogger(__name__)
    while True:
        try:
            token, refresh_after_seconds = await _mint_temporal_jwt()
            client.rpc_metadata = {"authorization": f"Bearer {token}"}
            log.info(
                "Refreshed Temporal auth token from Vault (next refresh in %ss)",
                refresh_after_seconds,
            )
            await asyncio.sleep(refresh_after_seconds)
        except asyncio.CancelledError:
            raise
        except Exception:
            log.exception("Failed to refresh Temporal auth token from Vault")
            await asyncio.sleep(30)


async def main() -> None:
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    )
    log = logging.getLogger(__name__)

    rpc_metadata = {}
    auth_mode = "disabled"
    if settings.temporal_auth_token:
        auth_mode = "static-token"
        rpc_metadata["authorization"] = f"Bearer {settings.temporal_auth_token}"
    elif settings.temporal_use_vault_auth:
        auth_mode = "vault-k8s"
        token, _ = await _mint_temporal_jwt()
        rpc_metadata["authorization"] = f"Bearer {token}"

    log.info(
        "Connecting to Temporal at %s (namespace=%s, task_queue=%s, auth=%s)",
        settings.temporal_host,
        settings.temporal_namespace,
        settings.task_queue,
        auth_mode,
    )

    client = await Client.connect(
        settings.temporal_host,
        namespace=settings.temporal_namespace,
        rpc_metadata=rpc_metadata,
    )

    refresh_task = None
    if settings.temporal_use_vault_auth and not settings.temporal_auth_token:
        refresh_task = asyncio.create_task(_refresh_client_auth(client))

    worker = Worker(
        client,
        task_queue=settings.task_queue,
        workflows=WORKFLOWS,
        activities=ACTIVITIES,
    )

    log.info("Worker started — listening on task queue '%s'", settings.task_queue)
    try:
        await worker.run()
    finally:
        if refresh_task:
            refresh_task.cancel()
            await asyncio.gather(refresh_task, return_exceptions=True)


if __name__ == "__main__":
    asyncio.run(main())
