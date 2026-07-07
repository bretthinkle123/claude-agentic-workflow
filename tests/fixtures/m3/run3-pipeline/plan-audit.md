---
audited_at: 2026-07-07T01:54:42Z
plan_sha256: ec060c4f41aa2cf55faf610f07e2d74def1009b7cb120fe55b480cca52457b04
flags_total: 6
material_flags: 3
critical_flags: 0
revision_recommended: true
dependencies_checked: 2
dependencies_unverified: 0
---

# Plan audit — Meterly feature 3 (Usage Dashboard)

Audited: `.pipeline/plan.md` (sha256 `ec060c4f41aa2cf55faf610f07e2d74def1009b7cb120fe55b480cca52457b04`),
`.pipeline/acceptance.md`, `PROJECT.md`, `.pipeline/design-spec.md`, `.pipeline/design-approved`
(hash-matched), and `pyproject.toml` (no manifest change on this branch).

## Focus here first

- **[material]** The plan needs an AWS Secrets Manager secret + a new ECS task-role IAM grant
  (the I-D1 mitigation depends on it) but there is no `## Infrastructure` layer section and no
  `infra/*.tf` entries in **Files affected** — only a prose paragraph deferring the change to
  "after plan approval." The IaC agent has nothing concrete to act on.
- **[material]** `AC16`'s gated perf budget (`GET /dashboard/api/usage-series p95 < 200 ms`) is
  qualified only by "a modest dashboard concurrency" — no concrete req/s or concurrent-request
  number, unlike feature 1's explicit `500 req/s sustained`. Testing cannot build a deterministic
  k6 scenario from this.
- **[material]** Safe-error handling (a forced BFF internal error returns the generic envelope,
  fails closed) is described only in Test-strategy prose, not as a numbered criterion in
  `acceptance.md` — it will not be tracked by the criteria-coverage gate.
- **[advisory]** Proposed dev dependency `pytest-playwright==0.7.0` is ~18 months stale (latest
  `0.8.0`, released 2026-05-18, ~49 days old — past cooldown and the better pin).
- **[advisory]** Proposed transitive `playwright==1.49.*` is a non-exact (wildcard) pin and is 12
  minor releases behind latest (`1.61.0`) — violates the exact-pin determinism rule. Both dep flags
  are contingent on Q4 confirmation, so low urgency, but should be corrected if Q4 is accepted.
- **[advisory]** The loading-skeleton spec says "N greyed `CMP-7` rows" — the row count `N` is
  left as a variable, not a number (contrast with the populated table's fixed 10 rows).

No concerns on the three things flagged for hard scrutiny: no new **runtime** dependency is
introduced (verified against `pyproject.toml` — nothing added, page served via FastAPI's built-in
`FileResponse`), no migration is introduced; the browser-key-avoidance design is genuinely
server-side (reader key resolved via `get_secret`/`verify_api_key` in-process, memoized, and AC9
explicitly asserts no `mtr_live`/`Authorization` value ever reaches the browser or served assets);
and Q1 (month exceeds the 90-day lookback) is surfaced as a real open decision with three concrete
alternatives and a recommendation, not silently resolved by degrading correctness.

## Completeness

| Dimension | Status | Missing item | Blocks which agent | material/advisory |
|---|---|---|---|---|
| Layer sections present | gap | No `## Infrastructure` section / no `infra/*.tf` files for the new Secrets Manager secret + IAM grant (only narrative in the Auth section) | IaC / infra agent | **material** |
| Acceptance criteria traced | ✓ | Every `PROJECT.md`/design-spec item traces to an AC1–AC23 row | — | — |
| STRIDE mechanisms named | ✓ | Every T-D/I-D/S-D/D-D row names a concrete file + mechanism | — | — |
| Input-surface controls | ✓ | One untrusted source (`usage-series` query string); AC11 validation + AC12 rate-limit both present; Tier-1 IP-keyed correctly (no false "per-owner" claim, consistent with `api-edge-conventions`) | — | — |
| Data-protection | ✓ | No new stored field; `data_protection_waiver` recorded (AC19) with a per-field classification table | — | — |
| Object-level authorization | ✓ (adapted) | No client principal exists at the viewer boundary (Q2 accepted risk), so a classic cross-owner-denial test doesn't literally apply; AC10's cross-tenant isolation test is the correct analog and is present | — | — |
| Authentication boundary tested | n/a | Dashboard/BFF are deliberately unauthenticated by design (Q2), so T2-1 does not trigger | — | — |
| Safe-error handling tested | gap | "Forced internal error → generic envelope, fail closed" appears only in Test-strategy prose, not as a numbered `acceptance.md` criterion | testing / criteria-coverage gate | **material** |
| Security-property tests (T2-3…T2-6) | n/a | No self-contained tokens, no session mgmt, no multi-write ledger op, no password path — correctly none triggered | — | — |
| App-store criteria | n/a | Web-only, no store target declared | — | — |
| DAST readiness | ✓ | AC17 (schema parity + reachable headers) / AC18 (auth-context doc) present | — | — |
| ASVS Compliance block | ✓ | Present, triggered chapters + L3 scope + waivers all listed | — | — |
| Test strategy declared | ✓ | `pyramid`, rationale given | — | — |
| Files affected concrete | gap (partial) | App files are concrete with reasons; infra files are absent (same underlying gap as the Infrastructure row above — not double-counted) | infra agent | (see above) |

## Ambiguities

| Section | Quoted text | Downstream risk | Clarifying question | material/advisory |
|---|---|---|---|---|
| Performance budget / AC16 | "under a modest dashboard concurrency" | Testing has no concrete concurrency/req-s figure to script into k6, unlike feature 1's explicit `500 req/s`; two implementers could pick very different loads and both "pass" | What concurrent-request level (or req/s) should the k6 scenario hold while measuring the 200 ms p95? | **material** |
| Frontend / Render states | "a greyed `CMP-5` block + N greyed `CMP-7` rows" | Implementer must guess how many skeleton rows to render (10, to match the populated table? fewer?) | Should the loading skeleton show exactly 10 placeholder rows to match the populated table, or a different fixed count? | advisory |

No unresolved `TODO`/`TBD`/placeholder markers, and no internal contradictions, were found in the
plan body.

## Dependency reality

| Package | Ecosystem | Exists? | Latest stable | Typosquat note |
|---|---|---|---|---|
| pytest-playwright | PyPI | ✓ yes (200) | 0.8.0 | none — well-known package, correct name |
| playwright | PyPI | ✓ yes (200) | 1.61.0 | none — well-known package, correct name |

Both are **proposed, not committed** dependencies (contingent on Q4 at the checkpoint; the plan
explicitly offers a zero-dep fallback). No new **runtime** dependency is introduced — verified
against the current `pyproject.toml`, which is unchanged by this plan.

## Version policy

| Package | Planned version | Age (days) | License | Verdict | Recommended version |
|---|---|---|---|---|---|
| pytest-playwright | 0.7.0 (exact pin) | ~522 days (uploaded 2025-01-31) | Apache-2.0 (permissive ✓) | ✗ too stale — several releases behind latest (0.7.1, 0.7.2, 0.8.0 all shipped since); 0.8.0 itself is ~49 days old (past cooldown) | **0.8.0** |
| playwright | 1.49.* (wildcard, not exact) | n/a (range, not a pinned version) | not stated in registry metadata (upstream project is Apache-2.0; no license-compatibility concern) | ✗ two violations — (1) not an exact pin (determinism rule), (2) 12 minor releases behind latest 1.61.0 | **1.61.0** (or the newest stable ≥14 days old at implementation time), pinned exactly |

Both verdicts are **advisory** (the dependency is proposed/contingent, not committed, and a stale
or wildcard pin does not block correct implementation — it would just need correcting before
`poetry.lock` is generated if Q4 is accepted).

## Could not verify

None — both registry lookups succeeded.
