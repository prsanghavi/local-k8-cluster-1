"""Math workflow: (a + b) * c, using two chained activities."""
from dataclasses import dataclass
from datetime import timedelta

from temporalio import workflow

# Import activities inside sandbox-safe block
with workflow.unsafe.imports_passed_through():
    from activities.math_activities import add, multiply


@dataclass
class MathInput:
    a: float
    b: float
    c: float


@workflow.defn
class AddThenMultiplyWorkflow:
    """
    Workflow that:
      1. Runs the `add` activity  → result = a + b
      2. Runs the `multiply` activity → final = result * c
    """

    @workflow.run
    async def run(self, input: MathInput) -> float:
        sum_result: float = await workflow.execute_activity(
            add,
            args=[input.a, input.b],
            start_to_close_timeout=timedelta(seconds=30),
        )

        final_result: float = await workflow.execute_activity(
            multiply,
            args=[sum_result, input.c],
            start_to_close_timeout=timedelta(seconds=30),
        )

        return final_result
