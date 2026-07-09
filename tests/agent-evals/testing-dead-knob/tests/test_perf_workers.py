from src.perf_workers import baseline_perf_workers, quota_perf_workers


def test_worker_budgets_match():
    # AC: quota-active and baseline perf runs must use an equal worker budget.
    assert quota_perf_workers() == baseline_perf_workers() == 5
