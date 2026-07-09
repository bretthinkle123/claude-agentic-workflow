# Per-customer metric quotas

## Summary

Adds admin-scoped per-customer, per-metric usage caps ("quotas") on top of the existing
ingest/usage API. `PUT /v1/quotas` lets an `admin`-scoped API key create-or-replace a cap
`(customer_id, metric) -> limit_per_window`; `POST /v1/events` now enforces it, atomically,
returning `429 quota_exceeded` when a request would push the current window's rollup total
(`R`) plus the incoming quantity (`Q`) over the limit (`L`). Customers without a quota row
stay unlimited — no behavior change to the first feature's ingest path. One expand-only
migration (`0003`) adds the `quotas` table and an `api_keys.scope` column (`'ingest'`
default, `'admin'` elevated). See the full design and STRIDE threat model in
`.pipeline/plan.md` (now retained at `docs/decisions/feature/metric-quotas/plan.md`).

## Changes

- **API:** `PUT /v1/quotas` (`src/api/routes/quotas.py`, `src/api/schemas/quotas.py`) —
  auth -> Tier-2 per-`api_key_id` throttle -> `admin`-scope gate (403 `forbidden` otherwise)
  -> `quota_service.upsert_tenant_quota`. 201 on create, 200 on replace.
- **Enforcement:** `src/services/events_service.py` + `src/repositories/quotas_repo.py`'s
  `read_tenant_quota_state_locked` — an atomic check-then-decide (`SELECT ... FOR UPDATE`
  on the quota row, then a **separate** fresh read of `usage_rollup`) inside the same
  transaction as the event insert and rollup increment. A rejection rolls back the whole
  transaction (no partial write). Unlimited customers take no lock at all.
- **Auth:** `api_keys.scope` (`src/auth/api_key.py`, `src/repositories/api_keys_repo.py`);
  `scripts/seed_api_key.py --admin` provisions an admin-scoped key (default `'ingest'`).
- **DB:** `alembic/versions/0003_create_quotas_and_api_key_scope.py` — one expand-only
  revision (new `quotas` table + `api_keys.scope` column), `FORCE ROW LEVEL SECURITY` on
  `quotas` from the start.
- **Config:** `src/db/session.py` now pins `isolation_level="READ COMMITTED"` explicitly on
  the async engine — the correctness dependency the lock-then-read quota check relies on
  (see Decisions below).
- **Docs:** updated `README.md`s for `src/api`, `src/auth`, `src/repositories`,
  `src/services`, `src/db`, `alembic`, `scripts`; new `README.md`s for `tests/`,
  `tests/integration/`, `tests/integration/k6/`; `docs/system_architecture.md` gained a
  `PUT /v1/quotas` request-flow section, a "Quota enforcement / atomicity" section, and a
  Mermaid request/data-flow diagram; `CLAUDE.md`/`PROJECT.md` updated for the `scope`
  authorization model.

## Decisions & tradeoffs

- **Two round-trips, not one combined `LEFT JOIN ... FOR UPDATE`.** PostgreSQL's `FOR
  UPDATE` only guarantees a fresh re-check of the *locked* row itself on waiter unblock —
  it does not force a fresh snapshot for a joined table in the same statement. A single
  combined statement was verified (empirically, during implementation) to let every
  concurrent waiter read the same stale rollup total and all get admitted, silently
  breaking the cap. Splitting the lock-acquire and the rollup-read into two statements,
  under an explicit `READ COMMITTED` pin, fixes this — see `src/repositories/quotas_repo.py`
  and the new `tests/test_db_session_isolation.py` regression guard.
- **Admin is a superset scope, not a separate key family**, and **one admin key per tenant**
  is the model this slice ships with — a tenant that wants quotas provisions one
  `admin`-scoped key and uses it for both ingest and administration. This is a known,
  accepted constraint of the current single-key-per-tenant schema (plan.md Open Question 3);
  a multi-key-per-tenant model is out of this slice's scope and would be a larger follow-up
  if that constraint becomes a problem.
- **AC20 (perf) was human-revised mid-run.** The original absolute `p95 < 50ms` budget for
  quota-active `POST /v1/events` proved unachievable on this host at any worker parity, and
  a 3362ms measurement (40x over budget) was root-caused by debugging as a harness artifact
  (a 2-worker quota fixture racing a 5-worker baseline, not a real regression). AC20 was
  revised to a **relative bound**: quota-active p95 <= 1.5x the same-session no-quota
  baseline p95, at equal worker budget. The absolute 50ms figure moves to a post-merge
  CI/staging load-campaign budget, outside this stage's scope. Measured this run: baseline
  p95 = 124.10ms, quota-active p95 = 123.45ms (ratio 0.995x — essentially at parity, well
  inside the 1.5x bound).

## Testing

- **128 / 128 tests pass** (`tests_by_type`: 80 unit, 48 integration, 0 e2e — pyramid
  strategy). Resilience: migration round-trip pass, 1 property-based (Hypothesis) test,
  concurrency pass.
- **Coverage:** 89.9% lines, **58.3% branches** (combined; per-suite unit/integration figures
  not separately recorded this run).
- **Acceptance criteria: 21 test-covered + 1 delegated to security** (22 total, per
  `.pipeline/test-results.json` `criteria_covered.by_id`). The delegated criterion is
  **AC22** (ASVS reconciliation) — it is the security stage's deliverable, not a
  test-suite assertion, not a gap in test coverage.
- **Test quality (advisory, `.pipeline/test-quality.json`):** `quality_ok: false` —
  mutation testing could not run this session (mutmut refuses to run on native Windows and
  no WSL was available in this environment; honestly reported rather than fabricated). A
  manual adversarial review over the changed core modules substitutes: notable gaps include
  the lock-then-read concurrency proof being exercised at only one concurrency point/cap
  value (a regression could reappear and pass intermittently on an idle CI box), no test
  driving two concurrent requests sharing the same `idempotency_key` through the quota
  check, and the `LimitPerWindow` BIGINT-safe upper bound (1e15) not being driven through
  the actual HTTP endpoint into Postgres. None are blocking; all are reviewer context.

## Security

- **Scope:** diff since `faabe9d` (`.pipeline/security-report.md`). **Status: clean.**
  0 critical, 11 warnings (all advisory/non-blocking), 1 fixed, 12 total findings (2 OSV +
  2 manual STRIDE-mechanism notes + 7 Semgrep + 1 manual).
- **Fixed this feature: `quotas` RLS backstop made effective.** The migration originally
  used `ENABLE ROW LEVEL SECURITY` (not `FORCE`) on `quotas`; since the migrating/app role
  owns the table and a table owner bypasses non-`FORCE` RLS, the tenant-isolation policy
  would have been silently inert. `ALTER TABLE quotas FORCE ROW LEVEL SECURITY` closes this,
  and it is now proven (not just declared) by a new adversarial test
  (`tests/integration/test_quotas_rls_backstop.py`) that connects as a real `NOBYPASSRLS`
  role, removes the primary `api_key_id` filter entirely, and asserts the RLS policy alone
  still confines the session to its own tenant — plus fail-closed behavior when the tenant
  context is unset.
- **Follow-up, not fixed here (pre-existing, outside this diff):** `events` and
  `usage_rollup` (migrations `0001`/`0002`) have the same owner-bypass exposure — they use
  `ENABLE` without `FORCE`. Same reasoning as the `quotas` fix applies. Recommend a
  follow-up migration adding `FORCE ROW LEVEL SECURITY` to both, or verifying migrations
  run as a non-owner role. The explicit `api_key_id` predicate remains the effective
  primary control on those tables regardless of this gap.
- **Action required (human decision, not auto-fixed): bump `pytest`.** `pytest@8.3.4`
  carries two dev/test-only findings (GHSA-6w46-j5rx-g56g, PYSEC-2026-1845, CVSS ≈ 6.8
  Medium — tmpdir predictability, not on the request path). Below the deploy gate's
  CVSS >= 7.0 floor, so non-blocking, but recommend bumping to `pytest >= 8.3.5` in
  `pyproject.toml` + `poetry.lock` in a follow-up (dependency bumps are the debugging
  agent's remit, not security's).
- 5 Semgrep `avoid-sqlalchemy-text` ERROR rows are false positives (DDL over an internally
  generated, never-user-controlled role name in the new RLS backstop test and the migration
  test) — triaged in full in the security report. 2 `github-actions-mutable-action-tag`
  WARNINGs (CI workflow) are real but advisory.

## Supply chain

- **Lockfile integrity:** `poetry.lock` in sync with `pyproject.toml` (`lockfile-check.sh`,
  clean, exit 0).
- **SBOM:** a CycloneDX SBOM was generated (`.pipeline/sbom.cdx.json`, Trivy 0.71.2) —
  **65 components**.

## DAST (runtime) — advisory

A ZAP passive-baseline scan ran post-GREEN against `http://host.docker.internal:8000`
(`.pipeline/dast-review.json`). **Target was reached** (`target_reached: true`, HTTP 200),
so this result is informative (not a U-14 non-page-scan case). Tally:
high 0, medium 3, low 4, informational 5 — **all within budget**, no severity band over
its cap. All 6 non-informational alert *types* are hygiene findings against the Swagger
`/docs` page specifically (CSP directive fallback, missing Subresource-Integrity
attributes, cross-domain JS inclusion, and missing `Cross-Origin-{Embedder,Opener,Resource}-Policy`
headers) — not the `/v1/events`/`/v1/usage`/`/v1/quotas` API surface itself. This is a
**passive baseline run post-GREEN, outside the security loop** — advisory reviewer context,
never a pass/fail signal. The gating DAST layers run in CI against staging, not in this run;
the pre-merge scanners (Semgrep/OSV/ASVS-SAST) and human diff review stay the real teeth.

## Threat model

See `.pipeline/plan.md` `## Threat Model` (STRIDE, scoped to this feature). All 10
non-accepted-risk threats have a named, verified mechanism (`stride_mechanisms_verified =
10`, `stride_mechanisms_missing = 0`); 2 accepted-risk rows (quota-data-at-rest, hot-row
serialization latency) are out of scope per protocol. Highest-severity rows: **Spoofing**
(unauthenticated/non-admin caller sets a cap — mitigated by `require_api_key` + the
route's `admin`-scope 403 gate) and **Tampering** (mass-assignment of `api_key_id`/`scope`
via the PUT body — mitigated by `ConfigDict(extra='forbid')` plus the server setting
`api_key_id` from the authenticated principal, never the request body), both High severity,
both with a concrete mechanism verified in code.
