# Implementation progress — per-customer metric quotas

Following `.pipeline/tasks.md` (T1..T6), test-first per task. This file is
gitignored working state; terse notes only.

## T1 — migration 0003 (quotas table + api_keys.scope)
- T1 done: tests written+red -> code -> green.
  Files: tests/integration/test_quota_migration.py,
  alembic/versions/0003_create_quotas_and_api_key_scope.py.

## T2 — scope plumbing (api_keys_repo, AuthenticatedPrincipal, seed_api_key --admin)
- T2 done: tests written+red -> code -> green.
  Files: src/repositories/api_keys_repo.py (ApiKeyRecord.scope, create_api_key(scope=)),
  src/auth/api_key.py (AuthenticatedPrincipal.scope default "ingest", populated in verify_api_key),
  scripts/seed_api_key.py (--admin flag), tests/integration/test_seed_api_key_script.py::test_admin_flag_sets_scope.
  Verified existing tests/test_auth_api_key.py, test_events_endpoint.py, test_rate_limit.py,
  test_concurrency.py still green after the AuthenticatedPrincipal/ApiKeyRecord field additions.
  Next: T3 (schemas/quotas.py, quotas_repo.upsert_quota, quota_service, routes/quotas.py, errors.AppError, CORS PUT, mount router).

## T3 — PUT /v1/quotas (upsert, admin scope, validation, error code, mount)
- T3 done: tests written+red -> code -> green.
  Files: tests/test_schemas_quotas.py, tests/integration/test_quotas_endpoint.py,
  src/api/schemas/quotas.py (QuotaPutRequest/QuotaResponse),
  src/repositories/quotas_repo.py (upsert_quota xmax idiom + read_tenant_quota_state_locked
  written now, consumed by T4), src/services/quota_service.py (upsert_tenant_quota,
  quota.upsert log, 201/200 mapping), src/api/routes/quotas.py (admin-scope gate,
  quota.forbidden log), src/api/errors.py (AppError + app_code honored in
  handle_http_exception), src/api/middleware.py (CORS allow_methods += PUT),
  src/main.py (mount quotas_router). Also extended test infra:
  tests/integration/conftest.py (make_api_key scope= param; truncate_tables
  includes quotas).
  Full suite green: 112 passed (tests/ minus k6 perf + unrelated dashboard tests).
  Next: T4 (read_tenant_quota_state_locked wiring into events_service quota
  check on the winning-insert branch; quota.rejected log;
  tests/integration/test_events_quota_enforcement.py).

## T4 — POST /v1/events quota enforcement (FOR UPDATE read-and-decide)
- T4 done: tests written+red -> code -> green.
  Files: tests/integration/test_events_quota_enforcement.py,
  src/services/events_service.py (QuotaExceededError(AppError), quota check
  on the winning-insert branch using read_tenant_quota_state_locked, rollback
  on reject via raise-inside-transaction, quota.rejected log without totals,
  _seconds_until_next_hour_boundary for Retry-After).
  Full suite green: 120 passed (tests/ minus k6 perf + unrelated dashboard tests).
  Next: T5 (test_quota_concurrency.py -- N concurrent distinct-key posts never
  exceed L) and T6 (perf k6 quota scenario + DAST/docs) -- parallel-safe per
  tasks.md, doing T5 first then T6.

## T5 — concurrency correctness (AC13)
- T5 done, but surfaced and fixed a real correctness bug in T4's
  `read_tenant_quota_state_locked` in the process (debugged empirically with
  scratch scripts, since removed): a single combined
  `SELECT ... LEFT JOIN usage_rollup ... FOR UPDATE OF q` does NOT give every
  concurrent waiter a fresh read of the joined `usage_rollup` row --
  PostgreSQL's `FOR UPDATE` only forces a fresh re-check (EvalPlanQual) of the
  LOCKED row itself; a joined, non-locked table is still read from the
  waiter's original (pre-wait) statement snapshot. Verified empirically: 20
  concurrent posts against a cap of 10 all read the same stale total and all
  got admitted (20/20 201s) -- the bug was invisible to the sequential T4
  tests (which never contend on the lock) and only showed up under real
  concurrency.
  FIX: split into two round-trips in the same transaction -- (1) lock the
  quotas row alone (`SELECT limit_per_window ... FOR UPDATE`, no join), then
  (2) a separate plain `SELECT total_quantity FROM usage_rollup ...` issued
  AFTER the lock is held, which gets its own fresh READ COMMITTED snapshot
  reflecting everything the previous lock holder just committed. Re-verified
  with the same empirical scripts: current_total now increases correctly
  across serialized waiters (0, 1, 2, ... capped at L) instead of staying
  stuck at 1 for every waiter.
  Files: tests/integration/test_quota_concurrency.py (new),
  src/repositories/quotas_repo.py (read_tenant_quota_state_locked rewritten
  as two statements; docstring documents the EvalPlanQual/snapshot subtlety
  and why a combined single-statement version is unsafe).
  Verified: test_quota_concurrency.py green across 3 repeated runs; full
  suite green (121 passed, tests/ minus k6 perf + unrelated dashboard tests)
  after the repo rewrite -- no regression to the T3/T4 sequential-path tests.
  Next: T6 (k6 quota-active perf scenario, DAST context, docs/READMEs/CLAUDE.md).

## T6 — perf (quota-active), DAST context, docs (final task)
- T6 done. Files: tests/integration/k6/load_events_quota.js (new k6 script,
  same distributed-key ingest pattern as load_events.js), a new
  `k6_quota_load_env` fixture + `test_events_ingest_with_quotas_p95_under_50ms`
  in tests/integration/test_perf_k6_load.py (admin-scoped key, 50 customer
  buckets pre-seeded with a high-but-finite quota so the FOR UPDATE
  read-and-decide runs on every request without ever rejecting; records true
  nearest-rank p95, same honest-measurement convention as the existing
  baseline perf test -- asserts sample_count>0, not a hard budget gate).
  DAST context (AC21): tests/test_dast_context_documented.py already passes
  unchanged (mtr_live/Bearer already documented in plan.md); docs/system_architecture.md
  now also documents the admin test-key requirement.
  Docs: docs/system_architecture.md (quotas surface, PUT /v1/quotas flow,
  data model + RLS, a full "Quota enforcement / atomicity" section
  explaining the two-statement lock-then-read design and the empirical bug
  it fixes), src/api/README.md, src/services/README.md,
  src/repositories/README.md, src/auth/README.md, CLAUDE.md (admin scope +
  PUT /v1/quotas noted in the Auth line).

  ENVIRONMENT ISSUE FOUND AND FIXED (test infra only, not a feature bug):
  running the FULL test suite (`pytest tests/ -k "not dashboard"`, ~140
  tests) in one session intermittently threw `asyncpg.exceptions.
  TooManyConnectionsError` across MANY unrelated tests once the 3rd
  multi-worker-uvicorn k6 perf fixture was added in this task -- diagnosed by
  bisecting with `git stash`: the pre-existing 2 perf fixtures alone (before
  this feature) did not exhibit it, and my new fixture alone (paired with a
  couple of other test files) did not exhibit it either; it only appeared
  with all ~140 tests plus all 3 heavy multi-worker-uvicorn+DB-pool fixtures
  in one shared-session Postgres testcontainer, whose default
  `max_connections=100` is too low for that cumulative demand.
  FIX (test-container capacity only, no production change): raised the
  shared `postgres_url` testcontainer's `max_connections` to 300 via
  `PostgresContainer(...).with_command("postgres -c max_connections=300")`
  in tests/integration/conftest.py; also gave the new k6_quota_load_env
  fixture its own smaller default worker count (2, via
  METERLY_PERF_QUOTA_UVICORN_WORKERS, not the shared
  METERLY_PERF_UVICORN_WORKERS=5 knob) and a 1s post-teardown grace sleep,
  to reduce peak connection footprint further.
  VERIFIED: full suite green three times after the fix -- 121 passed (before
  adding the k6 quota perf test), then 124 passed (`pytest tests/ -k "not
  dashboard"`, ~141s), confirming no lingering flakiness.

## Final state
- All T1-T6 tasks complete. AC1-AC21 built and covered by tests (AC22 is
  delegated to the security stage per acceptance.md, as planned). Full test
  suite green (124 passed, tests/ minus unrelated dashboard-feature tests
  from a different branch's leftover working-tree files).
- Self-check complete: `git diff HEAD --name-only` + untracked files cover
  every Create/Modify path in plan.md's Files affected list (plus the
  necessary tests/integration/conftest.py test-infra extension, not
  literally named in the plan but required to test the new scope field/quotas
  table, and the unrelated pre-existing dirty-tree files from before this
  session, untouched by this feature). Security invariant quick scan clean
  (no hardcoded secrets; every quotas query scoped by api_key_id; all inputs
  through Pydantic schemas with the exact anchored patterns the plan
  specifies). .pipeline/surface-delta.md written. Full suite re-confirmed
  green a second time after cleanup (124 passed, 152.93s). DONE.
