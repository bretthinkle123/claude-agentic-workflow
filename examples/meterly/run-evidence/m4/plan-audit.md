---
audited_at: 2026-07-08T00:00:00Z
plan_sha256: 1e74fdb8ce7250cc09861ea670fc961675aa89ba6c182b67e087d109ee02a873
flags_total: 2
material_flags: 0
critical_flags: 0
revision_recommended: false
dependencies_checked: 0
dependencies_unverified: 0
---

# Plan audit — per-customer metric quotas

## Focus here first

- No blocking concerns — plan reads clean against completeness, ambiguity, proof-claim, and
  cross-feature-trace dimensions; `revision_recommended: false`.
- [advisory] Lock-ordering/no-deadlock claim ("event → quota → rollup, so no lock cycle can form",
  Backend § *Enabling conditions*) has no dedicated deadlock/timeout test — it's argued structurally
  (single code path always acquires locks in the same order), which is reasonable, but nothing would
  fail if a future edit reordered the acquisitions. Worth a one-line note in `test_quota_concurrency.py`
  tying the ordering assertion to the lock sequence, not a blocker.
- [advisory] Open Question 3 (admin = ingest superset, single-key-per-tenant) is a real product
  constraint the plan flags honestly rather than hides — worth the human's explicit sign-off at the
  checkpoint even though the plan already proposes a sound default.

## Completeness

| Dimension | Status | Missing item | Blocks which agent | material/advisory |
|---|---|---|---|---|
| Layer sections present | ✓ | — (Frontend explicitly n/a: "no UI to build", backend-only feature) | — | — |
| Acceptance criteria traced | ✓ | All 15 Resolved requirements items map to a plan section; the 1 Open item (PUT latency budget) carries a proposed default; `acceptance.md` lists all 22 ACs with file/layer + verification | — | — |
| Task decomposition (tasks.md, TA/A-3 triggered: 22 ACs, ~26 files) | ✓ | Union of T1–T6 `ACs advanced` covers AC1–AC21; AC22 correctly excluded (delegated to security per `acceptance.md` header); every `depends_on` (T2→T1; T3→T1,T2; T4→T1,T3; T5→T4; T6→T3,T4) references an existing task ID; every task traces to a named plan section | — | — |
| STRIDE mechanisms named | ✓ | Every threat row names a concrete mechanism + file (e.g. `SELECT … FOR UPDATE OF q` in `quotas_repo.py`, `ConfigDict(extra='forbid')` in `quotas.py`) | — | — |
| Input-surface controls complete | ✓ | Both new inputs (PUT body, reused Authorization header) and the extended-behavior input (POST body) enumerated; PUT body carries both a validation criterion (AC5) and a rate-limit criterion (AC15), correctly principal-keyed post-auth Tier-2 (not IP-keyed) | — | — |
| Data-protection complete | ✓ | All 4 new/changed fields classified in a table; none sensitive; explicit `data_protection_waiver` present in `acceptance.md` with reasoning | — | — |
| Object-level authorization tested | ✓ | AC6 asserts a second tenant's key cannot read/affect tenant A's quota (the cross-owner denial shape) | — | — |
| Authentication boundary tested | ✓ | AC4: missing/malformed/revoked auth on `PUT /v1/quotas` → 401 | — | — |
| Safe-error handling tested | ✓ (pre-existing) | An existing forced-internal-error test (`tests/integration/test_events_endpoint.py::test_forced_internal_error_returns_safe_envelope_and_fails_closed`) already exercises the generic-envelope/fail-closed path at the exact callsite (`increment_usage_rollup`) the new quota check sits just upstream of; the plan doesn't need a new one since the facade and callsite are unchanged | — | — |
| Security-property tests (T2-3…T2-6) | ✓ n/a | No self-contained tokens issued/consumed (T2-3 n/a), no sessions (T2-4 n/a), T2-5 (atomic rollback) satisfied by AC9, no password flow (T2-6 n/a) | — | — |
| App-store submission criteria | ✓ n/a | No store target declared in `PROJECT.md`/`CLAUDE.md` | — | — |
| DAST readiness | ✓ | AC21 covers served-OpenAPI presence + seeded admin test key + auth context | — | — |
| ASVS compliance scoped | ✓ | `## ASVS Compliance` block present; triggered chapters listed; L3 explicitly considered (V15.4.x, V11.2.4) with justification; n/a chapters reasoned; no unwaived L1/L2 gap | — | — |
| Test strategy declared | ✓ | `pyramid` (project default) with rationale tying integration tier to Postgres-only guarantees | — | — |
| Files affected concrete | ✓ | Every create/modify entry has a path + one-line reason | — | — |

Completeness is clean — no gaps found.

## Ambiguities

None found. The plan is unusually concrete throughout: every endpoint has method + path + status codes,
every field has a type/bound, the database engine and locking primitive are named, and no `TODO`/`TBD`/
placeholder markers survive in the body. Test strategy is declared and justified.

## Proof-claim verification (U-03)

The plan makes several "cannot happen" / "never exceed" claims (Backend § *The atomic read-and-decide*).
Checked each against enforcement:

| Claim | Invariant | Enforcement point | Verifying test |
|---|---|---|---|
| "usage can never exceed `L`" | `current_total + Q <= L` at commit, for every committed increment | `SELECT … FOR UPDATE OF q` row lock in `read_tenant_quota_state_locked` (`src/repositories/quotas_repo.py`) serializes all writers for a `(customer,metric)`; check + increment share one `scoped_transaction` | AC13 / `test_quota_concurrency.py::test_concurrent_posts_never_exceed_limit` (N concurrent posts, asserts final total `<= L`) |
| "a rejected event leaves no trace" / "no partial write" | event insert and rollup increment commit together or not at all | `AppError` raised before `increment_usage_rollup`, propagating out of `session.begin()` → rollback | AC9 / `test_events_quota_enforcement.py::test_over_limit_429_and_no_partial_write` |
| "replay never consults the quota" | idempotency replay path is disjoint from the quota-check branch | check lives only on the `inserted is not None` branch of `insert_event_if_new`; replay takes the `find_event_by_idempotency_key` branch | AC11 / `test_replay_over_quota_returns_200_no_usage` |
| "no lock cycle can form" (consistent lock order event→quota→rollup) | all concurrent requests acquire locks in the same order | structural: single code path always sequences insert→quota-lock→rollup-upsert (no test needed if the code path is truly singular) | none dedicated — **advisory**, see Focus-here-first |

All four claims name an invariant and an enforcement point; three of four have a dedicated test. The
fourth is a structural (single-code-path) argument rather than a race, so its absence of a test is
advisory, not material.

## Cross-feature data-flow trace (U-03)

The quota check reads `usage_rollup`, a table written by feature 1 (`POST /v1/events` ingestion). Traced
the join key end-to-end: `usage_rollup` rows are written keyed by the ingesting key's `api_key_id`
(feature 1), and the quota check reads that same table filtered on the **same authenticated principal's**
`api_key_id` (this feature explicitly models admin as an ingest-superset scope so the two keys are one
key). No reader/writer principal mismatch — this avoids feature 3's blind spot (a reader key that could
never own the rows it needs). No flag.

## Dependency reality

No new dependencies. Confirmed by reading `pyproject.toml`: every package the plan relies on
(SQLAlchemy, Alembic, Pydantic/FastAPI, structlog, argon2-cffi, asyncpg) is already pinned there at a
fixed version, and `git diff HEAD -- pyproject.toml poetry.lock` shows no change. `dependency-audit-policy`
skill not invoked (not triggered).

## Version policy

No new dependencies — not applicable.

## Could not verify

None — no dependency lookups were required.
