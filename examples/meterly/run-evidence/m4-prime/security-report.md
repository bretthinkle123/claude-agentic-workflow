---
status: clean
ran_at: 2026-07-09T20:10:10Z
scope: diff
since_commit: 43da3203feb5e9be3d7684992b47209188d328b0
critical_count: 0
warning_count: 4
fixed_count: 0
total_findings: 7
semgrep_findings: 4
osv_findings: 2
checkov_findings: 0
trivy_findings: 0
stride_mechanisms_verified: 8
stride_mechanisms_missing: 0
stride_new_threats: 0
---

# Security report — usage CSV export (`GET /v1/usage/export`)

**Verdict: clean.** No critical findings remain. The change set adds one read-only
streaming CSV endpoint over the existing `usage_rollup` table plus its schema, service,
repository queries, CSV-encoding facade, and tests. Every planned STRIDE mitigation is
present *and* effective (per-mechanism efficacy checked, not just presence); the two
Semgrep ERROR hits are verified false positives (fully parameterized queries); the one OSV
CVE is a dev-only, below-floor moderate; and no new attack surface escaped the threat model.

**Remediation re-run (cycle 2).** Since the clean cycle-1 scan the diff gained only the AC16
performance fix — the CSV escape's `str.translate` deletion table (`src/api/csv_export.py`,
replacing a per-character generator), batched `_ROWS_PER_CHUNK` chunking of the streaming
generator (`src/services/usage_export_service.py`), and a `yield_per` server-side-cursor tuning
option (`src/repositories/usage_repo.py`) — plus a chunk-count regression test, two testing-added
tests, a `--cov-fail-under=85` fill in `.github/workflows/pipeline-ci.yml`, and a human-confirmed
AC16 revision in `.pipeline/acceptance.md`. **The perf fix preserves every security invariant**:
the `str.translate` table is byte-for-byte semantically identical to the prior `_is_safe_character`
filter (same C0 controls except tab/CR/LF plus DEL stripped, same leading-formula-trigger quoting);
`yield_per` only tunes cursor batch size (constant-memory streaming and the fixed-literal
`ORDER BY`/`WHERE` unchanged, values still bound); chunking changes *when* bytes are handed to the
ASGI stack, not *what* is encoded. Findings are identical to cycle-1 (the Semgrep hit's line moved
161→175 as `execution_options(...)` was appended). **This pass, ast-grep (0.44.1, now installed) ran
its structural SQL/async pass** — the disclosed skip from cycle-1 is closed.

## Tools run

| Tool | Scope | Result |
|---|---|---|
| Semgrep (`auto`, `p/secrets`, `p/owasp-top-ten`, `p/python`) | 12 code-shaped changed files (6 src + 5 tests + CI workflow) | 2 ERROR (verified false positives) + 2 WARNING (pre-existing mutable action-tag) |
| OSV Scanner | full manifest (`.`) | 1 unique CVE (2 aliased ids) — pytest, dev dep, moderate (artifact byte-identical to cycle-1) |
| Gitleaks (`dir`) | full tree | 127 raw hits — all `.venv/` dependency data or test fixtures (out of scope / FP) |
| ast-grep 0.44.1 structural rules | SQL/async changed files | **RAN** — 2 `text()`+f-string leads (both verified-safe, = the Semgrep FPs); 0 KDF-on-event-loop in scope. Advisory-only |
| ASVS Tier-1 SAST (`asvs-sast.sh`) | diff | 0 critical, 0 warning |
| Lockfile / supply-chain (`lockfile-check.sh`) | change set | clean (exit 0) |
| SBOM (`generate-sbom.sh`) | project | present — CycloneDX, 65 components |
| Checkov / Trivy | n/a | no `infra/` dir and no Dockerfile/image in the change set — not applicable |

**ast-grep structural pass (F-M4-5 — disclosed skip now closed):** ast-grep 0.44.1 is now on
PATH, so the `ast-grep-rules` structural pass ran over the SQL- and async-touching changed files
(stamped in `.pipeline/scan-log.jsonl`; three execution rows this pass). Two rules were applied:
(1) a `text()`-built-from-f-string SQL-injection lead — **hit twice**, `usage_repo.py:129` and
`usage_repo.py:175`, exactly the two sites Semgrep flags; both investigated and confirmed safe (the
interpolated `where_clause` is assembled only from fixed string literals in
`_export_filter_clause_and_params`, every filter *value* bound as a parameter — no injection vector).
(2) a KDF/blocking-call-on-the-event-loop lead — **no hit in the change set**; the only tree-wide hit
is `src/crypto/__init__.py:53` (`hashlib.sha256` token-index hashing, pre-existing, outside the diff,
not a password KDF). The export path performs no KDF and uses only `await`-ed async DB calls. Per the
skill's hard boundary, **ast-grep findings are advisory** — they inform this prose only and feed no
`security-status.json` count, `scan_artifacts` entry, or gate/loop-exit conjunct.

## Complete findings inventory

| # | source | id | severity | exploitable | location | disposition |
|---|---|---|---|---|---|---|
| 1 | semgrep | `python.sqlalchemy.security.audit.avoid-sqlalchemy-text` | ERROR | no | `src/repositories/usage_repo.py:129` | reported-only (verified false positive) |
| 2 | semgrep | `python.sqlalchemy.security.audit.avoid-sqlalchemy-text` | ERROR | no | `src/repositories/usage_repo.py:175` | reported-only (verified false positive) |
| 3 | semgrep | `yaml.github-actions.security.github-actions-mutable-action-tag` | WARNING | no | `.github/workflows/pipeline-ci.yml:54` | reported-only (pre-existing, outside diff hunk) |
| 4 | semgrep | `yaml.github-actions.security.github-actions-mutable-action-tag` | WARNING | no | `.github/workflows/pipeline-ci.yml:86` | reported-only (pre-existing, outside diff hunk) |
| 5 | osv | `PYSEC-2026-1845` / `GHSA-6w46-j5rx-g56g` (one vuln, two aliases) | Moderate (CVSS ~6.8) | no | `pytest==8.3.4` (dev dependency) | action-required (below 7.0 floor — human decides) |
| 6 | gitleaks | `generic-api-key` (127 raw hits) | n/a | no | `.venv/**` (dependency data) + `tests/**` fixtures | reported-only (out of scope / false positive) |
| 7 | manual-6d | RLS `FORCE` inert on `usage_rollup` (ASVS 8.2.x backstop) | Low | no | migration `0002` (pre-existing, not in diff) | reported-only (accepted risk R2 / Open Q3; primary control effective) |

`total_findings = 7`. No row is omitted on grounds of low severity, non-exploitability, or
non-remediation.

### Finding 3 & 4 — Semgrep `github-actions-mutable-action-tag` (WARNING, pre-existing)

Surfaced this pass because the reconcile hook (U-09) requires the full code-shaped change set
in Semgrep's scope, and `.github/workflows/pipeline-ci.yml` is in the change set (its only diff
hunk is the one-line `--cov-fail-under=85` addition). Semgrep flags
`- uses: actions/setup-python@v5` at lines 54 and 86: a **mutable** version tag rather than a
pinned commit SHA (the adjacent `actions/checkout` is correctly SHA-pinned). Low-severity
supply-chain hygiene, **not introduced by this diff** (the flagged lines are outside the changed
hunk). Recorded as warnings (WARNING severity → `warning_count`); non-blocking and status-neutral.
Recommended follow-up: pin `actions/setup-python` to a SHA like `actions/checkout`. Not auto-fixed
— outside this feature's scope and touching CI action pins is a change the CI/delivery owner
should make deliberately.

### Finding 1 & 2 — Semgrep `avoid-sqlalchemy-text` (false positive)

The rule fires on any `text()` call carrying an f-string. Both hits are safe:
`count_usage_rollups` (line 129) and `stream_usage_rollups` (line 175) interpolate only
`where_clause`, the return of `_export_filter_clause_and_params` (line ~74), which is
`" AND ".join(clauses)` where every `clause` is a **fixed string literal**
(`"api_key_id = :api_key_id"`, `"customer_id = :customer_id"`, …). No filter *value* ever
enters the SQL string — all values travel as bound parameters in the `params` dict. The
`ORDER BY window_start, customer_id, metric ASC` is likewise a fixed literal, never
client-derived. **ast-grep's independent structural rule flagged the same two sites and was
investigated to the same conclusion.** There is no injection vector; both are recorded as
reported-only false positives and deliberately **not** folded into `critical_count`. (They remain
counted in `semgrep_findings: 2` so the reconcile hook's re-count of the artifact matches.)

### Finding 5 — pytest tmpdir CVE (OSV)

`pytest==8.3.4` is affected by a `tmpdir`-handling issue (`PYSEC-2026-1845` /
`GHSA-6w46-j5rx-g56g`, one vulnerability under two database ids). CVSS 3.1 vector
`AV:L/AC:L/PR:N/UI:N/S:C/C:L/I:L/A:L` ≈ 6.8 (GitHub: **Moderate**), local vector, **below the
deploy gate's 7.0 High/Critical floor**. pytest is a **dev/test-only** dependency, never on
the request path. The OSV artifact this pass is byte-identical to cycle-1 (dependencies
unchanged). Reported, not auto-fixed (per policy — dependency bumps are not made here).
Safe upgrade recorded in Action required.

### Finding 6 — Gitleaks hits (all out of scope / false positive)

Gitleaks flagged 127 strings. Every hit resolves to either `.venv/**` third-party library
example/test data (AWS botocore fixtures, etc. — dependency tree, not the change set) or a
test-fixture line such as `metric="api_calls", idempotency_key="a"` in
`tests/integration/test_usage_export_endpoint.py` (the `generic-api-key` regex misfiring
on adjacent kwargs). The change-set-scoped filter (non-`.venv`, non-`tests/`) returns nothing.
Presented API keys in tests come from the `make_api_key()` fixture, not hardcoded literals. No
real secret is committed in the change set. The independent change-set secrets grep (6a),
Semgrep `p/secrets`, and the ASVS Tier-1 SAST all agree: zero secrets in source.

### Finding 7 — RLS `FORCE` backstop inert on `usage_rollup` (pre-existing)

The `usage_rollup_tenant_isolation` RLS policy (migration `0002`) is `ENABLE ROW LEVEL
SECURITY` **without `FORCE`**, and the app role (`meterly_app`) owns the table — a table
owner bypasses non-`FORCE` RLS, so the RLS *backstop* is effectively inert for the app role.
This is disclosed in the plan (accepted risk R2, Open Q3), pre-dates this feature, and
affects `GET /v1/usage` identically. Critically, tenant isolation for the export does **not
rely on RLS** — the primary control is the mandatory explicit `api_key_id = principal.api_key_id`
predicate on both new queries (verified present, see 6b/6d), which is effective. Recorded as a
warning / accepted risk; the recommended follow-up is a migration adding `ALTER TABLE
usage_rollup FORCE ROW LEVEL SECURITY` (mirroring `0003` for `quotas`). This feature does not
worsen the condition and does not depend on RLS for its isolation.

## Manual checks (steps 6a–6g)

- **6a Secrets:** change-set grep clean; `.env` and `.envrc` gitignored, no `.env` tracked;
  no secrets in `PROJECT.md`/`CLAUDE.md`/configs; the CI workflow change adds only
  `--cov-fail-under=85` (no `pull_request_target`, no script injection). No hardcoded credential
  in source.
- **6b Row-level security / IDOR:** both new queries (`count_usage_rollups`,
  `stream_usage_rollups`) scope by `api_key_id` **first** as a mandatory predicate sourced
  from the authenticated principal; `api_key_id` is absent from the request schema and
  `extra="forbid"` rejects a client-supplied one. IDOR/BOLA closed. Unchanged by the perf fix. ✓
- **6c Input / output sanitization:** query params validated by `UsageExportQueryParams`
  (anchored-allowlist `constr` reused from `events.py`, `AwareDatetime`, `[now-90d, now+1h]`
  bounds, `from<=to`, `extra="forbid"`). SQL sink parameterized (bound params, fixed-literal
  clauses). CSV sink: `escape_csv_text_cell` neutralizes formula-injection on `customer_id`
  and `metric` (the only attacker-influenced cells; numeric/timestamp are server-generated),
  plus `Content-Disposition: attachment` + inherited `X-Content-Type-Options: nosniff`. The
  `str.translate` refactor is semantically identical to the prior filter (verified by the
  unchanged AC10 escape unit tests + code inspection). ✓
- **6d STRIDE mechanism verification (presence + efficacy):** all 8 named mechanisms present
  AND effective — see table below.
- **6e Log-sink safety:** the `usage.export` / `usage.export.rejected` events log only opaque
  `api_key_id` (int), row counts, and *presence booleans* (`filtered_by_customer`, …) — no raw
  `customer_id`/`metric`, so no log-forging newline surface and no PII/secret in logs. ✓
- **6f STRIDE delta / attack-surface reconciliation:** every new surface in the diff
  (the `GET /v1/usage/export` entry point, the CSV→spreadsheet boundary, two new
  `usage_rollup` queries, the streamed `text/csv` body, the new `usage.export` log event, the
  any-authenticated-key authz surface) is already covered by a threat-model entry. The perf fix
  introduced no new surface (no new route, dependency, sink, or data flow).
  `stride_new_threats: 0`; the STRIDE delta addendum is empty.
- **6g ASVS 5.0.0:** triggered chapters V1/V2/V4/V6/V8/V13/V14/V16 verified at L1+L2 —
  reconciled, see below.

### 6d — STRIDE mechanism table (presence + efficacy)

| STRIDE | Mechanism | Evidence | Efficacy check |
|---|---|---|---|
| Spoofing | `require_api_key` on route | `src/api/routes/usage_export.py:52` (`Depends(require_api_key)`) | ✓ 401 before handler; reused unchanged facade |
| Tampering (SQL) | allowlist validation + bound-param SQL + fixed ORDER BY | `src/api/schemas/usage_export.py`, `src/repositories/usage_repo.py:129,175` | ✓ no value in SQL string; ORDER BY fixed literal; ast-grep + Semgrep leads both cleared |
| Tampering (CSV) | `escape_csv_text_cell` at encoding sink | `src/api/csv_export.py:40` | ✓ escapes leading `= + - @ \t \r`; strips C0 controls (str.translate table, semantics identical to prior filter); reachable leading-`-` case covered |
| Repudiation | one `usage.export` audit log in `finally` | `src/services/usage_export_service.py` (finally block) | ✓ fires on completion and on client disconnect |
| Info Disclosure (tenant) | mandatory `api_key_id` filter (primary control) | `src/repositories/usage_repo.py` (`api_key_id = :api_key_id` first clause) | ✓ effective; does not rely on the inert RLS backstop (F7) |
| Info Disclosure (PII/logs/errors) | minimal 4-col projection, booleans-not-values logging, generic error envelope, UTC-only filename, `no-store` | `usage_repo.py` (`UsageRollupExportRecord`), service log, `_export_filename` (routes:63), `src/api/middleware.py` (existing) | ✓ no tenant id in filename; no raw PII logged |
| Denial of Service | pre-flight count→422 + `LIMIT 100000` + constant-memory stream + Tier-2 per-key throttle | `usage_export_service.py` (`prepare_export`, `_drain`, `_ROWS_PER_CHUNK` batching), `enforce_tier2_rate_limit` | ✓ binding throttle is **identity-keyed** (Tier-2 per-`api_key_id`); chunking + `yield_per` keep memory bounded (≤ one batch buffered); no event-loop stall (async DB only) |
| Elevation of Privilege | `api_key_id`/`scope` absent from schema + `extra="forbid"`; id from principal | `src/api/schemas/usage_export.py` | ✓ mass-assignment rejected; not scope-gated so nothing to escalate |

**Topology efficacy note:** the *binding* rate limit for this authenticated route is the
Tier-2 per-`api_key_id` bucket (correctly identity-keyed — two tenants behind one NAT/ALB get
independent buckets), so it is not subject to the client-IP-behind-ALB single-bucket pitfall.
The pre-auth Tier-1 IP throttle's ALB client-IP derivation is a pre-existing app-wide
condition, not introduced or depended upon by this feature.

**Async-runtime efficacy (ast-grep-checked):** the structural KDF/blocking-call rule found no
hit inside the export's `async def` handlers; the streaming path awaits only async DB calls
(`session.stream`, `count_usage_rollups`, `scoped_transaction`), and the constant-memory CSV
encoding is pure-Python string work bounded to one chunk — no CPU-hard or blocking call stalls
the event loop.

### 6g — ASVS 5.0.0 reconciliation

Plan `## ASVS Compliance` block present. Triggered chapters (L1+L2 universal):
**V1** (CSV/formula output encoding, SQL parameterization — ✓ `csv_export.py`, `usage_repo.py`),
**V2** (Pydantic allowlist validation, `extra="forbid"`, window bounds, throttle — ✓),
**V4** (REST status codes 422/401/500, content-type — ✓),
**V6** (reused API-key split-token + Argon2id verify — ✓ inherited),
**V8** (tenant isolation via mandatory `api_key_id` predicate, BOLA closed — ✓, overlaps 6b),
**V13** (no secrets in code, minimal error disclosure — ✓),
**V14** (minimal projection, no tenant id in filename per 14.3.2, `Cache-Control: no-store` — ✓),
**V16** (structured audit log without PII, generic fail-closed error envelope per 16.5.x — ✓, overlaps 6e).
`n/a`: V5 (no file upload — the feature *emits* a download), V7/V9/V10 (stateless API-key auth,
no session/JWT/OAuth), V11 (no new crypto), V12 (TLS at ALB, inherited), V3/V15 (no new frontend).
No in-scope L3 items new for this feature. `l1_l2_missing: []`, `l3_in_scope_missing: []`,
`reconciled: true`.

*Note (plan-audit observation, non-blocking):* the plan's ASVS block labels the n/a chapters
(V5/V7/V9/V10) as "waivers." These are correctly **n/a determinations** (chapters not
triggered by the diff), not waivers of unmet code/config items, so no `waivers.json` entry is
required and `asvs.waivers` is empty. No reconciliation impact.

## Input-surface reconciliation

One input source implemented — `GET /v1/usage/export` query params (`customer_id`, `metric`,
`from`, `to`). Both controls present: validation contract (`UsageExportQueryParams`) **and**
rate-limit policy (Tier-2 per-`api_key_id`), each traceable to AC4/AC5. `declared: 1,
implemented: 1, uncontrolled: [], reconciled: true`.

## Data-surface reconciliation

Read-only feature (`new_stored_data: false`) — no new DB table/column, file write, cache
entry, or export field beyond what the existing ingest path already stores. `classified: 0,
sensitive: 0, unprotected: [], reconciled: true`.

## Fixes applied

None. No exploitable or critical-severity hygiene finding required a code change — the two
Semgrep ERROR hits are verified false positives on fully parameterized queries (corroborated by
ast-grep's independent structural pass), and the OSV CVE is a report-only dependency finding
below the gate floor. `fixed_count: 0`.

## Could not remediate

None.

## Action required (human decision — not auto-fixed)

- **`pytest` 8.3.4 → 9.0.3** (dev dependency): resolves `PYSEC-2026-1845` /
  `GHSA-6w46-j5rx-g56g` (tmpdir handling, CVSS ~6.8 Moderate, local). Below the deploy gate's
  7.0 floor and off the request path, so it does not block. Bump via `pyproject.toml` +
  `poetry.lock` when convenient (dependency bumps are performed by the debugging/remediation
  path, not the security stage).

## STRIDE delta addendum

Empty — the diff introduces no attack surface that the plan's threat model does not already
cover (`stride_new_threats: 0`). Every new/changed surface (new route, CSV→spreadsheet
boundary, two `usage_rollup` queries, streamed CSV body, new log event, any-authenticated-key
authz) maps to an existing STRIDE row verified in 6d. The cycle-2 perf fix added no new surface.
