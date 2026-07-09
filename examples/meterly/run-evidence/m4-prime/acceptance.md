---
feature: usage CSV export (GET /v1/usage/export)
criteria_total: 22
delegated_criteria: [AC18]
derived_from: PROJECT.md + .pipeline/requirements.md (resolved items) + STRIDE + input-surface + DAST-readiness
notes: >
  Feature-level definition-of-done. Implementation builds to these; testing maps each ID to a
  test (criteria_covered). AC18 is delegated to the security stage (ASVS reconciliation), so
  testing marks it covered:false, delegated:"security". No performance k6 load AC: the export is
  a reporting route with a documented p95 sanity check (AC16); the binding perf constraint is the
  negative one (AC15 — existing endpoints/budgets untouched). AC22 (added in the revision pass)
  covers the pre-flight safe-error shape — distinct from plan §R3, which only accepts the
  post-200 mid-stream truncation case.
---

| ID | Criterion | File / layer | How verified |
|---|---|---|---|
| AC1 | Response is RFC 4180 CSV via stdlib `csv`: header row exactly `customer_id,metric,window_start,total_quantity` (brief column order), CRLF line endings, fields containing comma/quote/newline quoted | `src/api/csv_export.py`, `src/services/usage_export_service.py` | Unit (dialect, header, CRLF, quoting) + integration end-to-end body assertion |
| AC2 | Optional `customer_id`/`metric`/`from`/`to` filters applied (reusing existing allowlist types + window bounds); all omitted → full supported range | `src/api/schemas/usage_export.py`, `src/repositories/usage_repo.py` | Unit (schema) + integration (each filter narrows the row set; none → all caller rows) |
| AC3 | `from`/`to` validation: timezone-aware, `from <= to`, both within `[now-90d, now+1h]`, naive datetime rejected | `src/api/schemas/usage_export.py` | Unit (accept/reject cases incl. naive, inverted range, out-of-window) |
| AC4 | Input validation (non-waivable): malformed / wrong-type / unknown / out-of-range query param → 422 `validation_failed`; `extra="forbid"` rejects unknown params | `src/api/schemas/usage_export.py`, `src/api/errors.py` | Unit + integration (422 envelope with `code=validation_failed`) |
| AC5 | Rate limit: post-auth **Tier-2 per-`api_key_id`** throttle applies (principal-keyed); two principals on one client IP get independent buckets | `src/api/routes/usage_export.py` (reuses `src/auth/rate_limit.py`) | Integration two-principals-one-IP discriminating test |
| AC6 | Authorization: any authenticated key (ingest or admin) may export; unauthenticated/invalid → 401; no scope gate | `src/api/routes/usage_export.py`, `src/auth` | Integration (ingest key 200, admin key 200, no/invalid key 401) |
| AC7 | Tenant isolation: export returns ONLY the caller's `api_key_id` rows; two tenants' data never cross (explicit `api_key_id` filter is the primary control; RLS is backstop) | `src/repositories/usage_repo.py` | Integration two-tenant test (tenant A's export excludes tenant B's rows) |
| AC8 | Row cap: a result exceeding 100,000 rows → 422 `validation_failed` ("narrow filters"), **no partial body streamed** (pre-flight count before any response byte) | `src/services/usage_export_service.py`, `src/repositories/usage_repo.py` | Integration (>100k rows → 422, response body is the envelope not CSV) |
| AC9 | Streaming constant memory: rows streamed as read via a server-side cursor, response not fully buffered before send | `src/services/usage_export_service.py` | Integration streaming-not-buffered sanity (first bytes observable before generator exhausted / bounded memory on a large export) |
| AC10 | CSV formula-injection escape: text cells (`customer_id`,`metric`) starting with `= + - @ \t \r` prefixed with `'`; control chars neutralized; numeric/timestamp cells untouched | `src/api/csv_export.py` | Unit (incl. leading-`-` `customer_id`, each trigger, control chars, numeric/timestamp unaffected) + integration end-to-end |
| AC11 | Response headers: `Content-Type: text/csv; charset=utf-8`; `Content-Disposition: attachment; filename=usage-export-<UTC timestamp>.csv` (no tenant identifier in filename); inherits `nosniff` + `Cache-Control: no-store` | `src/api/routes/usage_export.py`, `src/api/middleware.py` | Integration header assertions (incl. filename pattern, no tenant id) |
| AC12 | Empty result → 200 header-only CSV (single header row, zero data rows), never 404 | `src/services/usage_export_service.py` | Integration (caller with no matching rollups → 200, one CSV line) |
| AC13 | Deterministic ordering `ORDER BY window_start, customer_id, metric ASC`; identical exports are byte-stable | `src/repositories/usage_repo.py` | Integration (asserts row order over a seeded multi-row set) |
| AC14 | Value formats: `window_start` as UTC ISO-8601 with offset (identical to JSON response form); `total_quantity` as `str(Decimal)` (plain decimal, no scientific notation) | `src/api/csv_export.py`, `src/services/usage_export_service.py` | Unit + integration (format assertions) |
| AC15 | No behavior change: `POST /v1/events`, `GET /v1/usage`, `PUT /v1/quotas` behavior/budgets/tests unchanged; no new Alembic revision / migration added | repo-wide (negative) | Existing test suites pass unchanged; no new file under `alembic/versions/` |
| AC16 | Performance budget: export route **p95 < 500 ms at the 100,000-row cap** (documented target, integration timing sanity — NOT a k6 load AC) | `src/services/usage_export_service.py`, `src/repositories/usage_repo.py` | Integration timing sanity test at ~100k rows |
| AC17 | Audit logging: exactly one `usage.export` `info` event at completion (`userId`=opaque `api_key_id`, `operation`, `rowCount`, `capped`, `completed`, filter-presence booleans — no raw `customer_id`); over-cap request logged at `warn` | `src/services/usage_export_service.py`, `src/logging` | Unit/integration (log fields present, no PII, one event; `warn` on over-cap) |
| AC18 | ASVS 5.0 L1/L2 controls for the triggered chapters (V1/V2/V4/V6/V8/V13/V14/V16) present across the change set; recorded waivers honored | cross-cutting | Delegated to security stage (`delegated:"security"`) — reconciled against plan §ASVS Compliance |
| AC19 (DAST-1) | Served OpenAPI schema includes `GET /v1/usage/export` with its `200 text/csv` and `422` responses, matching the implemented route (not hand-drifted) | `src/api/routes/usage_export.py` | Integration (assert route + responses present in `/openapi.json`) |
| AC20 (DAST-2) | A seeded non-production DAST test key (reuse the existing seeded key; credentials from env/secrets, never hardcoded) can call the export | `scripts/seed_api_key.py` (existing), test fixtures | Integration (seeded key successfully hits the export in staging/local) |
| AC21 (DAST-3) | Auth-context recorded for scanners: `Authorization: Bearer mtr_live_<key_id>_<secret>` header shape, documented in the plan and exercised by the integration auth path | plan §Auth, `src/auth/api_key.py` (existing) | Documented in plan + integration test uses this exact Bearer shape |
| AC22 | Safe-error / fail-closed pre-flight: a forced internal error during the pre-flight `prepare_export` `COUNT` phase (before any response byte) returns the generic `500 internal` error-envelope (no stack/SQL/internal path leaked), rolls back the transaction, and starts **no** stream / emits **no** partial CSV body (ASVS 16.5.x). Distinct from plan §R3 (post-200 mid-stream truncation, accepted) | `src/services/usage_export_service.py`, `src/api/errors.py`, `src/api/routes/usage_export.py` | Unit in `tests/test_usage_export_service.py` (non-cap DB error propagates, not swallowed, no stream started) + integration in `tests/integration/test_usage_export_endpoint.py` (forced pre-flight `COUNT` error → `500 internal` envelope, no leak, no partial body) |
