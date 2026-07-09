# Debug notes

## 2026-07-08 — U-03 advisory: pin engine isolation to READ COMMITTED (remediation)

**Finding (PLAUSIBLE, latent fragility — not a live bug).** Advisory
correctness-review finding U-03. `quotas_repo.read_tenant_quota_state_locked`
enforces the quota cap by locking the `quotas` row (`SELECT ... FOR UPDATE`) and
then reading `usage_rollup.total_quantity` in a SEPARATE plain statement. That
pattern is only correct under READ COMMITTED, where the post-lock statement gets
a fresh snapshot that sees the previous lock holder's committed increment.
`src/db/session.py:31` created the engine with no `isolation_level`, silently
relying on the PostgreSQL/role default. If that default were ever changed to
REPEATABLE READ, lock-waiters would read the stale pre-wait rollup total and
admit events past the cap — with no test signal.

**Root cause.** The correctness of the lock-then-read is an implicit dependency
on READ COMMITTED that was never pinned or asserted anywhere. Not a present
defect (Postgres defaults to READ COMMITTED, so behavior is currently correct);
the risk is the unguarded implicit reliance.

**Evidence.** Reproduced the unpinned state through the real production path:
`get_engine().sync_engine.dialect._on_connect_isolation_level` was `None`
(engine inherits the DB/role default). New regression test failed against the
unpinned engine: `assert None == 'READ COMMITTED'`.

**Fix (minimal, localized).** Added `isolation_level="READ COMMITTED"` to
`create_async_engine(...)` in `src/db/session.py`, with a comment explaining the
quota lock-then-read dependency and referencing the
`read_tenant_quota_state_locked` docstring. Pinning at the engine forces the
level per connection, so it holds even if a future DB/role default differs.

**Proof.** Authored `tests/test_db_session_isolation.py::`
`test_engine_pins_read_committed_isolation` (mirrors the pin-guard shape of
`tests/test_dependency_pins.py`): asserts the process-wide engine is pinned to
READ COMMITTED. Failed before the fix (`None`), passes after. Ran it 8x —
deterministic all-pass (config assertion, no flakiness surface). Confirmed no
regression: the three quota test files
(`tests/integration/test_quota_concurrency.py`,
`test_events_quota_enforcement.py`, `test_quotas_endpoint.py`) = 19 passed,
including the concurrency strict-enforcement guard; `import src.main` smoke
import OK.

**Dead ends / notes.** `isolation_level` does not surface via
`engine.get_execution_options()` (empty); it is recorded on
`dialect._on_connect_isolation_level` at construction — a private attribute, but
the only no-DB-connection accessor, so the test asserts on it with an
explanatory message for diagnosability. No temporary debug probes left in the
tree; the only changes are the one-line-plus-comment fix and the regression test.

## 2026-07-08 — AC20 perf: quota-active POST /v1/events p95 ≫ 50 ms budget (remediation)

**Finding (from the testing gate).** AC20's k6 quota scenario measured p95
**3362 ms** (budget 50 ms), only **347 rps** of a 500 rps constant-arrival
target, 5493 samples all 201. The no-quota baseline on the same host/session was
p95 **83.55 ms**. The finding hypothesised a real regression in the quota
`FOR UPDATE` read-and-decide path (~40× worse than baseline).

**Reproduced first.** Ran the exact failing test
(`test_events_ingest_with_quotas_p95_under_50ms`, unchanged code): **p95
3519.29 ms, 345 rps, all 201** — matches the reported failure.

**Root cause (empirically isolated — NOT the quota code path).** The AC20 perf
fixture `k6_quota_load_env` launched uvicorn with only **2 worker processes**
(`METERLY_PERF_QUOTA_UVICORN_WORKERS` default `"2"`), whereas the no-quota
baseline it is compared against (`k6_load_env`) uses **5**. Two worker processes
cannot service 500 rps of this workload's per-request CPU (routing, Pydantic,
two Redis throttle checks, SQLAlchemy over ~6–7 round-trips, structlog) on the
Docker-Desktop/Windows host, so under the constant-arrival-rate scenario the
excess arrivals **queue** and the tail inflates into the seconds. The ~40× gap
was a measurement handicap, not a code regression. Evidence:

| Experiment (15 s @ 500 rps target) | p95 | rps | verdict |
|---|---|---|---|
| A. no-quota baseline, **5 workers** | 84.54 ms | 497 | target met (host floor) |
| B. quota path, **5 workers** | 87.68 ms | 495 | ≈ baseline; +~3 ms for the quota check |
| (repro) quota path, **2 workers** | 3519 ms | 345 | **saturated → queueing** |
| C. quota path, **2 workers + big pool** (50 conns/worker, 100 total) | 4356 ms | 306 | still saturated — pool is NOT the ceiling |

Experiment C is decisive: raising the DB connection pool at 2 workers did **not**
help (it was marginally worse), so the ceiling is **worker-process count**, not
pooled-connection starvation and not the `FOR UPDATE` lock. Given an equal
worker budget (B vs A) the quota check adds only ~3 ms p95 — the strict-
enforcement two-statement lock-then-read is not a perf problem.

**Fix (minimal, localized to the harness — no production code changed).**
`tests/integration/test_perf_k6_load.py`: the quota fixture now derives its
worker count from `_quota_perf_workers()`, which **defaults to the baseline
worker count (5)** instead of a hardcoded 2, so AC20 is an apples-to-apples
measurement under the same CPU budget as the baseline it is compared against.
The old 2-worker default was justified by a `max_connections` concern that no
longer applies: the shared Postgres testcontainer runs `max_connections=300`
(conftest) and the perf fixtures are function-scoped/torn down sequentially, so
5 workers × 15 pooled conns = 75 is well within budget. The strict-enforcement
invariant (usage ≤ L) is untouched — no `quotas_repo`/`events_service`/engine
change. A pool-tunability experiment in `src/db/session.py` was **fully reverted**
(experiment C proved it irrelevant); net change there is zero.

**Proof.** After fix, clean env (fixture default now 5): **p95 112.42 ms, 497 rps,
all 201** — target throughput met, p95 in the same ~85–112 ms band as the no-quota
baseline (run-to-run host tail jitter), vs the 3519 ms saturated repro. Regression
guard `test_ac20_quota_perf_fixture_matches_baseline_worker_budget` (fast, Docker-
free) asserts the quota fixture's worker budget is never below the baseline's;
**fails-before** demonstrated in a scratch copy against the old default (`2 >= 5`
→ AssertionError), **passes-after** (`5 >= 5`). This is a perf measurement under
real k6 load, not a flaky unit test; the throughput target (497/500 rps, no
saturation) is the stability signal, and it held across all three 5-worker runs.

**Escalation (human decision — I did NOT reinterpret AC20).** Even after the
fix the literal **p95 < 50 ms budget is still not met (~87–112 ms)** — but so is
the **no-quota baseline (~84 ms)**. The 50 ms floor is unachievable on this
Docker-Desktop/Windows host regardless of code: `host.docker.internal` +
Windows networking imposes an irreducible per-request overhead (the exact
pre-existing deferred finding from feature 1). The quota path does NOT blow the
*existing* budget relative to baseline (AC20's stated intent, plan §"the
quota-check path does not blow the existing budget"). Whether AC20's absolute
50 ms threshold should stand on this host, be re-measured on production-class
infra (ECS→RDS same-AZ round-trips are ~1 ms, not Docker-Desktop's tens of ms),
or be adjusted — is a budget decision that escalates to the human. Left the AC20
test asserting `sample_count > 0` (honest measurement) rather than hardcoding a
50 ms assertion that would fail forever on this host.

**Dead ends / notes.** (1) Bigger DB pool at 2 workers — no help (exp C).
(2) Considered a single-statement combined check-and-increment to cut round-trips,
but rejected: the plan explicitly rejects the guarded-upsert approach, the
two-statement lock-then-read is load-bearing for strict enforcement (debug-notes
U-03 above), and the data shows the quota path is not the bottleneck anyway — it
would have been a needless redesign. No debug probes left in the tree; the only
tracked change is `tests/integration/test_perf_k6_load.py`.
