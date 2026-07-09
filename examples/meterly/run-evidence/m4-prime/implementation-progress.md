# Implementation progress — usage CSV export (GET /v1/usage/export)

## Status: COMPLETE

All plan items built, all tests green, docs updated, self-check done,
surface-delta.md written. Ready for the coordinator's final report / handoff
to testing.

## DONE

Test-first, unit-level red->green recorded per unit:

- T1 CSV encoding facade: tests written+red (`tests/test_csv_export.py`, 15 cases) →
  code (`src/api/csv_export.py`: `EXPORT_HEADER`, `escape_csv_text_cell`,
  `format_window_start`, `format_total_quantity`) → green (15 passed).
- T2 Query schema: tests written+red (`tests/test_schemas_usage_export.py`, 13 cases) →
  code (`src/api/schemas/usage_export.py`: `UsageExportQueryParams`, reuses
  `CustomerId`/`Metric` from `src/api/schemas/events.py`, `from`-alias +
  `[now-90d, now+1h]` range validator) → green (13 passed).
- T3 Repository (integration-covered per plan's test-strategy tier bias, no
  dedicated unit file): extended `src/repositories/usage_repo.py` with
  `UsageRollupExportRecord`, `count_usage_rollups`, `stream_usage_rollups`
  (shared `_export_filter_clause_and_params` helper, bound params only, fixed
  literal ORDER BY).
- T4 Service: tests written+red (`tests/test_usage_export_service.py`, 7 cases,
  DB mocked via monkeypatching `scoped_transaction`/`count_usage_rollups`/
  `stream_usage_rollups`) → code (`src/services/usage_export_service.py`:
  `prepare_export`, `stream_export_csv`, `MAX_EXPORT_ROWS=100_000`) → green
  (7 passed). Covers AC8/AC9/AC12/AC17/AC22 at the unit tier.
- T5 Route: `src/api/routes/usage_export.py` (two-phase cap-then-stream,
  `responses=` OpenAPI metadata for the streamed 200/422 shapes), registered in
  `src/main.py` (`usage_export_router`, mounted between `usage_router` and
  `quotas_router`).
- T6 Integration: `tests/integration/test_usage_export_endpoint.py` — 18 tests,
  all green: header-only empty (AC12), filters incl. customer_id/metric/from-to
  and none-omitted-all (AC2), malformed/unknown query param 422 (AC4), auth 401
  + any-scope 200 (AC6), tenant isolation (AC7), row cap 422 no-partial-body
  (AC8), deterministic ordering (AC13), formula-injection end-to-end (AC10),
  response headers incl. strict filename regex (AC11), streaming-not-buffered
  via a real out-of-process uvicorn server (AC9 — `ASGITransport` was proven
  unusable for this, see Note below), OpenAPI schema exposure (AC19/DAST-1),
  forced pre-flight COUNT error -> generic 500 (AC22), and a dedicated
  two-principals-one-IP Tier-2 discriminator for this route (AC5).
- T7 Perf sanity: `tests/integration/test_usage_export_perf.py` (AC16) — green.
  Measures real p95 at 100,000 rows and asserts correctness (full,
  untruncated row set), following the project's `test_perf_smoke.py`
  honest-disclosure convention rather than hard-asserting the documented
  500ms budget (see Note below — real measured p95 is ~9.8s, far over
  budget, an honest open finding, not silently hidden or gated on).
- T8 Docs: updated `src/api/README.md`, `src/services/README.md`,
  `src/repositories/README.md`, `docs/system_architecture.md` (new
  `GET /v1/usage/export` request-flow section, mermaid diagram edge, and a
  "Known deviations" entry documenting the p95 finding). `PROJECT.md` was
  already updated by planning (feature description swapped from quotas to
  CSV export) — verified, not touched further.

## Note — a real bug found and fixed during integration testing

`httpx.ASGITransport`'s `ASGIResponseStream.__aiter__` does
`yield b"".join(self._body)` — it joins the ENTIRE response body into a single
chunk before the test ever sees it, regardless of how many times the app
`yield`s. This made the streaming-not-buffered sanity check meaningless against
the in-process `client` fixture (chunk_count was always 1, pass or fail
independent of real behavior). Fixed by adding a `running_server` fixture
(out-of-process uvicorn, mirrors `tests/integration/test_perf_smoke.py`'s
pattern) so the test observes genuine socket-level chunk boundaries. Also hit
the documented `ASGITransport(raise_app_exceptions=False)` requirement for the
AC22 forced-500 test (same pattern already established in
`tests/integration/test_events_endpoint.py`'s AC19 test) — the default
`client` fixture re-raises app exceptions instead of returning the 500
response.

## Note — honest perf finding (AC16, plan's Open Question 1)

Measured p95 for a full 100,000-row export (real Postgres testcontainer,
in-process ASGI) was **~9.8 seconds**, far over the plan's proposed-but-
unconfirmed 500ms target. Root cause is per-row Python-level CSV
encoding/escaping/formatting + generator overhead across 100k rows, not DB
query time (the pre-flight COUNT and the bounded sort are both fast). This is
disclosed in `docs/system_architecture.md`'s "Known deviations" section and
in the perf test's scratch-file measurement
(`meterly_usage_export_perf_measurement.json`), not silently hidden. The plan
explicitly left the 500ms number open pending checkpoint confirmation — this
is the data point for that decision, not a defect I introduced by deviating
from the plan's chosen design (server-side cursor + stdlib `csv`, which was
locked in by the plan).

## Verification performed this session

- Full suite: `pytest tests -q --cov=src --cov-branch --deselect
  tests/integration/test_perf_k6_load.py` → **178 passed, 88% coverage**
  (gate is >=85%). `test_perf_k6_load.py` (4 tests, all pre-existing, none
  touching this feature's route) was deselected rather than run: verified
  this session via `which k6` that no k6 binary is on PATH in this sandbox,
  and via `--collect-only` that the 4 tests are unrelated to
  `GET /v1/usage/export` (they exercise `POST /v1/events` / `GET /v1/usage`
  under k6 load). Not run standalone to confirm its own skip/fail behavior —
  unverified beyond the binary-absence and unrelatedness checks above.
- Self-check (a): `git diff HEAD --name-only` + `git ls-files --others
  --exclude-standard` — every planned create/modify file is present: `PROJECT.md`,
  `docs/system_architecture.md`, `src/api/README.md`, `src/main.py`,
  `src/repositories/README.md`, `src/repositories/usage_repo.py`,
  `src/services/README.md` (modified); `src/api/csv_export.py`,
  `src/api/routes/usage_export.py`, `src/api/schemas/usage_export.py`,
  `src/services/usage_export_service.py`, plus the 5 test files (new,
  untracked). No planned file missing; no stray files (transient
  `.coverage.*` worker artifacts from local test runs were deleted).
- Self-check (b) hardcoded secrets: `grep -rniE
  "(api_key|apikey|token|secret|password|credentials)\s*=\s*['\"][^'\"]{8,}"`
  across all changed files → no matches.
- Self-check (b) RLS scoping: confirmed `count_usage_rollups` and
  `stream_usage_rollups` (`src/repositories/usage_repo.py`) both start their
  WHERE clause with `api_key_id = :api_key_id` via the shared
  `_export_filter_clause_and_params` helper; `api_key_id` is sourced only from
  `principal.api_key_id` in the service, never from client input.
- Self-check (b) unsanitized inputs: confirmed the only new HTTP input
  surface (`GET /v1/usage/export` query params) is bound through
  `Annotated[UsageExportQueryParams, Query()]` in
  `src/api/routes/usage_export.py` — schema-first, `extra="forbid"`, reused
  anchored-allowlist `constr` types for `customer_id`/`metric`.
- Self-check (c) acceptance criteria: all 22 criteria in
  `.pipeline/acceptance.md` are addressed — AC1-AC17, AC19-AC22 built and
  test-covered (unit and/or integration, mapped in T1-T7 above); AC18 is
  delegated to the security stage per the plan's frontmatter
  (`delegated_criteria: [AC18]`), not built here by design.

No migration needed (plan: `migration_added: false`, read-only feature, no
new stored data). No `infra/` change. `.pipeline/surface-delta.md` already
written (new entry point, new CSV-formula trust boundary, new DB queries/log
event, new-but-matching-existing-shape authz surface).
