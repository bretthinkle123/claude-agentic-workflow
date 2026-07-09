# Plan — quota-active perf scenario (T6 slice)

## Scope

Add a **quota-active** k6 perf measurement for `POST /v1/events`: same distributed-key
ingest workload as the existing baseline, but with a high-but-finite quota pre-seeded per
customer bucket so the quota read-and-decide path runs on every request without rejecting.

## Files affected

- `tests/integration/k6/` — the quota-active scenario (the existing `load_events.js` is a
  parameterized shared harness; scenario differences ride `__ENV`).
- `tests/integration/test_perf_k6_load.py` — a quota fixture variant driving the harness.

## Test strategy

- The quota-active run records nearest-rank p95 over raw samples, same convention as the
  baseline test.

## Acceptance criteria

- AC1: quota-active p95 measured under the same constant-arrival workload as the baseline.
