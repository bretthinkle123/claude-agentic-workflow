# Add `GET /v1/usage/daily` — per-metric daily usage summary

> Written to `.pipeline/pr-description.md` per the deployment gate's requirement
> that this file exist.

## Summary

Adds a read-only, customer-scoped endpoint `GET /v1/usage/daily?date=YYYY-MM-DD`
that returns the authenticated tenant's per-metric event counts for one UTC
day, aggregated from the pre-computed `usage_rollup` counters (not a
`COUNT(*)` scan of raw `events`) — the same "read the rollup" discipline
`GET /v1/usage` already follows. Delivered as a new sibling module trio
(`src/api/schemas/usage_daily.py`, `src/services/usage_daily_service.py`,
`src/api/routes/usage_daily.py`) plus one additive repository function
(`usage_repo.aggregate_daily_event_counts`) and one `include_router` line in
`src/main.py`, so every existing endpoint's code path is untouched — see the
threat model and full design rationale in `.pipeline/plan.md`.

During implementation, security review surfaced and the debugging agent fixed
a pre-existing critical unrelated to the new read path itself: see
**Sanctioned migration deviation** below.

## Changes

- **Schema** (`src/api/schemas/usage_daily.py`): `DailyUsageQueryParams`
  (`date: str | None`, `extra="forbid"`), `parse_daily_date` (imperative
  400-on-invalid validation — missing, malformed, non-calendar, or outside
  `[today_utc-90d, today_utc+1d]`), `day_window_for` (pure half-open
  `[day_start, day_end)` UTC window arithmetic), `DailyUsageResponse` /
  `DailyMetricCount`.
- **Service** (`src/services/usage_daily_service.py`): `get_daily_usage`
  validates the date, reads inside a `scoped_transaction`, logs
  `usage.daily.read` (no `customer_id` in the log), returns `metrics: []`
  (never 404) for an empty day.
- **Route** (`src/api/routes/usage_daily.py`): `GET /v1/usage/daily`, auth ->
  Tier-2 throttle (own sibling `_require_authenticated_and_throttled`, same
  pattern as `usage.py`/`usage_export.py`) — customer-scoped, **not**
  admin-gated (any authenticated key may read its own summary).
- **Repository** (`src/repositories/usage_repo.py`, additive): new
  `aggregate_daily_event_counts(session, *, api_key_id, day_start, day_end)`
  — `SELECT metric, SUM(event_count) ... GROUP BY metric ORDER BY metric ASC`,
  scoped by `api_key_id` first (same IDOR/BOLA invariant as every other query
  in this file), plus the `DailyMetricCount` dataclass it returns.
- **Mount** (`src/main.py`, additive): one import + one
  `app.include_router(usage_daily_router)` line.
- **Security remediation** (see disclosure below): `alembic/versions/0004_force_rls_usage_rollup.py`,
  `tests/integration/test_usage_rollup_rls_backstop.py`.
- **Docs**: READMEs for `src/api/routes/`, `src/api/schemas/` (new),
  `src/services/`, `src/repositories/`, `alembic/`, `tests/`,
  `tests/integration/` (updated); `docs/system_architecture.md` gained a new
  `GET /v1/usage/daily` request-flow section, a Mermaid diagram edge, and a
  `usage_rollup` data-model note for migration `0004`.

## Disclosures (please read before approving)

### 1. Sanctioned migration deviation

The plan declared **"no new migration."** During security review, the
debugging agent's remediation added migration `0004_force_rls_usage_rollup.py`
to fix a **pre-existing critical**: migration `0002` created `usage_rollup`
with `ENABLE ROW LEVEL SECURITY` but not `FORCE`. The app connects as the
table **owner** `meterly_app`, and a PostgreSQL table owner **bypasses**
non-`FORCE` RLS regardless of `NOBYPASSRLS` — so the `usage_rollup_tenant_isolation`
policy (a named defense-in-depth backstop) was inert for the app role. This
was a real gap the new `GET /v1/usage/daily` read path would have exposed
(the app-level `api_key_id` filter was still the sole effective isolation
control), so the remediation was scoped into this feature rather than
deferred.

`0004` is **behavior-preserving**: it applies `ALTER TABLE usage_rollup FORCE
ROW LEVEL SECURITY` (a pure grant-semantics toggle, no DDL on rows/columns).
Every runtime reader/writer of `usage_rollup` — `usage_daily`, `usage_export`,
`GET /v1/usage`, the quota `read_tenant_quota_state_locked` read, and the
`POST /v1/events` rollup increment — already runs inside `scoped_transaction`,
which issues `SET LOCAL app.current_api_key_id`; under `FORCE` each still sees
exactly the rows the application `api_key_id` predicate already returns. It
mirrors migration `0003`, which already applied `FORCE` to `quotas` for the
same owner-bypass reason. `test_usage_rollup_rls_backstop.py` proves the fix
is genuinely effective, not merely present: it connects as a non-superuser
**table owner** (the only role class whose RLS visibility actually flips on
`FORCE`), removes the app-level `api_key_id` predicate entirely, and asserts
the owner is still confined to its own tenant's rows — falsified against a
temporarily-reverted `0004` this session (both new tests went RED without the
fix, GREEN with it restored).

### 2. Modified existing test

`tests/integration/test_quotas_list_delete.py::test_no_new_alembic_migration_added`
(a quota-admin AC14 guard) was updated to permit exactly the one sanctioned
`0004` file, while preserving its real intent: it now inspects `0004`'s
actual DDL targets (`ALTER TABLE (\w+)`) and asserts they are `{"usage_rollup"}`
only, and that `0004` creates no table — so the guard still fails if any
future migration smuggles a `quotas` schema change into this feature's story.

### 3. DAST (Layer 1): effectively skipped — not representative

This run's DAST capture **could not bring the app up** in this environment (a
WSL<->Windows localhost boot limitation — `dast-server.log` shows the capture
script failing to exec the configured `.venv/Scripts/python.exe` path, which
does not exist under WSL). No DAST-clean verdict is being reported for this
feature. `.pipeline/dast-review.json` present in this pipeline run reflects
**stale data from a prior feature's capture** (`dast-capture.json` is dated
2026-07-10, a day before this feature's security/test runs) — it is **not**
a scan of the `usage-daily` change set and must not be read as one. The
gating DAST layers run in CI against staging, not in this local run.

### 4. Pre-existing out-of-scope item

The `events` table (migration `0001`) carries the same non-`FORCE`-RLS gap
that was just fixed for `usage_rollup` — `meterly_app` owns `events` too, so
`events_tenant_isolation` is equally inert for the app role there. This was
**deliberately left out of this feature's scope** (it's not on the
`usage-daily` read path) and is tracked for the finding ledger as a follow-up.

## Decisions & tradeoffs

- **400, not 422, for a malformed/missing `date`.** The brief pins HTTP 400,
  whereas the codebase's other query schemas surface validation failures as
  422. `date` is bound as a loose `str | None` and validated imperatively by
  `parse_daily_date`, which raises `HTTPException(400)` directly; an
  *undeclared* query param still rides the house 422 path via `extra="forbid"`.
- **Aggregate the rollup, not `events`.** Keeps the per-request cost bounded
  as ingest volume grows, matching `GET /v1/usage`'s existing design.
- **Own sibling module, not added to `usage.py`.** Makes the no-behavior-change
  claim for `GET /v1/usage` auditable by inspection of the diff rather than by
  reasoning about a shared file (mirrors `usage_export.py`'s precedent).

## Testing

- **255/255 passed, 0 failed** (259 collected; 4 skipped — 3 k6-load
  self-skips, `rc=255` in this environment, and 1 pre-existing perf test
  deselected via `-m 'not perf'`, unrelated to this diff). `tested_change_hash`
  in `.pipeline/test-results.json`: `046a6ed10e5aa5b91bb0ac5a7377a56444d0411c7e13a174b1d2ed07f2b012cf`.
- **Acceptance criteria: 15 test-covered + 0 delegated to security** (all 15
  of `AC1`-`AC15` are directly test-verified per `test-results.json`'s
  `criteria_covered.by_id`; none carry `delegated: "security"`).
- **Coverage (combined, `--cov-branch`):** lines 91.94%, **branches 93.59%**
  — above the 85% `--cov-fail-under` gate. This feature's three new modules
  (`schemas/usage_daily.py`, `routes/usage_daily.py`,
  `services/usage_daily_service.py`) are 100% line-covered; the touched
  `usage_repo.py` sits at 89% overall (the new `aggregate_daily_event_counts`
  function's every branch is exercised — the miss is pre-existing
  `usage`/`usage_export` lines untouched by this diff).
- **Pyramid shape:** `test_strategy: pyramid`. New tests this feature: 25
  unit (`tests/test_schemas_usage_daily.py` — `parse_daily_date`/
  `day_window_for`/schema validation, incl. a 10-case parametrized
  malformed-date sweep) + 17 integration (15 in
  `tests/integration/test_usage_daily_endpoint.py` covering AC1-AC15
  end-to-end, plus 2 in `test_usage_rollup_rls_backstop.py` for the RLS
  backstop, AC7).
- **Test quality (advisory) — not applicable to this feature's own modules.**
  `.pipeline/test-quality.json` exists but is **stale relative to this diff**:
  it's dated 2026-07-10 (a day before this feature's security/test runs) and
  its `mutation.configured_scope` targets the **quota-admin** modules
  (`quotas_repo.py`, `quota_service.py`, `routes/quotas.py`,
  `schemas/quotas.py`), not this feature's core modules (`schemas/usage_daily.py`,
  `services/usage_daily_service.py`, `routes/usage_daily.py`, or the new
  `aggregate_daily_event_counts` in `usage_repo.py`). No mutation score or
  adversarial-gap data has actually been collected for `usage-daily`'s own
  code — flagging this rather than presenting the quota-admin figures as if
  they applied here. (For context, that stale run itself reports
  `quality_ok: false` — mutmut can't run natively on Windows — plus five
  low/medium adversarial gaps scoped to the quota endpoints.)

## Security

- Scope: diff since `791a37c`, re-scanned after the RLS remediation.
  **Status: clean** — 0 critical, 0 warning, `stride_new_threats: 0`,
  `stride_mechanisms_verified: 8/8`. Semgrep 8 findings, all triaged false
  positives (test-only DDL role/table-identifier interpolation, unparameterizable
  by construction, never reachable from request input). OSV 0 unfiltered
  findings (no new dependency). See `.pipeline/security-report.md` for the
  full findings inventory and ASVS reconciliation (`V1, V2, V4, V6, V8, V11,
  V13, V16` triggered, all L1+L2 universal verified).
- Threat model: see the `## Threat Model` section of `.pipeline/plan.md` —
  Spoofing/Tampering/Information-Disclosure/DoS/EoP rows, all High-severity
  threats mitigated (auth-before-data, bound-parameter SQL + anchored `date`
  allowlist, `api_key_id`-only scoping with no IDOR parameter, dual-layer RLS
  + app-level scoping for cross-tenant reads, fail-closed generic-500 error
  envelope, Tier-1/Tier-2 throttling).

## Supply chain

- **Lockfile integrity:** clean (exit 0) — no manifest/lockfile drift, no
  unpinned specifiers (`lockfile-check`, `.pipeline/security-report.md`).
- **SBOM:** `.pipeline/sbom.cdx.json` is present (CycloneDX 1.7, Trivy
  0.71.2, 65 components) but, like the DAST artifact above, its
  `metadata.timestamp` (2026-07-10T02:33Z) predates this feature's
  security/test runs and Trivy was explicitly **not** re-run this pass
  (`security-report.md`: "carried forward / skipped — no dependency change
  this pass"). No dependency changed in this diff (OSV confirms 0 new
  findings against the current `poetry.lock`), so the component set is
  expected to be current, but the SBOM file itself was not freshly generated
  for this diff — noting for the deployment gate's file-existence check.

## Design-record retention

Copied this run's plan, acceptance criteria, plan-audit, security report, and
run-summary into `docs/decisions/feature/usage-daily/` (no `design-spec.md`
this run — `CLAUDE.md` declares "Design source: none (API only)"). Evidence
for humans/audits; no gate reads it.
