---
status: clean
ran_at: 2026-07-06T20:21:34Z
scope: full
since_commit: null
critical_count: 0
warning_count: 45
fixed_count: 0
total_findings: 48
semgrep_findings: 8
osv_findings: 1
checkov_findings: 58
trivy_findings: 27
gitleaks_findings: 1
osv_max_cvss: 6.8
stride_mechanisms_verified: 15
stride_mechanisms_missing: 0
stride_new_threats: 0
asvs_reconciled: true
input_surface_reconciled: true
data_surface_reconciled: true
---

# Security report — Meterly (RE-SCAN after rate-limiter NameError remediation)

Greenfield repo, no HEAD — scanned the **full working tree** (scope `full`,
`since_commit: null`) per `diff-scoping-conventions`. This is the **re-scan** after
the debugging/remediation agent fixed the Tier-2 rate-limiter `NameError` (see
`.pipeline/debug-notes.md`, latest entry). The change set relative to the prior
clean pass is three files:

1. `src/auth/rate_limit.py` — **+1 line**, `from src.logging import get_logger`,
   resolving the two already-present `get_logger(...)` call sites in
   `enforce_tier2_rate_limit` (the fail-open branch and the 429-deny branch).
2. `tests/integration/conftest.py` — `truncate_tables` now also `flushdb()`s the
   session-scoped Redis per test (test-isolation fix; no runtime surface).
3. `tests/test_rate_limit_fail_open.py` — **new** regression test for the
   Redis-outage fail-open branch (test-only; no runtime surface).

**No dependency manifest, lockfile, infra (`infra/`), Dockerfile, or migration
changed** relative to the prior scan.

## Verdict

`status: clean` — **0 critical findings**, and the change set introduced none. The
one-line import fix is purely additive and, if anything, a **security improvement**:
before it, every Tier-2 `429` and every Redis-outage fail-open raised
`NameError → unhandled 500`, so the per-key rate-limit control (STRIDE **D**enial-of-
service mitigation, AC14/AC16) was effectively non-functional. The fix **restores**
that control. No newly-introduced attack surface, no secret, no injection, no
unencoded sink.

The prior pass's remaining non-gating item carries forward unchanged:

> **`osv_max_cvss = 6.8`** — the single remaining OSV finding is `pytest 8.3.4`
> (GHSA-6w46-j5rx-g56g / CVE-2025-71176, MODERATE, CVSS 6.8), a **dev-only** test
> dependency not shipped in the runtime image (Dockerfile installs `--only main`).
> 6.8 is **below the deploy gate's CVSS ≥ 7.0 floor** → does not block. No waiver
> needed. The ten previously-cleared `starlette` CVEs (four HIGH/7.5) remain absent.

## Tools run (this re-scan)

| Tool | Scope this pass | Result | vs. prior |
|---|---|---|---|
| Semgrep (auto, p/secrets, p/owasp-top-ten, p/python) via Docker | change set (3 files) | **0 findings, 0 errors** | change set adds nothing |
| Gitleaks (`dir`) via Docker | full tree | 122 raw; **1 in-scope (FP)**, 121 in gitignored `.venv/` | unchanged (1 FP) |
| OSV Scanner | poetry.lock (80 pkgs, unchanged) | **1 CVE (pytest, dev-only, 6.8)** | unchanged |
| ASVS Tier-1 SAST (hook) | change set | **0 critical, 0 warning** | unchanged |
| Lockfile integrity (hook) | change set | **clean** (no manifest/lock change) | clean |
| Checkov | `infra/` — **not re-run** (byte-identical) | carried forward: 58 | unchanged |
| Trivy config via Docker | Dockerfile + `infra/` — **not re-run** (byte-identical) | carried forward: 27 | unchanged |

**Checkov/Trivy justification for skip:** the change set touches no `infra/` file,
no Dockerfile, and no built image, so the IaC/container posture is byte-identical to
the prior clean scan; those findings carry forward verbatim rather than being
re-scanned. Docker Desktop was running; Semgrep, Gitleaks, and OSV all executed.

## Complete findings inventory

Authoritative record — every standing finding in the working tree, one row each.
The Semgrep/Gitleaks/OSV rows below were re-verified this pass; the Checkov/Trivy
infra rows are carried forward from the prior scan (infra byte-identical). Infra
rows are grouped by distinct check ID (affected-resource count in *location*).
Trivy's 27 CRITICAL/HIGH reconcile 1:1 to Checkov rows (noted inline) and are not
double-counted.

| source | id | severity | exploitable | location | disposition |
|---|---|---|---|---|---|
| semgrep | github-actions-mutable-action-tag | WARNING | no | .github/workflows/pipeline-ci.yml:54 | reported-only |
| semgrep | aws-cloudwatch-log-group-unencrypted | WARNING | no | infra/modules/compute/main.tf:28 | reported-only |
| semgrep | no-iam-data-exfiltration | WARNING | no | infra/modules/compute/main.tf:75 (X-Ray Put*, AWS-required `Resource:*`) | reported-only (FP) |
| semgrep | aws-elb-access-logs-not-enabled | WARNING | no | infra/modules/compute/main.tf:143 | reported-only |
| semgrep | aws-db-instance-no-logging | WARNING | no | infra/modules/data/main.tf:24 | reported-only |
| semgrep | aws-insecure-cloudfront-distribution-tls-version | WARNING | no | infra/modules/edge/main.tf:61 | reported-only |
| semgrep | aws-cloudwatch-log-group-unencrypted | WARNING | no | infra/modules/network/main.tf:93 | reported-only |
| semgrep | aws-cloudwatch-log-group-unencrypted | WARNING | no | infra/modules/observability/main.tf:19 | reported-only |
| gitleaks | generic-api-key | INFO | no | tests/test_schemas_events.py:18 (`idempotency_key` test value, not a credential) | reported-only (FP) |
| osv | GHSA-6w46-j5rx-g56g | MODERATE (6.8) | no | pytest 8.3.4 (poetry.lock, dev-only — not in runtime image) | action-required |
| checkov | CKV_SECRET_6 | INFO | no | infra/modules/data/main.tf:98 (`random_password` interpolation → Secrets Manager) | reported-only (FP) |
| checkov | CKV_AWS_382 | WARNING | no | 4 SGs (unrestricted egress) — = Trivy AWS-0104 | reported-only |
| checkov | CKV_AWS_23 | WARNING | no | 4 SG rules (no rule description) | reported-only |
| checkov | CKV2_AWS_5 | WARNING | no | 4 SGs (attach-to-resource, module-in-isolation FP) | reported-only |
| checkov | CKV_AWS_338 | WARNING | no | 3 log groups (retention < 1yr) | reported-only |
| checkov | CKV_AWS_158 | WARNING | no | 3 log groups (no KMS on log group) | reported-only |
| checkov | CKV_AWS_18 | WARNING | no | 2 S3 buckets (access logging) | reported-only |
| checkov | CKV_AWS_144 | WARNING | no | 2 S3 buckets (cross-region replication) | reported-only |
| checkov | CKV2_AWS_62 | WARNING | no | 2 S3 buckets (event notifications) | reported-only |
| checkov | CKV2_AWS_61 | WARNING | no | 2 S3 buckets (lifecycle config) | reported-only |
| checkov | CKV2_AWS_47 | WARNING | no | CloudFront (WAF log4j rule) | reported-only |
| checkov | CKV2_AWS_42 | WARNING | no | CloudFront (custom SSL cert) | reported-only |
| checkov | CKV2_AWS_32 | WARNING | no | CloudFront (response headers policy) | reported-only |
| checkov | CKV2_AWS_31 | WARNING | no | WAFv2 (logging) | reported-only |
| checkov | CKV_AWS_91 | WARNING | no | ALB (access logging) — = Trivy AWS-0052 | reported-only |
| checkov | CKV_AWS_86 | WARNING | no | CloudFront (access logging) | reported-only |
| checkov | CKV_AWS_374 | WARNING | no | CloudFront (geo restriction) | reported-only |
| checkov | CKV_AWS_353 | WARNING | no | RDS (enhanced monitoring detail) | reported-only |
| checkov | CKV_AWS_310 | WARNING | no | CloudFront (origin failover) | reported-only |
| checkov | CKV_AWS_31 | WARNING | no | ElastiCache (AUTH token; transit encryption IS enabled) | reported-only |
| checkov | CKV_AWS_305 | WARNING | no | CloudFront (default root object) | reported-only |
| checkov | CKV_AWS_26 | WARNING | no | SNS topic (encryption) — = Trivy AWS-0095 | reported-only |
| checkov | CKV_AWS_226 | WARNING | no | RDS (auto minor version upgrade) | reported-only |
| checkov | CKV_AWS_21 | WARNING | no | 1 S3 bucket (versioning) | reported-only |
| checkov | CKV_AWS_174 | WARNING | no | CloudFront (TLS min version) | reported-only |
| checkov | CKV_AWS_161 | WARNING | no | RDS (IAM auth) | reported-only |
| checkov | CKV_AWS_157 | WARNING | no | RDS (Multi-AZ — env-controlled `var.db_multi_az`; prod sets true) | reported-only |
| checkov | CKV_AWS_150 | WARNING | no | ALB (deletion protection) | reported-only |
| checkov | CKV_AWS_145 | WARNING | no | S3 (SSE uses AES256 not CMK) — = Trivy AWS-0132 | reported-only |
| checkov | CKV_AWS_131 | WARNING | no | ALB (drop invalid headers) — = Trivy AWS-0052 | reported-only |
| checkov | CKV_AWS_129 | WARNING | no | RDS (log exports) | reported-only |
| checkov | CKV_AWS_118 | WARNING | no | RDS (enhanced monitoring) | reported-only |
| checkov | CKV2_AWS_64 | WARNING | no | KMS key (policy defined) | reported-only |
| checkov | CKV2_AWS_60 | WARNING | no | RDS (copy tags to snapshot) | reported-only |
| checkov | CKV2_AWS_57 | WARNING | no | Secrets Manager (automatic rotation) | reported-only |
| checkov | CKV2_AWS_30 | WARNING | no | RDS (query logging) | reported-only |
| checkov | CKV2_AWS_28 | WARNING | no | ALB (WAF association — prod uses CloudFront+WAF) | reported-only |
| checkov | CKV2_AWS_12 | WARNING | no | VPC (default SG restricts all) | reported-only |

**Row count = 48 = `total_findings`.** Unchanged from the prior clean scan — the
three-file change set added zero rows.

## Fixes applied

None **by the security agent this run**. The rate-limiter `NameError` remediation
was performed by the debugging agent (`.pipeline/debug-notes.md`, latest entry):
the `from src.logging import get_logger` import in `src/auth/rate_limit.py`, the
per-test Redis `flushdb()` in `tests/integration/conftest.py`, and the new
`tests/test_rate_limit_fail_open.py`. This re-scan **confirms** that change is
security-benign (Semgrep 0, ASVS SAST 0) and introduced no finding. No step-7 fix
criterion was met this run.

## Could not remediate

None.

## Action required (human decision — not auto-fixed)

### `pytest` — dev-only, NON-gating

`pytest 8.3.4` → **GHSA-6w46-j5rx-g56g** / **CVE-2025-71176** (MODERATE, CVSS 6.8,
vector `CVSS:3.1/AV:L/AC:L/PR:N/UI:N/S:C/C:L/I:L/A:L`), fixed in **9.0.3**. A
dev/test dependency only — not shipped in the runtime image (Dockerfile installs
`--only main`), local attack vector, no production exposure. `osv_max_cvss = 6.8` is
below the deploy gate's 7.0 floor → **does not block deploy**. Upgrade at
convenience.

## Reconciliations re-verified

The change set touches only a benign import, a test fixture, and a new test — it
adds **no route, no trust boundary, no data sink, no stored field, and no privilege
surface**. The prior scan's reconciliations carry forward and were re-confirmed
against the current tree:

- **STRIDE mechanism verification (6d):** 15/15 named mechanisms present,
  `missing: 0`. The Tier-2 per-key token-bucket rate limiter (`src/auth/rate_limit.py`,
  plan D-category mitigation, AC14/AC16) is now **genuinely functional** — the
  `get_logger` import resolves both call sites that previously raised
  `NameError → 500`. No mechanism removed or weakened.
- **STRIDE delta (6f):** `stride_new_threats: 0`. `test_rate_limit_fail_open.py`
  has no runtime surface (an in-process assertion); the conftest change is
  test-only; the `rate_limit.py` change is an import. No new attack surface. Empty
  addendum.
- **Log-sink safety (6e):** the two now-live `get_logger(...)` calls in
  `enforce_tier2_rate_limit` (lines 158, 164) emit **structured fields only** via
  the structlog facade — `endpoint=request.url.path` (route path; structlog
  neutralizes control chars), `userId=principal.api_key_id` (internal integer id,
  not the key material), plus static `tier`/`action`/`reason` tags. No raw user
  input concatenated into a message, no secret/PII, no log-forging vector. Clean.
- **ASVS 5.0.0 (6g):** `reconciled: true`. Triggered chapters V1, V2, V4, V6, V8,
  V11, V12, V13, V14, V15, V16 verified at L1+L2 (universal) + in-scope L3 (11.2.4
  constant-time compare, 15.4 TOCTOU-atomic); `l1_l2_missing` and
  `l3_in_scope_missing` both empty; `waivers: []`. Unchanged — no ASVS-relevant
  code/config item altered.
- **Input surface:** declared 2 / implemented 2 / `uncontrolled: []`. `POST /v1/events`
  and `GET /v1/usage` retain their Pydantic validation contract + Tier-2 rate limit
  — the latter's rate-limit control is now **restored** by this fix. reconciled.
- **Data surface:** classified 3 / sensitive 3 / `unprotected: []` — unchanged
  (`api_keys.secret_hash` Argon2id; `events.customer_id` + `usage_rollup.customer_id`
  RDS SSE-KMS + redaction). No stored field touched.
- **ASVS Tier-1 SAST + lockfile integrity (hooks):** 0 critical; lockfile clean (no
  manifest/lock change in the set).

## STRIDE delta addendum (step 6f)

Empty — the change set introduced no new attack surface (`stride_new_threats: 0`).

## Infra (Checkov + Trivy) baseline assessment

**Not re-scanned this pass** — `infra/`, the Dockerfile, and the built image are
byte-identical to the prior scan, so the 58 Checkov + 27 Trivy findings are the same
set and carry forward. **Zero `infra/` baseline criticals** per
`iac-conventions`: no IAM data-action wildcards (only X-Ray `Put*` uses the
AWS-required `Resource:*`), no public S3 (all buckets Block-Public-Access),
encryption at rest present (RDS/Redis/ECR CMK, S3 SSE-AES256), no committed secrets
(CKV_SECRET_6 is a `random_password`→Secrets-Manager interpolation FP), no
`0.0.0.0/0` ingress to DB/admin ports (only the ALB SG takes 443 public), RLS +
NOBYPASSRLS enforced. All 85 (58+27) are best-practice/hardening warnings or scan
artifacts.

## Secrets scan

- Semgrep `p/secrets`: 0 findings in the change set.
- Gitleaks (`dir`, full tree): 122 raw — 121 are third-party SDK example fixtures
  under gitignored `.venv/` (out of scope). The 1 in-scope hit
  (`tests/test_schemas_events.py:18`, `idem-key-abc123`) is a **false positive**: an
  `idempotency_key` client dedup token in a test payload, not a credential. That
  file is not in this change set.
- ASVS Tier-1 SAST: 0 secrets/crypto criticals.
- No `.env` in the tracked tree; `.env` is gitignored; no embedded secrets in
  CLAUDE.md / PROJECT.md / config files.
