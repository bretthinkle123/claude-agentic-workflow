---
status: clean
ran_at: 2026-07-09T03:07:32Z
scope: diff
since_commit: faabe9d6e59533dd144ce7895881dbe54fd7ddd2
critical_count: 0
warning_count: 11
fixed_count: 1
total_findings: 12
semgrep_findings: 7
osv_findings: 2
checkov_findings: null
trivy_findings: null
---

# Security report — feature: metric-quotas (`PUT /v1/quotas` + per-customer enforcement)

## Scope

Diff against `HEAD` (`faabe9d`). Full change set: new `quotas` route/schema/service/repo,
Alembic `0003` (new `quotas` table + `api_keys.scope` column), the `POST /v1/events`
enforcement path, split-token/`scope` plumbing, `READ COMMITTED` engine pin, CORS `PUT`,
`AppError` envelope code, and the `--admin` seed flag. No `infra/` or `Dockerfile` in the
change set → Checkov / Trivy / store-compliance not applicable this pass.

**Remediation re-run delta (since the prior clean scan):** only test-harness + config-pin
changes entered the diff —
`tests/integration/test_perf_k6_load.py` (worker-parity fix + AC20 regression guard),
`tests/integration/test_quotas_rls_backstop.py` (NEW adversarial RLS backstop test),
`tests/test_db_session_isolation.py` (NEW READ-COMMITTED pin regression test),
`src/db/session.py` (`isolation_level="READ COMMITTED"` pin), and a human-revised **AC20**
in `.pipeline/acceptance.md` (perf criterion re-baselined to a relative ≤1.5× bound; not a
security surface). All are risk-reducing or test-only; none introduces new attack surface.

## Tools run this pass

| Tool | Scope | Result |
|---|---|---|
| Semgrep (`auto`, `p/secrets`, `p/owasp-top-ten`, `p/python`) | full change set (36 files) | 7 findings — 2 real WARNINGs (CI mutable tags), 5 ERROR **false positives** in test DDL (triaged below) |
| OSV Scanner | project manifests (`poetry.lock`) | 2 ids (1 vuln, `pytest` — dev/test dep), max CVSS 6.8 < 7.0 floor |
| Gitleaks (`dir`) | full tree | 0 in the change set (all raw hits in `.venv/` + `.pipeline/`) |
| ASVS Tier-1 SAST (`asvs-sast.sh`) | change set | 0 critical, 0 warning |
| Lockfile / supply-chain (`lockfile-check.sh`) | change set | clean (exit 0) |
| Checkov / Trivy | — | n/a (no `infra/` or `Dockerfile` in the change set) |

## Change vs. prior scan

- Semgrep went 5 → 7 findings: the 2 prior `dangerous-subprocess-use-tainted-env-args`
  ERRORs in `test_perf_k6_load.py` (139/290) are **gone** — the worker-parity refactor
  restructured the uvicorn launch, which still uses safe list-form `subprocess.Popen(
  [sys.executable, "-m", "uvicorn", ...])` (no `shell=True`, only `str(port)`/`str(workers)`
  int-coerced tokens). Four new `avoid-sqlalchemy-text` ERRORs entered from the new RLS
  backstop test (all false positives — DDL over a uuid-generated role name; see triage).
- OSV unchanged (same 2 `pytest` ids, artifact byte-identical).
- No new critical, no new blocking finding. `status` stays **clean**.

## Complete findings inventory

| # | source | id | severity | exploitable | location | disposition |
|---|---|---|---|---|---|---|
| 1 | osv | GHSA-6w46-j5rx-g56g | Medium (CVSS 6.8) | no | `poetry.lock` → `pytest@8.3.4` | action-required |
| 2 | osv | PYSEC-2026-1845 | Medium (CVSS 6.8) | no | `poetry.lock` → `pytest@8.3.4` | action-required |
| 3 | manual-6d | RLS backstop inert without FORCE (`quotas`) | Medium | no | `alembic/versions/0003_create_quotas_and_api_key_scope.py:54` | fixed |
| 4 | manual-6d | RLS backstop inert without FORCE (`events`, `usage_rollup`) | Medium | no | `alembic/versions/0001_*.py:66`, `0002_*.py:67` | reported-only |
| 5 | semgrep | github-actions-mutable-action-tag | Warning | no | `.github/workflows/pipeline-ci.yml:54` | reported-only |
| 6 | semgrep | github-actions-mutable-action-tag | Warning | no | `.github/workflows/pipeline-ci.yml:85` | reported-only |
| 7 | semgrep | avoid-sqlalchemy-text | Error (false positive) | no | `tests/integration/test_quota_migration.py:73` | reported-only |
| 8 | semgrep | avoid-sqlalchemy-text | Error (false positive) | no | `tests/integration/test_quotas_rls_backstop.py:44` | reported-only |
| 9 | semgrep | avoid-sqlalchemy-text | Error (false positive) | no | `tests/integration/test_quotas_rls_backstop.py:46` | reported-only |
| 10 | semgrep | avoid-sqlalchemy-text | Error (false positive) | no | `tests/integration/test_quotas_rls_backstop.py:47` | reported-only |
| 11 | semgrep | avoid-sqlalchemy-text | Error (false positive) | no | `tests/integration/test_quotas_rls_backstop.py:49` | reported-only |
| 12 | manual-6a | test-only ephemeral role password literal | Low | no | `tests/integration/test_quotas_rls_backstop.py:39` | reported-only |

`total_findings = 12` (2 osv + 2 manual-6d + 7 semgrep + 1 manual-6a). Gitleaks (0 in-scope) +
ASVS-SAST (0) + lockfile (0) contribute no rows. `critical_count = 0` after remediation;
`fixed_count = 1` (#3, carried in the working tree); `warning_count = 11` (all remaining rows
advisory/non-blocking).

## Semgrep triage (rows 5–11)

- **#5 / #6 — `github-actions-mutable-action-tag` (WARNING, real).** Two CI steps in
  `pipeline-ci.yml` reference a mutable `@vN` tag rather than a pinned commit SHA — supply-chain
  hygiene. WARNING → advisory, non-blocking. Not auto-fixed (pinning third-party action SHAs is a
  CI-ownership decision). Recommend pinning to full-length commit SHAs.
- **#7 — `avoid-sqlalchemy-text` (ERROR, false positive).** `test_quota_migration.py:73` builds an
  f-string into `text()`, but the interpolated `columns`/`values` are static literals assembled
  in-function; every actual value is passed as a bound `:param`. No user-controlled interpolation.
  Test-harness only. Not exploitable.
- **#8–#11 — `avoid-sqlalchemy-text` (ERROR, false positive), new RLS backstop test.**
  `test_quotas_rls_backstop.py:44,46,47,49` interpolate `role_name` into `CREATE ROLE` / `GRANT`
  DDL. `role_name` is `f"rls_test_role_{uuid.uuid4().hex[:8]}"` — internally generated, never
  user-controlled — and PostgreSQL does not accept bind parameters for identifiers (role names) in
  DDL, so an f-string is the only expressible form here. Runs solely against an ephemeral
  testcontainers Postgres, torn down after the test. No injection vector. Not exploitable → not a
  blocking critical. All bona-fide values in the test's data statements (`api_key_id`,
  `customer_id`) ARE passed as bound `:params` (lines 91, 98, 107, 148).

The five ERROR rows are recorded `exploitable: no` and excluded from `critical_count` (step-7
exploitability judgment over raw scanner severity); `semgrep_findings` reports the raw count of 7,
reconciled against the artifact.

## Manual 6a triage (row 12)

`role_password = "test-role-password"` (test_quotas_rls_backstop.py:39) is the password assigned to
the throwaway `NOBYPASSRLS` role the test creates and `DROP`s within the same testcontainers
session. It is not a production credential, appears in no runtime config/image/tfvars, and gitleaks
does not classify it as a secret (low entropy, obvious test literal). Reported for completeness;
not a finding requiring remediation. No `.env` in the tracked change set; `git ls-files .env`
returns nothing; `.env` remains gitignored.

## Fixes applied

**#3 — `quotas` RLS tenant-isolation backstop made effective (`FORCE ROW LEVEL SECURITY`)** in
`alembic/versions/0003_create_quotas_and_api_key_scope.py` (applied in the prior remediation pass;
still present in the working tree). The migration's app role owns the table and a table owner
bypasses non-`FORCE` RLS, so the backstop policy would be inert without `FORCE`. The added
`ALTER TABLE quotas FORCE ROW LEVEL SECURITY` closes that gap; safe for the app path because every
`quotas` access runs inside `scoped_transaction` (`SET LOCAL app.current_api_key_id`). Confirmed
gone by this pass's consolidated re-scan.

**This delta added a positive proof, not a fix:** the new `test_quotas_rls_backstop.py` is an
adversarial test that connects as a real `NOBYPASSRLS` role (mirroring production `meterly_app`),
issues a filter-less query with the primary `api_key_id` predicate entirely removed, and asserts
the RLS policy alone still confines the session to its own tenant's rows — and a second test proves
fail-closed behavior when `app.current_api_key_id` is unset. This turns the #3 FORCE fix from a
declared control into a tested one, and independently exercises the backstop that
`test_quotas_endpoint.py` could not (it runs as the testcontainers superuser, which bypasses RLS).

## Could not remediate

None.

## Action required (human decision — not auto-fixed)

- **#1 / #2 — `pytest@8.3.4`** (GHSA-6w46-j5rx-g56g / PYSEC-2026-1845, CVSS ≈ 6.8 Medium).
  Dev/test-only tmpdir predictability, not on the request path. Below the deploy gate's CVSS ≥ 7.0
  floor → non-blocking. Safe upgrade: bump `pytest` to ≥ 8.3.5 in `pyproject.toml` + `poetry.lock`.
  Dependency bumps are the debugging agent's remit, not security's — reported only.
- **#4 — `events` and `usage_rollup` lack `FORCE ROW LEVEL SECURITY`** (pre-existing, migrations
  `0001`/`0002`, outside this diff). Same owner-bypass reasoning as #3. Recommend adding `FORCE` in a
  follow-up migration, or verifiably running migrations as a non-owner role. The explicit
  `api_key_id` predicate remains the effective primary control on those tables regardless.

## STRIDE mechanism verification (6d)

All 10 non-accepted-risk threats from `plan.md` §Threat Model have their named mechanism present;
2 accepted-risk rows (quota-data-at-rest, hot-row serialization latency) skipped per protocol. No
change to the mechanism set this pass; the delta strengthens two efficacy answers:

- **TOCTOU (Tampering):** the `isolation_level="READ COMMITTED"` pin in `src/db/session.py:41` is now
  both documented (engine comment) and guarded by a deterministic regression test
  (`tests/test_db_session_isolation.py`), so the lock-then-read correctness the quota cap depends on
  cannot silently regress to REPEATABLE READ. Efficacy: ✓ (pin present + test-locked).
- **EoP data-level (IDOR/BOLA):** the RLS backstop is now proven effective by an adversarial
  NOBYPASSRLS test (`test_quotas_rls_backstop.py`), not merely declared. Efficacy: ✓ (primary
  `api_key_id` predicate present + backstop FORCE-enabled and independently exercised).

`stride_mechanisms_verified = 10`, `stride_mechanisms_missing = 0`. Topology (Tier-2 throttle keyed
on `api_key_id`, not client IP), DB privilege (owner-bypass fixed on `quotas`; `events`/
`usage_rollup` flagged as #4), async runtime (no CPU-hard KDF on the loop in changed code), and
contract drift (`customer_id` in the log redaction set) all re-confirmed unchanged.

## STRIDE delta addendum (6f)

The delta introduces **no new attack surface** — new files are tests, and `src/db/session.py`
gained a configuration pin (isolation level), not a new entry point, outbound call, subprocess,
deserializer, or data sink. `stride_new_threats = 0`; addendum empty. (The feature's own new
surface — `PUT /v1/quotas`, `api_keys.scope`, the `quotas` table — was reconciled and covered in
the prior pass and is unchanged here.)

## ASVS 5.0.0 verification (6g)

Triggered chapters: V1, V2, V4, V6, V8, V12, V13, V14, V15, V16 (per plan `## ASVS Compliance`).
`n/a`: V3, V5, V7, V9, V10, V11, V17. L1+L2 verified universally; in-scope L3 = V15.4.x
(check-then-act atomicity) + V11.2.4 (constant-time compare, unchanged). The delta touches only
V15.4.x — the READ-COMMITTED pin + its regression test reinforce the check-then-increment
atomicity that V15.4.1/15.4.2 require; still met. All other chapter verdicts carry forward from the
prior pass. `l1_l2_missing = []`, `l3_in_scope_missing = []`, `doc_advisory = []`, `waivers = []`,
`reconciled = true`. No plan-cited ASVS mitigation left unimplemented.

## Input-surface reconciliation

Unchanged: 1 input source implemented (`PUT /v1/quotas`), 1 declared, both controls present
(validation contract + Tier-2 per-`api_key_id` rate limit). `uncontrolled = []`, reconciled.

## Data-surface reconciliation

Unchanged: `quotas.{customer_id, metric, limit_per_window}` + `api_keys.scope`, all classified
non-sensitive operational config/authz metadata; at-rest control = RDS SSE. `sensitive = 0`,
`unprotected = []`, reconciled.

## Migration scan (`0003`)

Unchanged from prior pass: downgrade path present; `up` is expand-only; `down`'s `DROP TABLE` is the
defined reversibility of a create-migration; no injectable SQL (all static DDL). Not a finding.
