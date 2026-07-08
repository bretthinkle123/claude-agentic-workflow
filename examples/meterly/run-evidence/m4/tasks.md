# Tasks — per-customer metric quotas

Large-feature decomposition (TA/A-3): this feature exceeds both triggers (22 acceptance criteria;
~26-file change set), so implementation executes `plan.md` **task-by-task** with a checkpoint at each
task boundary. This is **not** a second agent or a new stage — implementation still runs once; this is
the ordered build plan it follows and can resume against.

Ordered by dependency. `depends_on` gates start order; tasks with no shared dependency and disjoint
files are parallel-safe (noted). The union of all `ACs advanced` covers every buildable AC
(AC1–AC21); **AC22 is delegated to the security stage** and is intentionally not assigned to a build
task.

| ID | depends_on | ACs advanced | test_strategy slice (tests this task's code must make pass) | expected files |
|---|---|---|---|---|
| **T1** | — | AC16 (partial: schema+constraints) | `tests/integration/test_quota_migration.py` (0003 up→down→up: quotas PK/FK/`CHECK(limit>=1)`, `api_keys.scope CHECK`, api_keys row survival) | `alembic/versions/0003_create_quotas_and_api_key_scope.py`, `tests/integration/test_quota_migration.py` |
| **T2** | T1 | AC17 | `tests/integration/test_seed_api_key_script.py::test_admin_flag_sets_scope` (unit-ish integration: `--admin`→`scope='admin'`, default `'ingest'`); auth unit tests still green with the new defaulted `scope` field | `src/repositories/api_keys_repo.py` (SELECT/insert `scope`), `src/auth/api_key.py` (`ApiKeyRecord.scope`, `AuthenticatedPrincipal.scope`), `scripts/seed_api_key.py` (`--admin`), `tests/integration/test_seed_api_key_script.py` |
| **T3** | T1, T2 | AC1, AC2, AC3, AC4, AC5, AC6, AC15, AC18 (write path), AC19 (upsert + forbidden), AC21 (OpenAPI presence) | `tests/test_schemas_quotas.py` (unit: validation contract); `tests/integration/test_quotas_endpoint.py` (201/200 upsert, 403 ingest, 401, 422, tenant isolation, per-principal rate limit, injection-at-boundary, openapi exposes route, upsert/forbidden logged) | `src/api/schemas/quotas.py`, `src/repositories/quotas_repo.py` (`upsert_quota`), `src/services/quota_service.py`, `src/api/routes/quotas.py`, `src/api/errors.py` (`AppError` + `app_code` honored), `src/api/middleware.py` (CORS `PUT`), `src/main.py` (mount router), `tests/test_schemas_quotas.py`, `tests/integration/test_quotas_endpoint.py` |
| **T4** | T1, T3 (`AppError`, `quotas_repo`) | AC7, AC8, AC9, AC10, AC11, AC12, AC14, AC18 (read path), AC19 (rejected) | `tests/integration/test_events_quota_enforcement.py` (unlimited passthrough, under-limit accepted, over-limit 429 + no partial write + `Retry-After`, empty-window `Q>L`, replay-over-quota 200 no usage, mid-window effect, throttle-precedes-quota distinct codes, rejection logged without totals) | `src/repositories/quotas_repo.py` (`read_tenant_quota_state_locked` — `FOR UPDATE OF q`), `src/services/events_service.py` (quota check on the winning-insert branch + `quota.rejected` log), `tests/integration/test_events_quota_enforcement.py` |
| **T5** | T4 | AC13 (+ AC16 completion via the enforcement path exercised on real Postgres) | `tests/integration/test_quota_concurrency.py::test_concurrent_posts_never_exceed_limit` (N concurrent distinct-key posts vs `L`; final rollup total `<= L`; excess 429) | `tests/integration/test_quota_concurrency.py` |
| **T6** | T3, T4 | AC20 (perf), AC21 (DAST context + admin test key) | `tests/integration/test_perf_k6_load.py::test_events_ingest_with_quotas_p95_under_50ms` (nearest-rank p95 with quotas active); `tests/test_dast_context_documented.py` (Bearer/`mtr_live` context present) | `tests/integration/k6/load_events_quota.js`, `tests/integration/test_perf_k6_load.py`, `docs/system_architecture.md`, `src/api/README.md`, `src/services/README.md`, `src/repositories/README.md`, `src/auth/README.md`, `CLAUDE.md` |

Parallel-safe notes:
- **T1** and (the schema/errors parts of) **T3** are independent in file terms, but T3's routes/repos
  depend on the migration existing to run integration tests — keep the T1→T3 order.
- **T5** and **T6** both depend only on T4 (T6 also on T3) and touch disjoint files (concurrency test
  vs. perf/docs) — they are parallel-safe once T4 lands.
- **AC22** (ASVS reconciliation) is produced by the security stage, not a build task — see
  `acceptance.md` `delegated_criteria`.
