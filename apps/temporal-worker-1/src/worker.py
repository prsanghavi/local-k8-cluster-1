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


async def main() -> None:
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    )
    log = logging.getLogger(__name__)

    log.info(
        "Connecting to Temporal at %s (namespace=%s, task_queue=%s)",
        settings.temporal_host,
        settings.temporal_namespace,
        settings.task_queue,
    )

    client = await Client.connect(
        settings.temporal_host,
        namespace=settings.temporal_namespace,
    )

    worker = Worker(
        client,
        task_queue=settings.task_queue,
        workflows=WORKFLOWS,
        activities=ACTIVITIES,
    )

    log.info("Worker started — listening on task queue '%s'", settings.task_queue)
    await worker.run()


if __name__ == "__main__":
    asyncio.run(main())
