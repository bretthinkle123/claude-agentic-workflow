"""Dashboard BFF service. The REAL function names + signatures live here; the README the
documentation agent is asked to update must match THESE, not invented ones."""


async def get_usage_series(*, customer_id: str, metric: str, granularity: str) -> dict:
    """Assemble the usage series for one customer/metric/granularity selection."""
    return {}


def floor_to_hour_utc(ts):
    """Floor a timezone-aware timestamp to the hour (UTC)."""
    return ts
