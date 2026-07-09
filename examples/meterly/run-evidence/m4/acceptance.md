---
criteria_total: 22
delegated_criteria: [AC22]
---

# Acceptance criteria — per-customer metric quotas

Definition-of-done for this feature. Implementation builds to these; testing maps each ID to a test
(`criteria_covered`); the deploy gate requires `criteria_covered.total == criteria_total` and that
every delegated id appears in `delegated_criteria` (only `security` is a valid delegate). Derived
from `.pipeline/requirements.md` (authoritative) + `PROJECT.md`.

| ID | Criterion | File / layer | How verified |
|---|---|---|---|
| AC1 | `PUT /v1/quotas` (admin key + valid body) creates a quota → **201**, response echoes `{customer_id, metric, limit_per_window}`, exactly one `quotas` row persisted | `src/api/routes/quotas.py`, `src/services/quota_service.py`, `src/repositories/quotas_repo.py` | `tests/integration/test_quotas_endpoint.py::test_put_creates_quota_returns_201_and_echoes` |
| AC2 | `PUT /v1/quotas` replacing an existing `(customer_id, metric)` → **200**, `limit_per_window` updated, still exactly one row (upsert, no duplicate) | `src/repositories/quotas_repo.py` (`xmax` insert/replace) | `tests/integration/test_quotas_endpoint.py::test_put_replace_returns_200_single_row` |
| AC3 | `PUT /v1/quotas` with an **ingest**-scoped key → **403**, envelope `code: forbidden`; admin scope required | `src/api/routes/quotas.py`, `src/auth/api_key.py` | `tests/integration/test_quotas_endpoint.py::test_ingest_key_forbidden` |
| AC4 | `PUT /v1/quotas` with missing/malformed/revoked auth → **401** | `src/auth/api_key.py` | `tests/integration/test_quotas_endpoint.py::test_put_requires_auth` |
| AC5 | Validation: `limit_per_window` = 0/negative/non-integer → **422** `validation_failed`; unknown field → 422 (`extra='forbid'`); `customer_id`/`metric` outside allowlist → 422 | `src/api/schemas/quotas.py` | `tests/test_schemas_quotas.py` + `tests/integration/test_quotas_endpoint.py::test_validation_rejections` |
| AC6 | Tenant isolation: a quota is stored under and enforced against the authenticated `api_key_id` only; a second tenant's key never reads/affects tenant A's quota (api_key_id scoping + RLS) | `src/repositories/quotas_repo.py`, `alembic/versions/0003_*`, `src/db/session.py` | `tests/integration/test_quotas_endpoint.py::test_quota_is_tenant_isolated` |
| AC7 | `POST /v1/events` for a `(customer, metric)` with **no quota** → unchanged behavior (201, unlimited); no regression | `src/services/events_service.py` | `tests/integration/test_events_quota_enforcement.py::test_no_quota_is_unlimited` |
| AC8 | `POST /v1/events` where `R + Q <= L` → **201** accepted, rollup increments normally | `src/services/events_service.py`, `src/repositories/quotas_repo.py` | `tests/integration/test_events_quota_enforcement.py::test_under_limit_accepted` |
| AC9 | `POST /v1/events` where `R + Q > L` → **429** envelope `code: quota_exceeded` + `Retry-After` header (seconds to next hour); **no event row persisted and rollup not incremented** (transaction rolled back) | `src/services/events_service.py`, `src/api/errors.py` | `tests/integration/test_events_quota_enforcement.py::test_over_limit_429_and_no_partial_write` |
| AC10 | `Q > L` against an **empty window** → **429** `quota_exceeded`; no rollup row created | `src/repositories/quotas_repo.py`, `src/services/events_service.py` | `tests/integration/test_events_quota_enforcement.py::test_empty_window_q_gt_l_rejected` |
| AC11 | Idempotent replay of a previously-**accepted** event, window now over quota → **200** replay of the original stored result; quota **not** consulted; no usage added | `src/services/events_service.py` | `tests/integration/test_events_quota_enforcement.py::test_replay_over_quota_returns_200_no_usage` |
| AC12 | A quota set/lowered **mid-window** takes effect immediately against the already-accumulated rollup (lowering `L <= R` blocks the rest of the window) | `src/repositories/quotas_repo.py` (fresh read per POST) | `tests/integration/test_events_quota_enforcement.py::test_midwindow_change_takes_effect` |
| AC13 | Strict enforcement under concurrency: N concurrent **distinct-idempotency-key** posts of `Q` against `L` never drive `usage_rollup.total_quantity` above `L`; the excess are rejected 429 | `src/repositories/quotas_repo.py` (`FOR UPDATE OF q`), `src/services/events_service.py` | `tests/integration/test_quota_concurrency.py::test_concurrent_posts_never_exceed_limit` |
| AC14 | Throttle precedence: the Tier-2 per-key throttle (`code: rate_limited`) still fires before any quota logic; quota rejection uses the **distinct** `code: quota_exceeded` | `src/api/routes/events.py`, `src/api/errors.py` | `tests/integration/test_events_quota_enforcement.py::test_throttle_precedes_quota_distinct_codes` |
| AC15 | `PUT /v1/quotas` is rate-limited by the **Tier-2 per-`api_key_id`** token bucket (principal-keyed, post-auth); two principals sharing one IP get independent buckets | `src/api/routes/quotas.py`, `src/auth/rate_limit.py` | `tests/integration/test_quotas_endpoint.py::test_put_rate_limited_per_principal` (two-principals-one-IP shape) |
| AC16 | Migration `0003` `up→down→up` restores schema + re-enforces all constraints (`quotas` PK/FK/`CHECK(limit>=1)`, `api_keys.scope CHECK IN ('ingest','admin')`); `quotas` is a create-migration (no row-survival across down); pre-existing `api_keys` rows survive the scope column add/drop (scope resets to `'ingest'` default — defined expand/contract behavior) | `alembic/versions/0003_*` | `tests/integration/test_quota_migration.py::test_0003_roundtrip_schema_and_constraints` |
| AC17 | `seed_api_key.py --admin` provisions a key with `scope='admin'`; without the flag `scope` defaults to `'ingest'` | `scripts/seed_api_key.py`, `src/repositories/api_keys_repo.py` | `tests/integration/test_seed_api_key_script.py::test_admin_flag_sets_scope` |
| AC18 | All new `quotas` SQL is parameterized (`text()` bind params only); an injection payload in `customer_id`/`metric` is rejected at the schema boundary (422) and never reaches the SQL sink | `src/api/schemas/quotas.py`, `src/repositories/quotas_repo.py` | `tests/integration/test_quotas_endpoint.py::test_injection_rejected_at_boundary` + security 6c (Semgrep) |
| AC19 | Observability/audit: a quota rejection logs `quota.rejected` (WARNING; `userId`, `action=deny`, `customer_id`, `metric`, `reason` — **no** usage totals); a quota upsert logs `quota.upsert` (`action=create|replace`, who/what/when); a scope-denied PUT logs `quota.forbidden` | `src/services/quota_service.py`, `src/services/events_service.py`, `src/api/routes/quotas.py` | `tests/integration/test_events_quota_enforcement.py::test_rejection_is_logged_without_totals` + `test_quotas_endpoint.py::test_upsert_and_forbidden_logged` |
| AC20 (perf) | `POST /v1/events` under the sustained distributed-key k6 load **with quotas active** (high limits, no rejection): **quota-active p95 ≤ 1.5× the same-session no-quota baseline p95, both measured at equal uvicorn worker budget** — the quota-check path does not blow the existing budget. *[Human-revised at the 2026-07-09 debugging escalation; the original absolute form "p95 < 50 ms" is unachievable on this Docker-Desktop/Windows host for any code (no-quota baseline ~84 ms). The 50 ms absolute figure remains the production-infra budget, owned by the post-merge CI load-campaign workflow against staging.]* | `src/repositories/quotas_repo.py`, `src/services/events_service.py`; `tests/integration/k6/load_events_quota.js` | `tests/integration/test_perf_k6_load.py::test_events_ingest_with_quotas_p95_within_1_5x_baseline` (drives the no-quota baseline and quota-active load in the same session at equal worker budget, nearest-rank p95 over raw k6 samples for both, asserts `quota_p95 <= 1.5 * baseline_p95`) |
| AC21 (DAST-readiness) | The served `/openapi.json` includes `PUT /v1/quotas` matching the implemented route/schema; the DAST auth context documents an **admin**-scoped seeded test key (`seed_api_key.py --admin`) with the `Authorization: Bearer mtr_live_<key_id>_<secret>` scheme | `src/api/routes/quotas.py`, `.pipeline/plan.md`, `docs/system_architecture.md` | `tests/test_dast_context_documented.py` + `tests/integration/test_quotas_endpoint.py::test_openapi_exposes_put_quotas` |
| AC22 | ASVS 5.0.0 L1/L2 (+ in-scope L3: V15.4.x safe concurrency, V11.2.4 constant-time) reconciliation across the change set — triggered chapters V1/V2/V4/V6/V8/V12/V13/V14/V15/V16 met or waived | security stage (`asvs` reconciliation block) | delegated: `security` (covered:false at the testing stage) |

Notes:
- AC22 is **delegated to the security stage** (ASVS reconciliation is its deliverable, not a
  test-suite assertion) — declared in `delegated_criteria` above; testing marks it
  `covered: false, delegated: "security"`.
- AC20 is a measurable **performance** criterion (quota-active p95 ≤ 1.5× the same-session
  no-quota baseline p95 on `POST /v1/events`, equal worker budget) — measured by testing's
  performance mode against the real k6 harness; it rides `criteria_covered`. Human-revised at the
  debugging escalation (see the AC20 row); p95 < 50 ms absolute stays as the CI/staging
  load-campaign budget.
- No `data_protection` criterion is emitted: every new stored field is classified **non-sensitive
  operational config** (see plan *Data classification*), so no field-level KDF/KMS mechanism is
  required — `data_protection_waiver: all new stored fields (customer_id, metric, limit_per_window,
  scope) are non-sensitive opaque operational config already stored as identifiers; RDS SSE
  (storage-level) covers them`.
