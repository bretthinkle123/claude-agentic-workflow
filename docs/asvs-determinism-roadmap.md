# ASVS 5.0.0 determinism roadmap — promoting agent-reasoned checks to deterministic gates

> **Delivered 2026-07-04 — Slice A + first Tier-2:** Tier-1 **T1-1…T1-4** ship as `asvs-sast.sh`
> (a Stop hook on the security agent + a deploy-gate `critical>0` floor; `tests/suites/asvs-sast.sh`).
> Tier-2 **T2-1** (auth-required) and **T2-2** (safe-error) ship as plan-audit **material flags** +
> `test-conventions` adversarial shapes, riding `criteria_covered`. Remaining rows below are ⬜.

**Status: roadmap/spec, partially built (see the banner + ✅ marks).** Companion to the ASVS 5.0.0
verification layer (security step 6g + `asvs-5.0-checklist.md`). Today 6g is **agent-reasoned**: the
security agent (Opus) judges whether each ASVS L1/L2 requirement is met and folds misses into
`critical_count` / `asvs.reconciled` (the deploy gate then blocks deterministically on the *result*).
That is the right uniform baseline, but individual high-value requirements can be **promoted** from
"agent judges" to "shell/test verifies," so an injected or sloppy agent cannot talk past them.

Three tiers (from the design discussion):
- **Tier 1 — mechanically deterministic** (SAST / grep / config presence). A shell check detects the
  pattern; hits fold into `critical_count` like `lockfile-check.sh`.
- **Tier 2 — semantic-but-testable** (a required *test* that would fail if the requirement were
  unmet). Not "prove the code is correct" but "require a test that bites," riding `criteria_covered`
  + a plan-audit material flag — the exact pattern already used for IDOR/BOLA (8.2.2).
- **Tier 3 — genuinely not checkable** (judgment items). Stay agent-reasoned under 6g; no promotion.

This doc lists the **specific** promotions worth making, what's already covered, and the sequencing.

---

## Already deterministic — do NOT re-spec

| ASVS area | Requirement(s) | Mechanism (existing) |
|---|---|---|
| Injection (SQLi/XSS/cmd/path/XXE) | V1.2.x, V1.5.1 | Semgrep `p/owasp-top-ten` + `auto` (Tier 1) |
| Secrets in source/config/logs | V13.3.1, V14.x, V16.2.5 | security 6a grep + `p/secrets` + `Read(**/.env)` deny + deployment pre-commit scan |
| Dependency CVEs / lockfile / SBOM | V15.1.x, V15.2.1 | OSV CVE floor (B6), `lockfile-check.sh`, `generate-sbom.sh` |
| **IDOR / BOLA** | **8.2.2** | **DONE (Tier 2):** plan-audit material-flags a cross-owner-denial test; `test-conventions` cross-owner shape; rides `criteria_covered` |
| Input validation + rate limiting | 2.2.1, 2.2.2, 2.4.1 | input-controls: `input_surface` reconciliation floor + typed `validation`/`rate_limit` criteria |
| Data-at-rest protection | 11.4.2 (at rest), 14.x | Speced in the **DP** workstream (`docs/data-protection-enforcement-plan.md`) — see it, don't duplicate |
| ASVS L1/L2 catch-all (all chapters) | any | 6g agent verification + `asvs.reconciled` deterministic deploy floor |

---

## Tier 1 promotions — new SAST/config checks

Deliver as a new **`asvs-sast.sh`** hook the security agent runs (like `lockfile-check.sh`): targeted
Semgrep rules + a few greps over the diff-scoped change set; each hit is a **critical** that folds into
`critical_count` (so it blocks via the existing gate and is fully deterministic — the agent cannot
under-report it). Rules are stack-aware (Python/JS defaults). Priority order:

| # | ASVS req | What it catches | Detection sketch | Value |
|---|---|---|---|---|
| **T1-1 ✅** | **9.1.2 / 9.1.1** | JWT `alg:none`, signature verification disabled | `algorithms=["none"]`; `verify=False`; `jwt.decode(... verify=False)`; `alg:'none'` | **Critical** — auth bypass · **DONE** (`asvs-sast.sh`) |
| **T1-2 ✅** | **11.4.2** | Passwords stored with a fast hash instead of a slow KDF | a value named `password`/`passwd`/`passphrase` in proximity to `md5`/`sha1`/`sha256`/… `(` | **Critical** — offline cracking · **DONE** |
| **T1-3 ✅** | **11.5.1** | Non-CSPRNG for security values | `random.random/randint/randrange` or `Math.random()` directly assigned to `token`/`secret`/`nonce`/`otp`/`key`/`session`/`reset`/`salt` | **Critical** — predictable tokens · **DONE** |
| **T1-4 ✅** | **11.3.1 / 11.3.2** | Insecure cipher/mode/padding | `MODE_ECB`/`AES/ECB`, `DES`/`RC4`/`ARC4`, `PKCS1v15` | **Critical** · **DONE** |
| T1-5 | **3.3.1 / 3.3.4** | Cookies missing `Secure` / `HttpOnly` / `SameSite` | `set_cookie` / `res.cookie(...)` without the flags (framework-aware) | High (session theft) |
| T1-6 | **13.4.2 / 16.5.1** | Debug mode on in prod; stack traces to client | `debug=True`, `app.run(debug=True)`, `DEBUG = True`; returning exception/traceback text in a response body | Medium |
| T1-7 | **3.4.x** | Missing security headers (HSTS/CSP/`X-Content-Type-Options`/`frame-ancestors`) | presence of a security-headers middleware/config for the default stack (overlaps `api-edge-conventions`) | Medium (config-presence → keep advisory-leaning where framework-ambiguous) |
| T1-8 | **14.2.1** | Sensitive data in URL/query or logged full URLs | query params named `password`/`token`/`ssn`/`card`; logging of full request URLs | Low–Med (heuristic) |

**First slice = T1-1…T1-4** (crypto/auth, highest value, cleanest to write as precise Semgrep rules,
lowest false-positive risk). T1-5/T1-6 next; T1-7/T1-8 last (framework-ambiguous → tune to avoid noise).

---

## Tier 2 promotions — required test-shapes

Enforced the proven way: **plan-audit raises a material flag** when a triggering feature's
`acceptance.md` lacks the required test criterion, and the test then rides the existing
`criteria_covered` gate. Mirrors the DONE 8.2.2 cross-owner-denial pattern.

| # | ASVS req | Required test shape | Triggers when |
|---|---|---|---|
| **T2-1 ✅** | **6.2.x / 8.2.1** | An **unauthenticated** request to each auth-required endpoint returns 401/403 | the feature has any authenticated endpoint (complements 8.2.2). **DONE** (plan-audit material flag + `test-conventions` shape) |
| **T2-2 ✅** | **16.5.1 / 16.5.3** | A forced error returns a **generic** body — no stack trace / SQL / secret; no fail-open | any feature with server-side error paths. **DONE** (plan-audit material flag + `test-conventions` shape) |
| T2-3 | **9.2.1 / 9.2.3** | An **expired** token and a **wrong-audience** token are both rejected | the feature issues or consumes self-contained tokens |
| T2-4 | **7.2.4 / 7.4.1** | Session token **rotates on authentication**; **logout invalidates** the session | the feature manages sessions |
| T2-5 | **2.3.3** | A mid-transaction failure **rolls back** (no partial write) | a multi-write / money / ledger operation (overlaps the concurrency mode — make explicit) |
| T2-6 | **6.2.4 / 6.2.12** | A known-**breached password** is rejected at registration/change | the feature has password registration |

**First slice = T2-1 (auth-required test) + T2-2 (generic-error test)** — highest value, cleanest to
require, apply to almost every real feature. T2-3…T2-6 as their triggers appear.

---

## Sequencing

1. **Slice A — `asvs-sast.sh` (T1-1…T1-4). ✅ DONE (2026-07-04).** Deterministic grep scan (no new
   deps), wired as a security Stop hook, with a deploy-gate `critical>0` floor (deploy-only, absent
   ⇒ no-op, so no loop-exit churn) and `tests/suites/asvs-sast.sh` (detection + gate).
2. **Slice B — Tier-2 T2-1 + T2-2. ✅ DONE (2026-07-04).** plan-audit material flags +
   `test-conventions` adversarial shapes; ride `criteria_covered`.
3. **Slice C — T1-5/T1-6 (cookie flags, debug/errors) + remaining Tier-2 (T2-3…T2-6)** ⬜ as feature
   triggers warrant.
4. **Slice D — T1-7/T1-8** ⬜ (framework-ambiguous; tune thresholds, keep noisy ones advisory).

Each slice narrows the set of ASVS requirements that rely on agent judgement, without removing the
6g `asvs.reconciled` baseline that still covers the Tier-3 semantic items. The end state: the
highest-value auth/crypto/session/token requirements are **shell- or test-verified**, and only
genuinely-judgment requirements remain agent-reasoned.
