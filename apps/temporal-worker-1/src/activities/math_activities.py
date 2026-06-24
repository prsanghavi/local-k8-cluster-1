"""Math activities — each function is a single Temporal activity."""
import logging
from temporalio import activity

logger = logging.getLogger(__name__)


@activity.defn
async def add(a: float, b: float) -> float:
    """Return a + b."""
    result = a + b
    logger.info("add(%s, %s) = %s", a, b, result)
    return result


@activity.defn
async def multiply(value: float, factor: float) -> float:
    """Return value * factor."""
    result = value * factor
    logger.info("multiply(%s, %s) = %s", value, factor, result)
    return result
