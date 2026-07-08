# Pipeline performance report — M3 run (Meterly feature 1, 2026-07-06)

Audit of the SDLC pipeline engine's performance on the M3 test run. Written by an
independent audit session on 2026-07-06. Every number below is quoted from the raw
artifacts (`.pipeline/run-log.jsonl`, `run-summary.json`, `loop-state.json`, the stage
artifacts) or from the pipeline definition (`~/.claude/hooks|agents|skills|pipeline-templates`,
repo-of-record `claude-agentic-workflow`); `run-retrospective.md` was treated as testimony
and re-verified. Claims that could **not** be verified are marked ⚠ and collected in the
fix plan's "could not verify" section.

**Shipped result:** PR #1, branch `feature/usage-metering-ingest`, commit `faabe9d` —
verified `140 files changed, 14131 insertions(+)` via `git show --stat`. Human approved
the diff as-is with 10 verified code-review findings deferred (recorded in the PR body).

---

## 1. Run economics

### Per-stage totals (quoted from `run-summary.json`, regenerated 2026-07-06T21:25:10Z)

| stage | invocations | attempts_max | caps | model | last_status |
|---|---|---|---|---|---|
| planning | 1 | 1 | 0 | opus | pass |
| plan-audit | 1 | 1 | 0 | sonnet | pass |
| implementation | 5 | 5 | 3 | sonnet | pass |
| debugging | 3 | 3 | 1 | opus | pass |
| security | 3 | 3 | 0 | opus | clean |
| testing | 3 | 3 | 1 | sonnet | pass |
| documentation | 2 | 2 | 1 | haiku | pass |
| deployment | 2 | 2 | 1 | sonnet | pass |

Totals (same file): `log_lines: 20`, `capped_lines: 7`, `loop_cap_events: 0`,
`first_pass_clean: false`. Models used: haiku, opus, sonnet.

**20 invocations to ship one feature; 7 of 20 log lines (35%) are cap-outs.** The capped
lines in `run-log.jsonl` are #3–5 (implementation attempts 1–3), #11 (testing attempt 1),
#13 (debugging attempt 2), #17 (documentation attempt 1), #19 (deployment attempt 1).
Configured `maxTurns` (agent frontmatter, verified): implementation 40, testing 50,
security 30, debugging 30, planning 30, documentation 25, plan-audit 20, deployment 15.
Every stage that builds or exercises large amounts of code capped at least once;
even deployment (commit + push + PR, `maxTurns: 15`) capped before finishing.
Notably, the cap-outs cluster at the *end* of work: documentation resumed and passed in
59 s (20:55:20 → 20:56:19), deployment in 36 s (21:20:00 → 21:20:36) — those two caps
bought almost nothing and each cost a cold resume.

### Timeline (timestamp deltas from `run-log.jsonl` — the only duration proxy available)

- Whole run: 17:11:34Z (planning pass) → 21:20:36Z (deployment pass) = **4 h 09 m**.
- Implementation block: 17:18 → 18:36 = **78 min for 5 attempts** (3 caps, 1 smoke fail,
  1 pass) — the single most expensive stage.
- Remediation loop: `loop-state.json` `started_at: 18:36:44Z`, `completed_at: 20:50:21Z`,
  **cycles 3 of 5**, `compute_s: 1218` of 1800 max, wall clock at last tick =
  1783369227 − 1783363004 = **6223 s of 7200 s** (86% of the absolute backstop consumed
  at cycle 3, while the compute budget — which caps each cycle's contribution at 600 s
  precisely so human-wait and resume latency don't count — sat at a comfortable 68%).
- Retries: `remediation 2 of 3` used (run-log line 14 notes; `debug-notes.md` documents
  both — starlette CVE bump, rate-limiter NameError), `sanity 0`.

### Cost shape

Opus carried planning, security ×3, and debugging ×3; sonnet carried the two highest-
turn-count stages (implementation ×5, testing ×3); haiku carried documentation. The
dominant waste was not model choice but **cap-resume overhead**: each of the 7 resumes
restarts a fresh-context agent that re-reads the plan/tree before continuing.

---

## 2. Effectiveness — what each layer caught, and what got through

### Caught by the pipeline (verified against artifacts)

| Layer | Catch | Evidence |
|---|---|---|
| Smoke gate (`smoke-check.sh`) | Implementation attempt 4 failed smoke — the run-log line 6 `"notes":"smoke fail"` — surfacing the broken greenfield build check (smoke.env quoting + wrong `python`) plus whatever import breakage the resume left; attempt 5 passed after the smoke.env rewrite. | run-log lines 6–7; current `smoke.env` shows the working space-free form |
| OSV scan → CVE floor | `starlette 0.41.3` with 4 HIGH/CVSS 7.5 CVEs; `osv_max_cvss = 7.5` would have tripped the deterministic ≥7.0 deploy floor. Remediated via fastapi 0.133.0 + starlette 1.3.1 with a fails-before/passes-after pin-guard test. Final scan: `osv_max_cvss: 6.8` (pytest, dev-only) — legitimately below the floor. | `debug-notes.md` entry 1; `security-status.json`; `security-report.md` |
| Testing stage | The rate-limiter `NameError` — a **real production bug** (every Tier-2 429 and every Redis-outage fail-open became an unhandled 500, silently disabling AC14/AC16 rate limiting). Caught by the two discriminating-shape integration tests, fixed with a regression test, plus a second latent test-isolation bug (Redis state leaking across tests) unmasked and fixed. | run-log line 12 (2 named failures); `debug-notes.md` entry 2 |
| Loop-exit perf-completeness predicate | Forced a **real k6 measurement**: POST 497.75 req/s (meets ≥475), p95 75.47 ms (misses <50 ms, disclosed, 3-run repeatable), GET p95 13.19 ms (meets). Without the "declared budget ⇒ non-null measured + non-null scenario" conjunct the initial punt would have exited green unmeasured. | `test-results.json` `.perf` block; gate lines 60–72; SKILL.md lines 66–71 |
| Criteria-coverage gate | Numerically enforced `covered >= total` at both loop-exit and deploy. | gate lines 36–41 |
| Marker guards | `guard-approval-markers.sh` correctly denied marker writes (see friction #7 for the doc problem); `guard-source-markers.sh` blocked — albeit on its own scaffold (friction #3). | hook sources; reworded meterly copies |

### Got through to /code-review — 10 CONFIRMED findings the security stage missed

I spot-checked six of the ten in the shipped tree; all six are real
(`src/api/middleware.py:118` `request.client.host`; `:91` `_TIER1_EXEMPT_PATHS = {"/health"}`;
`alembic/versions/0001…py:66` `ENABLE ROW LEVEL SECURITY` (not FORCE);
`infra/modules/data/main.tf:84` `GRANT … UPDATE, DELETE` to `meterly_app`;
`src/config/secrets.py:80` sync `get_secret_value`; `src/observability/sentry.py:15`
`_STRIPPED_KEYS` with no query-string handling). The security stage reported `clean`
on **all three** passes (run-log lines 8, 10, 15 — the retrospective says "twice";
minor error) with `stride_mechanisms_verified: 15, missing: 0`, `asvs.reconciled: true`,
`input_surface.reconciled: true`, `data_surface.reconciled: true`.

**Why, by class — the common thread is that every reconciliation checks *presence*,
not *efficacy*:**

1. **Deploy-topology bugs** (Tier-1 throttle keyed on the ALB node's IP with no
   proxy-header trust configured anywhere; `/health/ready` — the ALB probe path — not
   throttle-exempt). No scanner models "this code runs behind a load balancer." The
   STRIDE 6d check confirmed the rate-limit *mechanism exists*; nothing asks whether its
   key is meaningful in the declared topology. The plan said "IP+route" and plan-audit
   flagged only the missing numeric limit — the topology assumption was never stated, so
   no downstream check could test it. Ironically `surface-delta.md` explicitly flagged
   the `/health` exemption; nobody asked "and `/health/ready`?".
2. **DB-privilege semantics** (RLS ENABLE-without-FORCE while the app role owns the
   tables ⇒ backstop inert; "append-only" declared in STRIDE R1 while UPDATE/DELETE are
   granted). Checkov/Trivy check cloud-resource config, not Postgres grant semantics.
   The security report asserted "RLS + NOBYPASSRLS enforced" — true and irrelevant,
   since table *owners* bypass non-FORCE RLS regardless of BYPASSRLS. Worse, the
   integration RLS test **passed vacuously**: app-layer scoping made cross-tenant reads
   fail even with the backstop inert, so a green test certified a dead control.
3. **Sync-on-event-loop hazards** (Argon2id verify and boto3 `get_secret_value` called
   synchronously inside async handlers). No configured Semgrep pack has an
   asyncio-blocking-call rule. The k6 p95 miss (75 ms vs 50 ms) was the *symptom*, and
   it was measured — but the testing agent attributed it wholly to shared-Docker-host
   contention and the explanation was accepted; deferred finding #4 identifies sync
   Argon2id as the likely primary cause. A measured red flag was explained away without
   a code-level check.
4. **Contract-vs-implementation drift** (secrets facade documents rotation re-fetch but
   `src/db/session.py` resolves the DB URL once at engine creation; Sentry scrubber
   strips headers/fields but not `query_string`/`url`, so `GET /v1/usage?customer_id=…`
   leaks PII on any unhandled exception). Cross-module semantic drift between a promise
   in one file and a consumer in another — invisible to any per-file scanner, and no
   named reconciliation step compares facade contracts to their consumers.

All four classes are checkable **by inspection with a named checklist question** — no new
scanner required. That is the fix plan's F2.

### Got through to nothing (unknown unknowns)

By definition unmeasurable from this run. Two shipped inaccuracies that only /code-review
or this audit noticed are worth recording as near-misses: `pr-description.md` states
"All 24 acceptance criteria covered (AC1–AC24)" while `test-results.json` marks AC20
`covered: false` (see friction #6), and the scaffold `CLAUDE.md` references
`docs/pipeline-deployment-targets.md`, which does not exist in the project tree (the
bootstrap memory template references it too — it's an engine-repo doc leaking into
project scaffolds).

---

## 3. Friction inventory — improvisation and human intervention beyond the two designed checkpoints

1. **Seven cap-out resumes** (run-log lines 3, 4, 5, 11, 13, 17, 19). Each required the
   orchestrator to observe the cap, log the `log-run.sh <stage> "" capped` breadcrumb
   (visible in meterly's `settings.local.json` allow-list), and resume with a fresh
   cache-cold agent. The breadcrumb protocol itself worked — all 7 caps are in the log.
2. **The smoke.env rewrite.** Verified root cause chain: `bootstrap-project.sh:96` writes
   `SMOKE_BUILD_CMD='$BUILD'` verbatim; its own usage doc (line 18) recommends exactly
   the fatal form (`'python -c "import app.main"'`); `smoke-check.sh:51` expands the
   variable **unquoted** (`if ${SMOKE_BUILD_CMD:-…}`), word-splitting the nested quotes
   into a `SyntaxError`; and bare `python` was not the project venv. ⚠ The original
   broken file content is testimony (it was overwritten in-run); the mechanism is
   verified from the two scripts, and the current `smoke.env` shows the working
   venv-explicit `-m` form.
3. **Marker-guard false positive on its own scaffold.** Verified: the meterly copies were
   reworded in-run (`scripts/ci/guard-source-markers.sh` comments now circumlocute the
   marker spellings; `.github/workflows/pipeline-ci.yml:201` step renamed to
   "Experimental-revert / must-not-ship markers…"), regex untouched. The template
   source is **still self-breaking**: `~/.claude/pipeline-templates/ci/pipeline-ci.yml:194`
   step name contains the literal "do-not-commit", `~/.claude/hooks/guard-source-markers.sh`
   prose spells out the markers, and the EXCLUDE regex covers
   `global-hooks/guard-source-markers\.sh` but **not** the `scripts/ci/` copy that
   bootstrap creates. Next greenfield bootstrap reproduces the false positive.
4. **Security agent's temp-file leak into the repo tree** (first pass wrote scanner output
   under a literal `C:/Users/...` directory in the repo root). ⚠ Partially verified: the
   directory is gone (removed in-run) — corroborated by `files_changed` dropping 119 → 118
   between debugging attempts 2 and 3, but the path itself is testimony. Important
   correction to the retrospective's proposed fix: **the rule already exists** —
   `security.md` line 50: "Tool output goes to the scratchpad, never the repo tree
   (audit E4)". The agent violated existing prose; more prose is not the fix (→ F7).
5. **AC-PERF punt-then-retry.** ⚠ The initial "no k6 available" punt is testimony;
   corroborated by testing attempt 1 capping (line 11), attempt 2 carrying no perf block,
   and `test-quality.json`'s AC6 gap phrased "real measurement **now taken**". The
   orchestrator had to supply the grafana/k6-via-Docker recipe explicitly.
6. **AC20 counting judgment call — verified, and the sharpest finding in this run.**
   `test-results.json` records `criteria_covered: {total: 24, covered: 24}` while its own
   `by_id` entry for AC20 says `covered: false` ("security agent's step 6g deliverable").
   The testing agent's contract (`testing.md`) says an out-of-suite criterion must be left
   uncovered — but doing so honestly would have **wedged the loop forever**, since
   `covered < total` blocks GREEN and no test will ever cover an ASVS-reconciliation
   criterion. The schema has no way to say "delegated." The agent chose a generous
   numerator; the gate (`deployment-gate.sh:36-41`) compares only the two integers and
   never recomputes from `by_id`, so the inconsistency sailed through, and
   `pr-description.md` repeated "All 24 covered" to the human reviewer.
7. **Approval-marker friction for the orchestrator.** ⚠ The retrospective says the
   orchestrator's `touch .pipeline/plan-approved` was denied. I could not verify the
   mechanism: `guard-approval-markers.sh` is wired (agent frontmatter) only on subagents;
   the settings deny rules cover the `Write`/`Edit` tools, not main-thread Bash; no
   main-thread hook exists in any settings file. The denial was plausibly a permission
   prompt. What IS verified is a four-way documentation contradiction: the guard header
   says markers are created "ONLY by the human, on the un-hooked main thread";
   SKILL.md step 1c shows a bare `touch` with no actor; SKILL.md step 0b instructs *the
   orchestrator* to write `design-approved` via a redirect (the exact pattern the guard
   blocks in subagents); the bootstrap memory template says the human runs `touch`; and
   the session memory from M2 says the orchestrator records markers when Brett says
   "continue" in chat.
8. **Manual run-summary re-run.** Verified: `run-summary.json` `generated_at:
   21:25:10Z` — after deployment passed at 21:20:36Z — while SKILL.md step 4c places
   the only scripted generation at loop-GREEN (20:50), before documentation and
   deployment had run. Without the manual re-run the summary would have been missing
   two stages.
9. **Telemetry identity quirks** (minor, mechanisms verified in `log-run.sh`): the two
   deployment lines carry `files_changed: 0` (the tree is clean post-commit; the count
   is `git diff HEAD` + untracked) and `feature` flips from `main` to
   `feature/usage-metering-ingest` mid-run (feature is derived from the current branch,
   which deployment creates), splitting one feature's identity across two keys — which
   also means `log-run.sh`'s attempt counter restarted at 1 for deployment.

---

## 4. Verdict per pipeline component

| Component | Verdict | Basis |
|---|---|---|
| Planning + plan-audit | **Working as designed** | 1 invocation each, 0 caps; plan-audit did real registry verification (22/22 PyPI lookups) and correctly recommended no revision. Caveat: it audits plan *structure*, not architecture — the deploy-topology assumptions that became findings #2/#10 were never stated in the plan for it to check. |
| Implementation | **Worked but expensive** | 5 invocations / 3 caps / 78 min for a 100+-file greenfield feature against `maxTurns: 40`. Recovery protocol worked; the cost is repeated cold context. |
| Smoke gate (hook) | **Working as designed** | Deterministic, caught a real boot failure, wrote `smoke-status.json` on every path. |
| bootstrap-project.sh (smoke wiring) | **Failed silently** (until smoke tripped) | Emits an unvalidated `SMOKE_BUILD_CMD` and *documents* the self-breaking form; the failure surfaced one stage later as an implementation smoke fail costing a resume cycle. |
| Security stage — scanners (Semgrep/OSV/Gitleaks/Checkov/Trivy + hook floors) | **Working as designed** | OSV caught the one gating CVE; the floors (CVSS ≥7, ASVS-SAST, lockfile) all evaluated; 45 warnings honestly carried. Scanners cannot see the four missed classes — that is a scope boundary, not a malfunction. |
| Security stage — reconciliations (STRIDE 6d/6f, ASVS 6g, input/data surface) | **Failed silently** | Reported 15/15 mechanisms verified, everything reconciled, on a tree containing an inert RLS backstop, an unenforced append-only declaration, an ALB-IP-keyed throttle, and two facade-contract drifts. Presence-checking passed where efficacy-checking would have failed. |
| Testing stage | **Worked but expensive; one silent arithmetic failure** | Caught the NameError production bug and produced an honest, disclosed perf measurement — but wrote a `criteria_covered` numerator its own `by_id` contradicts (forced by a schema gap), and capped once. |
| Debugging stage | **Working as designed** | Both remediations root-caused with fails-before/passes-after proof; found and fixed a second latent bug (Redis test isolation); removed the security stage's tree junk. 1 cap. |
| Run-to-condition loop + loop-guard | **Working as designed** | Deterministic exit, GREEN at cycle 3/5, compute budget (the intended primary bound) at 68%; the append-only journal recorded the completion. The 86%-consumed wall clock is the absolute backstop doing its job under cap-resume latency, not a defect — but it would likely have tripped at cycle 4–5 (see fix plan F9 note). |
| Loop-exit ≡ deploy-gate invariant | **Working as designed** | The predicate in SKILL.md lines 61–71 matches `deployment-gate.sh` conjunct-for-conjunct; deploy-only extras (waiver authenticity, ASVS-SAST floor, markers, quality honesty, diff currency) are documented as deploy-only. |
| Deployment gate — criteria check | **Failed silently** (this run) | `covered >= total` on trusted integers passed a numerator contradicted by the same file's `by_id`. Nothing recomputes. |
| Deployment gate — perf pairing | **Working as designed** | Verified semantics: it gates measurement *completeness + scenario disclosure*, explicitly not the verdict (`perf.status: "fail"` shipped with the miss disclosed in the PR). This is the documented intent (gate comments, PR G); confirm it is still the *desired* intent. |
| guard-approval-markers | **Working as designed; documentation doesn't match behavior** | Structural forgery guard held; the actor story for who writes markers is contradicted across four documents (friction #7). |
| guard-source-markers | **Worked, but the template is self-breaking; documentation doesn't match behavior** | Blocks real markers (regression-verified in-run) yet false-positives on its own scaffold; the durable fix exists only in meterly's reworded copies, not in the templates that seed the next project. |
| Documentation stage | **Worked but expensive; one honesty defect** | 2 invocations for a 1-minute completion after a 25-turn cap; repeated the misleading "All 24 covered" claim into the human-facing PR description. |
| Deployment stage | **Worked but expensive** | Capped at `maxTurns: 15` doing a scripted commit/push/PR, then finished in 36 s. |
| Telemetry (log-run, run-summary, breadcrumbs) | **Worked, with quirks** | All 7 caps captured via the manual breadcrumb protocol; auto-derived models prevented misattribution; feature-identity split, deployment `files_changed: 0`, and the one-shot summary stamp are known distortions (friction #8/#9). |
| Human checkpoints (plan, diff) | **Working as designed** | Both exercised; diff checkpoint received the /code-review findings and the human made an informed defer decision. |

---

## 5. Retrospective accuracy assessment

The retrospective was substantially accurate — every number I re-derived matched
(20 lines, 7 caps, per-stage table, loop figures, remediation counts). Corrections and
unverifiable items: security reported clean **three** times, not "twice" (item 4);
the security temp-file rule it proposes already exists in `security.md` (item 5); the
original smoke.env bytes, the temp-file path, the AC-PERF punt dialogue, and the
mechanism of the orchestrator's marker denial are testimony I could not independently
confirm (items 2, 5, 8, 9 — each marked ⚠ above). Its wall-clock framing (item 7)
under-credits the existing compute-budget design, which already excludes human-wait.

**Proposed remediations: see `.pipeline/pipeline-fix-plan.md`.**

---

## 6. Second-pass addendum (deeper verification: raw scanner outputs, artifact mtimes, hook ordering, plan.md)

A re-audit pass over evidence the first pass had only sampled. Five new findings; none
overturn a first-pass verdict, two add verdicts.

### A. Security report claims tool executions its artifacts contradict — new *failed silently / docs-don't-match-behavior*

`security-report.md` (pass 3, 20:27Z) states: *"Docker Desktop was running; Semgrep,
Gitleaks, and OSV all executed."* Artifact mtimes (UTC):

| tool | claimed on pass 3 (20:28Z) | artifact evidence |
|---|---|---|
| Gitleaks | executed | `gitleaks.json` 20:22:26Z ✓ re-ran |
| ASVS-SAST hook | executed | `asvs-sast.json` 20:28:30Z ✓ re-ran (Stop hook) |
| OSV | executed | `osv.json` **19:10:29Z — pass 2, 78 min earlier; never re-written** ✗ |
| Semgrep | executed, "0 findings, 0 errors" | **no pass-2/3 output exists anywhere in `.pipeline/`**; only the pass-1 `semgrep.err` (18:39Z) survives — the pass-1 `semgrep.json` was the file leaked into the repo tree and deleted, and any later runs went to the session scratchpad (now gone). Unverifiable. |
| Checkov / Trivy | **honestly disclosed as carried forward** (byte-identical infra) | 18:40–18:42Z ✓ consistent |

The *result* was almost certainly unaffected (the lockfile was byte-identical to pass 2,
so pass-2's `osv.json` legitimately covers it — the exact justification the report
itself used for Checkov/Trivy), but the report asserted **execution** where the evidence
supports **carry-forward**. The same overwrite-in-place pattern means no pass-1/pass-2
`security-report.md` survives at all — this run's security evidence trail cannot be
independently reconstructed, which is the M2 evidence-loss lesson recurring inside a
single run. Verified positive: pass-1 `semgrep.err` shows "Findings: 8 (8 blocking)"
over 96 files — matching `semgrep_findings: 8` in the status file.

### B. The loop has no written route for "clean but predicate-failing" — orchestrator improvised (correctly)

Security pass 1 (18:49:36Z) reported `status: "clean", critical: 0` **while the
starlette CVSS 7.5 stood** — explicitly anticipated by the gate's B6 comment ("even when
status:'clean'") and by `security.md`, which lets a dependency CVE coexist with `clean`.
But the SKILL loop's written routing covers only two cases: `issues-found → debugging`
and test `fail → debugging`. For clean-but-CVSS≥7 the written sequence would proceed to
testing, fail the GREEN check, and re-enter security — which would report clean again,
forever. The run-log shows what actually happened: security pass 1 → **debugging at
19:01** (the starlette remediation), an improvised route that appears nowhere in
SKILL.md. It worked because this orchestrator was sensible; the contract has a hole a
weaker orchestrator would loop in.

### C. Final-pass telemetry under-reports retries — hook-order artifact

Testing's Stop array runs `stamp-ran-at → record-clean → log-run` (frontmatter,
verified). On the final clean pass, `record-clean.sh` zeroes `debug_retry_count`
**before** `log-run.sh` reads it: run-log line 16 (the 83/83 pass) records
`retries: 0` for a cycle that consumed 2 remediations (lines 13–15 say `retries: 2`).
Any per-run retry analysis based on final-pass lines under-counts. (`stamp-ran-at.sh`'s
"ordering is not load-bearing" comment is true for `ran_at` but false for `retries`.)

### D. The topology gap starts in the plan — and plan-audit has no dimension that could catch it

`plan.md` names the ALB in its own architecture diagram ("ALB — forwarded request →
API") and even justifies ElastiCache because in-process rate-limit state "fails open
behind the ALB" (line 311) — yet specifies Tier-1 as "IP+route-keyed" with **no
statement of how client IP is derived behind that ALB** (no ProxyHeaders /
X-Forwarded-For / forwarded-allow-ips anywhere in 55 KB). Implementation faithfully
implemented the letter of the plan (`request.client.host`), and plan-audit's checklist
has no topology dimension, so both upstream nets passed the defect through. Deferred
finding #2 was *planted at planning time*.

### E. STRIDE presence-verification was structurally unable to fail on three of the missed findings

The plan's own mechanism cells show why 15/15 verified was compatible with inert
controls: **D1** "Tier-1 IP + Tier-2 per-key Redis token buckets" — present (and keyed
on the ALB node's IP); **E1** "app role without `BYPASSRLS`" — true and irrelevant
(the role *owns* the tables; non-FORCE RLS doesn't apply to owners); **R1** "append-only
`events` (immutable source of truth)" — nothing enforces it and UPDATE/DELETE is
granted; **I3** "Sentry `before_send` strip" — present, missing query_string/url. In
all four, the *named mechanism exists*, so a presence check must pass. This is the
strongest evidence for fix P0-2: the reconciliation step needs efficacy questions, and
the conventions need to make plans state the enabling conditions (IP derivation, FORCE +
ownership, REVOKE) so presence checks have something falsifiable to verify.

### Corrections to first-pass text

None required; finding A upgrades the security stage's *reporting* to its own verdict
row: security reconciliations remain **failed silently**, and the security **report's
tool-execution claims** are additionally **documentation doesn't match behavior**.
One ambiguity worth a doc decision (fix plan P2-6): `security.md`'s description says the
agent "fixes exploitable vulnerabilities directly," yet the gating starlette CVE was
routed to debugging — pick one story for gating dependency CVEs and write it down.
