---
audited_at: 2026-07-06T17:17:10Z
plan_sha256: 1a6b6bb9e9b39ee9661185b930dbe7f7ff014e7ab919c6ec570f67c8881c327d
flags_total: 7
material_flags: 0
critical_flags: 0
revision_recommended: false
dependencies_checked: 22
dependencies_unverified: 0
---

# Plan audit — Meterly: metered-event ingestion + usage query

Audited `.pipeline/plan.md` (sha256 `1a6b6bb9…881c327d`) against `PROJECT.md`, `CLAUDE.md`, and
`.pipeline/acceptance.md`. This is a greenfield repo — no `pyproject.toml`/lockfile exists yet, so
every package in the plan's "New third-party dependencies" table is new supply-chain surface and
was run through the `dependency-audit-policy` registry + version checks.

## Focus here first

No material or critical concerns. This is an unusually thorough plan — every mandated
non-functional signal (AC-PERF, AC-CONCURRENCY, AC-DATA-PROTECTION, AC-MIGRATION, AC-SLO) is traced
into `.pipeline/acceptance.md` with a concrete verification method, every STRIDE threat carries a
named mechanism + file, both input surfaces carry validation + correctly principal-keyed
(post-auth, `api_key_id`) rate-limit criteria, the one stored personal field is classified with a
named at-rest control, IDOR/cross-owner denial and unauthenticated-denial criteria are both
present, DAST-readiness (schema + seeded test user + auth context) is covered, and the ASVS
Compliance block scopes L3 and states reasoned waivers. All 22 new dependencies exist on PyPI
(no slopsquat risk) and are exact-pinned. **`revision_recommended: false`.**

Advisory items only, ordered by how much attention they're worth:

- [advisory] Five new dependencies are pinned more than one major version behind current stable
  (`gunicorn`, `argon2-cffi`, `redis`, `structlog`, and `pytest-asyncio`'s pre-1.0 pin) — see
  **Version policy** below. None are EOL or security-flagged; worth a quick human glance, especially
  `redis` (5.2.1 vs latest 8.0.1 — a 3-major gap on the client the Tier-1/Tier-2 token-bucket Lua
  script depends on) and `pytest-asyncio` (0.25.0 predates the 1.0 default-execution-mode change).
- [advisory] Tier-1 pre-auth rate-limit threshold (IP+route-keyed) has no stated numeric limit —
  only Tier-2 (`rate_limit_per_sec`, per key) is quantified. Implementation will have to pick a
  Tier-1 number without plan guidance.
- [advisory] The in-process auth-verification cache TTL is given as "~5 min" (approximate) rather
  than an exact value; implementation needs one concrete number.

## Completeness

Complete — all applicable sections present, and the five mandated `PROJECT.md` acceptance IDs
(AC-PERF, AC-CONCURRENCY, AC-DATA-PROTECTION, AC-MIGRATION, AC-SLO) are each traced to a named plan
section and to specific `acceptance.md` rows.

| Dimension | Status | Missing item | Blocks which agent | material/advisory |
|---|---|---|---|---|
| Layer sections present | ✓ | — (Frontend correctly marked N/A: "Design source: none") | — | — |
| Mandated AC-IDs traced (AC-PERF/CONCURRENCY/DATA-PROTECTION/MIGRATION/SLO) | ✓ | — (→ AC6, AC7, AC8+AC9, AC10+AC11, AC12) | — | — |
| `.pipeline/acceptance.md` exists, lists file/layer + verification per criterion | ✓ | — | — | — |
| STRIDE mechanisms named (concrete lib call/config/file) | ✓ | — (S1–E3, each with a file) | — | — |
| Input-surface validation + rate-limit per source | ✓ | — (POST /v1/events: AC13/AC14; GET /v1/usage: AC15/AC16), rate limit correctly principal-keyed post-auth (`api_key_id`), not IP | — | — |
| Data-protection classification + mechanism/waiver per stored field | ✓ | — (`secret_hash`→Argon2id/AC8; `customer_id`→SSE/AC9; rest non-sensitive) | — | — |
| Object-level authorization (cross-owner denial) | ✓ | — (AC17, read + write path) | — | — |
| Authentication boundary (unauthenticated denial) | ✓ | — (AC18) | — | — |
| Safe-error handling | ✓ | — (AC19, generic envelope + fail-closed) | — | — |
| Security-property tests (T2-3…T2-6) | ✓ | N/A — no JWT/session/password surface; T2-5 atomic-rollback covered by AC19's fail-closed transaction | — | — |
| App-store submission criteria | ✓ | N/A — no store target (`Design source: none (API only)`) | — | — |
| DAST readiness | ✓ | — (AC22 schema, AC23 seeded key, AC24 auth context) | — | — |
| ASVS Compliance block | ✓ | — (triggered chapters, L3 in-scope items, reasoned L1/L2 waivers) | — | — |
| Test strategy declared + justified | ✓ | — (`pyramid`, rationale given) | — | — |
| Files affected concrete | ✓ | — (paths + one-line reason each) | — | — |

## Ambiguities

| Section | Quoted text | Downstream risk | Clarifying question | material/advisory |
|---|---|---|---|---|
| Auth — Per-key rate limiting, Tier 1 | "a coarser Redis token bucket to shed unauthenticated floods" | Implementation must invent a numeric IP+route limit with no plan-stated budget; testing has no target value to assert against | What is the Tier-1 (pre-auth, IP+route) requests/sec limit? | advisory |
| Auth — Key format and verification | "an in-process verification cache (`src/auth`, **TTL ~5 min**)" | "~5 min" is approximate; implementation needs one exact constant (e.g. 300s) and the revocation-latency SLA (Q4) implicitly depends on this exact number | Confirm the exact cache TTL in seconds (e.g. 300) rather than "~5 min" | advisory |

## Dependency reality

All 22 packages the plan introduces (16 runtime + 6 dev) were verified to exist on PyPI via
`https://pypi.org/pypi/<pkg>/json` (HTTP 200 for every one — no 404s, no slopsquat risk).

| Package | Ecosystem | Exists? | Latest stable | Typosquat note |
|---|---|---|---|---|
| fastapi | PyPI | ✓ | 0.139.0 | none — expected package |
| uvicorn[standard] | PyPI | ✓ | 0.50.2 | none |
| gunicorn | PyPI | ✓ | 26.0.0 | none |
| pydantic | PyPI | ✓ | 2.13.4 | none |
| pydantic-settings | PyPI | ✓ | 2.14.2 | none |
| sqlalchemy | PyPI | ✓ | 2.0.51 | none |
| asyncpg | PyPI | ✓ | 0.31.0 | none |
| alembic | PyPI | ✓ | 1.18.5 | none |
| argon2-cffi | PyPI | ✓ | 25.1.0 | none |
| redis | PyPI | ✓ | 8.0.1 | none |
| structlog | PyPI | ✓ | 26.1.0 | none |
| sentry-sdk | PyPI | ✓ | 2.64.0 | none |
| opentelemetry-sdk | PyPI | ✓ | 1.43.0 | none |
| opentelemetry-instrumentation-fastapi | PyPI | ✓ | 0.64b0 | none — beta-tracks otel-sdk minor, expected |
| opentelemetry-exporter-otlp | PyPI | ✓ | 1.43.0 | none |
| boto3 | PyPI | ✓ | 1.43.40 | none |
| pytest (dev) | PyPI | ✓ | 9.1.1 | none |
| pytest-asyncio (dev) | PyPI | ✓ | 1.4.0 | none |
| pytest-cov (dev) | PyPI | ✓ | 7.1.0 | none |
| httpx (dev) | PyPI | ✓ | 0.28.1 | none |
| testcontainers[postgres] (dev) | PyPI | ✓ | 4.14.2 | none |
| hypothesis (dev) | PyPI | ✓ | 6.156.1 | none |

## Version policy

All 22 pins are **exact** (deterministic — no ranges/wildcards, satisfies rule 3). All pinned
versions are **≥550 days old**, well past the 14–30/30–90-day cooldown window, so none is flagged
as "too fresh." Licenses are all permissive or dual permissive (MIT/BSD/Apache-2.0), except
`hypothesis` (MPL-2.0, weak-copyleft, dev/test-only — not distributed with the shipped
application, so no obligation attaches); none is strong-copyleft or unlicensed. No license flags.

| Package | Planned version | Age (days) | License | Verdict | Recommended version |
|---|---|---|---|---|---|
| fastapi | 0.115.6 | 579 | MIT (known) | ✓ compliant (0.x scheme; not true semver majors) | keep, or bump to a recent 0.13x if desired |
| uvicorn[standard] | 0.34.0 | 567 | BSD-3-Clause (known) | ✓ compliant | keep |
| gunicorn | 23.0.0 | 694 | MIT (known) | ✗ obsolescence — 3 majors behind (23 vs latest 26) | 25.x (n-1) or re-validate 26.0.0 |
| pydantic | 2.10.4 | 564 | MIT (known) | ✓ compliant (same major) | keep |
| pydantic-settings | 2.7.1 | 551 | MIT | ✓ compliant | keep |
| sqlalchemy | 2.0.36 | 628 | MIT | ✓ compliant | keep |
| asyncpg | 0.30.0 | 623 | Apache-2.0 (known) | ✓ compliant | keep |
| alembic | 1.14.0 | 608 | MIT (known) | ✓ compliant | keep |
| argon2-cffi | 23.1.0 | 1055 | MIT (known) | ✗ obsolescence — 2 majors behind (23 vs latest 25) | 24.x |
| redis | 5.2.1 | 576 | MIT | ✗ obsolescence — 3 majors behind (5 vs latest 8); this is the client behind the Tier-1/Tier-2 token-bucket Lua script | 7.x (n-1); verify async API + Lua-script call compatibility before any bump |
| structlog | 24.4.0 | 718 | MIT/Apache-2.0 dual | ✗ obsolescence — 2 majors behind (24 vs latest 26) | 25.x |
| sentry-sdk | 2.19.2 | 576 | MIT (known) | ✓ compliant | keep |
| opentelemetry-sdk | 1.29.0 | 571 | Apache-2.0 (known) | ✓ compliant | keep |
| opentelemetry-instrumentation-fastapi | 0.50b0 | 571 | Apache-2.0 | ✓ compliant (pre-1.0, tracks otel-sdk minor) | keep in lockstep with opentelemetry-sdk |
| opentelemetry-exporter-otlp | 1.29.0 | 571 | Apache-2.0 (known) | ✓ compliant | keep |
| boto3 | 1.35.90 | 554 | Apache-2.0 | ✓ compliant (boto3 stays major=1 by convention) | keep |
| pytest (dev) | 8.3.4 | 581 | MIT (known) | ✓ compliant (1 major behind = n-1) | keep |
| pytest-asyncio (dev) | 0.25.0 | 569 | Apache-2.0 (known) | ✗ obsolescence-adjacent — pinned pre-1.0 while a stable 1.x line exists; 1.0 changed the default execution-mode default | 1.x pin, after confirming `asyncio_mode` config still matches |
| pytest-cov (dev) | 6.0.0 | 614 | MIT | ✓ compliant (1 major behind = n-1) | keep |
| httpx (dev) | 0.28.1 | 576 | BSD-3-Clause | ✓ compliant — matches current latest exactly | keep |
| testcontainers[postgres] (dev) | 4.9.0 | 572 | Apache-2.0 | ✓ compliant | keep |
| hypothesis (dev) | 6.123.2 | 555 | MPL-2.0 (known) | ✓ compliant (same major; weak-copyleft, dev-only) | keep |

## Could not verify

None — every registry lookup succeeded (22/22). Note: PyPI's JSON `classifiers`/`license` field was
empty for several packages (fastapi, uvicorn, gunicorn, pydantic, asyncpg, alembic, argon2-cffi,
sentry-sdk, the three opentelemetry packages, pytest, pytest-asyncio, hypothesis); their licenses
above are recorded from well-established public knowledge of these projects rather than a populated
registry field — the human may want to spot-check if a license audit tool is run later.
