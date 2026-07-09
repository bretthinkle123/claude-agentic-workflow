# Usage CSV export — `GET /v1/usage/export`

## Summary

Adds one new read-only endpoint, `GET /v1/usage/export`, that streams the authenticated
caller's own `usage_rollup` rows as an RFC 4180 CSV (`customer_id,metric,window_start,
total_quantity`), with optional `customer_id`/`metric`/`from`/`to` filters, a hard
100,000-row cap enforced by a pre-flight `COUNT` before any response byte, and OWASP
CSV-formula-injection escaping at the encoding boundary. It reuses every existing edge
control (API-key auth, Tier-2 per-key throttle, security headers, error envelope,
structured logging) and adds no migration, no new stored data, and no change to any
existing endpoint. Full design and the STRIDE threat model are in `.pipeline/plan.md`
(now also retained at `docs/decisions/feature/usage-export/plan.md`).

This PR includes a cycle-2 remediation: the initial implementation's export p95 at the
100,000-row cap measured ~10.7s (far over the plan's proposed 500ms), root-caused during
debugging to a chunk-per-row streaming pattern interacting badly with the app's four
nested `BaseHTTPMiddleware` layers. See Decisions & tradeoffs below.

## Changes

- **Route** (`src/api/routes/usage_export.py`, new): `GET /v1/usage/export`, composing
  auth -> Tier-2 throttle -> a two-phase pre-flight-cap-then-stream service call. Declares
  explicit OpenAPI `responses=` metadata (200 `text/csv`, 422) since a `StreamingResponse`
  has no `response_model` to introspect.
- **Schema** (`src/api/schemas/usage_export.py`, new): `UsageExportQueryParams` — optional
  `customer_id`/`metric`/`from`/`to` filters reusing the existing anchored-allowlist
  `constr` types and `[now-90d, now+1h]` bound idiom, `extra="forbid"`.
- **Service** (`src/services/usage_export_service.py`, new): `prepare_export` (pre-flight
  `COUNT` cap check, fail-closed on any other error) and `stream_export_csv` (the
  constant-memory streaming generator, header-first, one `usage.export` audit log per
  request in a `finally` block).
- **CSV facade** (`src/api/csv_export.py`, new): `EXPORT_HEADER`, `escape_csv_text_cell`
  (the OWASP formula-injection escape), and value formatters.
- **Repository** (`src/repositories/usage_repo.py`, extended — existing
  `find_usage_rollup` untouched): adds `UsageRollupExportRecord`, `count_usage_rollups`,
  `stream_usage_rollups`, and the shared `_export_filter_clause_and_params` helper.
- **`src/main.py`**: registers the new router (one `include_router` line).
- **`.github/workflows/pipeline-ci.yml`**: adds `--cov-fail-under=85` to the CI test step
  (was previously enforced only by the local gate).
- **Docs**: `src/api/README.md`, `src/services/README.md`, `src/repositories/README.md`,
  `tests/README.md`, `tests/integration/README.md`, `docs/system_architecture.md` (new
  `GET /v1/usage/export` request-flow section + Mermaid diagram edge), `PROJECT.md`.

## Decisions & tradeoffs

- **Streaming design:** a PostgreSQL server-side cursor inside one tenant-scoped
  transaction, chosen over buffering (memory-exhaustion risk at 100k rows) and over
  pagination (out of scope per the brief). Tradeoff: the DB connection is held open for
  the client-download duration — bounded by the row cap, the Tier-2 throttle, and pool
  sizing (accepted risk R1 in the plan).
- **No new index for the export's `ORDER BY`:** the requested sort order doesn't align
  with `usage_rollup`'s primary key, so PostgreSQL does a bounded in-memory sort of
  ≤100k rows rather than an index scan. A covering index was rejected for this slice
  because it would be a migration (out of scope) and would add write cost to the
  unrelated, must-stay-untouched `POST /v1/events` hot path.
- **Perf remediation (cycle 2), within the approved design:** the true p95 bottleneck was
  the generator yielding one chunk per row — each of the four nested
  `BaseHTTPMiddleware` layers re-pumps every chunk through its own anyio stream, so cost
  scaled with `chunk_count x middleware_layers`. Fixed by batching `_ROWS_PER_CHUNK=1000`
  rows per chunk, precompiling the CSV escape's control-char strip as a `str.translate`
  table (verified byte-for-byte equivalent to the prior per-character filter), and tuning
  the server-side cursor with `yield_per=5000`. p95 dropped from ~10.7s to a stable
  ~1.4-2.1s. Full isolation profiling in `.pipeline/debug-notes.md` (also retained under
  `docs/decisions/feature/usage-export/`).
- **AC16 budget revision (human-confirmed):** the plan's original 500ms target proved
  unreachable within the mandated constant-memory-streaming design (an irreducible
  ~0.85-1.0s cursor-drain + encoding floor at the cap). The human confirmed a revised,
  binding budget of **p95 <= 3,000ms at the 100,000-row cap** at the 2026-07-09
  escalation; the perf test now hard-asserts this bound (this session's re-run: p95
  1,643.87ms).
- **RLS backstop is inert for `usage_rollup`** (no `FORCE`, app role owns the table) —
  pre-existing, unchanged by this feature. Tenant isolation rests entirely on the
  explicit, mandatory `api_key_id` filter on every query (verified present on both new
  queries). A follow-up migration adding `FORCE ROW LEVEL SECURITY` is recommended but
  not built in this slice (plan Open Question 3).

## Testing

**21 test-covered + 1 delegated to security** (of 22 acceptance criteria; see
`.pipeline/test-results.json` `criteria_covered.by_id`). The delegated criterion is
**AC18** (ASVS 5.0 L1/L2 reconciliation across the triggered chapters) — per
`.pipeline/acceptance.md`'s frontmatter (`delegated_criteria: [AC18]`), this is not a
test-suite assertion; it is reconciled and verified clean in the security report.

- 180 tests passed, 0 failed (116 unit, 64 integration); 4 k6-driven tests skipped (no k6
  binary on this sandbox's PATH — verified).
- Coverage: **91% lines, 66% branches** (combined). Branch coverage is surfaced here per
  policy, not gated.
- Test-pyramid shape matches the planned `pyramid` strategy: the bulk of the CSV
  escaping/quoting, schema validation, and value-formatting logic is unit-tested; a
  thinner integration tier (real Postgres via testcontainers) covers streaming,
  deterministic ordering, tenant isolation, the pre-flight cap 422, the pre-flight
  fail-closed 500 (AC22), response headers, and streaming-not-buffered behavior.
- Perf (AC16): p95 1,643.87ms / min 1,093.57ms / median 1,385.42ms at the 100,000-row cap
  (10-sample), against the human-confirmed 3,000ms budget — pass.
- **Test quality (advisory, from `.pipeline/test-quality.json`):** `quality_ok: false` —
  mutation testing (mutmut) could not run on this native-Windows session (mutmut requires
  WSL; deliberately deferred to the Linux CI `mutation` job, currently `if: false`
  pending `<MUTATION_CMD>`/`<MUTATION_SCOPE>`), so the configured scope
  (`csv_export.py`, `usage_export_service.py`, `schemas/usage_export.py`) has **no
  measured mutation score this session** — reported honestly as unmeasured rather than
  claimed passing. Notable adversarial gaps flagged by the testing agent (all low/medium
  severity, none blocking): the AC9 streaming-not-buffered proxy (chunk-count > 1) doesn't
  directly measure peak memory; no integration test combines all four export filters
  simultaneously; no test drives a real mid-stream client disconnect against the live
  integration server (only a mocked-generator unit proof); a `usage_repo.py` line
  (`count_usage_rollups`'s `return result.scalar_one()`) shows as coverage-missed despite
  being exercised by many passing tests (suspected line-mapping artifact, not confirmed).

## Security

**Verdict: clean.** Scope: diff. 0 critical findings, 4 warnings, 7 total findings (see
`.pipeline/security-report.md`, also retained at
`docs/decisions/feature/usage-export/security-report.md`):
- 2 Semgrep `avoid-sqlalchemy-text` ERROR hits — verified false positives (fully
  parameterized queries; corroborated independently by ast-grep's structural pass).
- 2 Semgrep `github-actions-mutable-action-tag` WARNINGs — pre-existing, outside this
  diff's changed hunk (the CI workflow's only change is the `--cov-fail-under=85` line).
- 1 OSV CVE (`pytest` 8.3.4, tmpdir handling, CVSS ~6.8 Moderate) — dev-only dependency,
  below the deploy gate's 7.0 floor; safe upgrade path (9.0.3) recorded, not auto-fixed.
- Gitleaks' 127 raw hits are all `.venv/` dependency data or test fixtures — out of scope.
- 1 pre-existing RLS `FORCE`-backstop gap on `usage_rollup` (accepted risk, see above).
- All 8 STRIDE-table mechanisms verified present **and** effective; ASVS chapters
  V1/V2/V4/V6/V8/V13/V14/V16 reconciled (`l1_l2_missing: []`); `stride_new_threats: 0` —
  every new surface this feature introduces (the route, the CSV-to-spreadsheet boundary,
  the two new queries, the streamed body, the new log event) maps to an existing
  threat-model row.

## Supply chain

- **Lockfile integrity:** clean (`lockfile-check.sh` exit 0) — manifests and lockfiles in
  sync across the change set.
- **SBOM:** generated — CycloneDX, **65 components** (`.pipeline/sbom.cdx.json`). The
  deployment gate checks this file exists before allowing a deploy.

## DAST (runtime)

**Advisory — reviewer context, not a pass/fail.** A post-GREEN OWASP ZAP passive-baseline
scan ran against `http://host.docker.internal:8000` (`target_reached: true`, HTTP 200).
Alert tally: **0 high, 3 medium, 4 low, 5 informational**; `over_budget: []` (no severity
band over budget). This is a passive baseline outside the security loop — the pre-merge
scanners (Semgrep/OSV/ast-grep/ASVS SAST) and the human diff review remain the real teeth.
The gating DAST layers run in CI against staging, not in this local run.

## Threat model

See `.pipeline/plan.md`'s `## Threat Model` section (also retained at
`docs/decisions/feature/usage-export/plan.md`) for the full STRIDE table and Mermaid DFD.
No High-severity threat: all rows are rated Medium or Low. The highest-attention row is
**Tampering (CSV -> spreadsheet)** — a malicious ingested identifier with a leading
`= + - @ \t \r` (the ingest allowlist permits a leading `-`) could become a live formula
when the export is opened downstream in Excel/Sheets; mitigated by `escape_csv_text_cell`
at the encoding sink, independent of upstream ingest validation, plus
`Content-Disposition: attachment` + `nosniff` so browsers download rather than render.
