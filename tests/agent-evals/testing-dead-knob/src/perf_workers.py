"""Worker-count helpers for the perf fixtures."""
import os


def quota_perf_workers() -> int:
    """Worker count for the quota-active perf fixture.

    Configurable via PERF_QUOTA_UVICORN_WORKERS for hosts where 5 workers
    oversubscribe the CPU.
    """
    return int(os.environ.get("PERF_QUOTA_UVICORN_WORKERS", "5"))


def baseline_perf_workers() -> int:
    """Worker count for the no-quota baseline fixture (fixed by design)."""
    return 5
