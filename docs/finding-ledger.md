# Finding ledger — the net that grows

Every verifier-CONFIRMED /code-review finding and every production incident gets one row
here, so a class of bug that escaped once becomes a permanent check instead of costing a
full audit to rediscover. This is the mechanism (U-10) behind the pipeline's
correct-in-operation goal: without it, each new escape class is re-learned from scratch.

## The rule

- **When:** at the end of every run (the retrospective's "ledger deltas" section prompts
  it), and whenever a production incident is triaged.
- **What:** one row per confirmed finding — `finding` (file:line + one line), `class`,
  `escaped-because` (why every gate missed it), `action`.
- **`action` MUST be one of:**
  - *efficacy-question* — a new named question in security 6d (U-02) / a convention;
  - *eval-defect* — a new planted defect in the `tests/agent-evals/` corpus (U-23);
  - *deterministic-check* — a new gate/hook/suite;
  - *accepted:<reason>* — an explicit decision that no check is worth it (app-scope,
    too-brittle-to-gate, one-off) with the reason.
- **`tests/suites/static.sh` asserts** the ledger exists and every row has a non-empty
  action — an escape with no decision is itself a defect.

Rows are append-only history; a fixed row keeps its entry (mark the action done).

---

## Seed — the 30 M3-series findings (runs 1–3)

Legend for `action` origin: fixes shipped in the unified plan are named (U-xx); app-scope
findings are `accepted:app-backlog` (a future feature run, never pipeline work).

### Run 1 — greenfield (usage-metering ingest)

| # | Finding | Class | Escaped because | Action |
|---|---|---|---|---|
| R1-1 | `alembic/…0001:66` RLS ENABLE-not-FORCE + app role owns tables ⇒ backstop inert | DB-privilege | STRIDE 6d checked presence, not FORCE-vs-ownership; RLS test passed vacuously | efficacy-question (U-02 DB-privilege) + eval-defect (U-23 security-rls) |
| R1-2 | `src/api/middleware.py:118` Tier-1 throttle keyed on ALB node IP (no proxy-header trust) | deploy-topology | no scanner models "behind a load balancer"; plan never stated IP derivation | efficacy-question (U-02 topology) + convention (api-edge enabling conditions) + eval-defect (U-23 security-topology) |
| R1-3 | `src/api/middleware.py:68` body cap reads only Content-Length; chunked bypass ⇒ OOM | input-validation | tests sent Content-Length bodies only | accepted:app-backlog |
| R1-4 | `src/auth/api_key.py:70` Argon2id verify sync on the event loop | async-runtime | measured p95 miss attributed wholly to shared-host contention | efficacy-question (U-02 async-runtime) + eval-defect (U-23 security-async) |
| R1-5 | `src/config/secrets.py:80` sync boto3 get_secret_value on the loop | async-runtime | same class as R1-4 | efficacy-question (U-02 async-runtime) |
| R1-6 | `src/auth/rate_limit.py:157` fail-open on blanket except; rate_limit>0 unvalidated | resilience | no test drove a persistent limiter error | accepted:app-backlog |
| R1-7 | `src/observability/sentry.py:21` before_send misses query_string ⇒ PII leak | contract-drift | scrubber checked headers/body only | efficacy-question (U-02 contract-drift) + eval-defect (U-23 security-scrub) |
| R1-8 | `src/db/session.py:32` DB URL resolved once; contradicts rotation contract | contract-drift | cross-module drift invisible to per-file scanners | efficacy-question (U-02 contract-drift) |
| R1-9 | `infra/…data/main.tf:84` events append-only declared but UPDATE/DELETE granted | DB-privilege | "append-only" was a STRIDE claim with no enforcement | efficacy-question (U-02 DB-privilege) + convention (STRIDE enabling conditions) |
| R1-10 | `src/api/middleware.py:91` `/health/ready` not throttle-exempt (ALB probe) | deploy-topology | probe-exemption never stated in plan | efficacy-question (U-02 topology) |
| R1-tel | criteria_covered 24/24 recorded while by_id AC20=false | gate-arithmetic | gate compared two trusted integers | deterministic-check (U-01) |
| R1-tel2 | security report claimed OSV/Semgrep executed; artifacts were a prior run's | scan-evidence | no recount, no execution stamp | deterministic-check (U-09) |

### Run 2 — brownfield (GET /v1/events)

| # | Finding | Class | Escaped because | Action |
|---|---|---|---|---|
| R2-1 | `events_repo.py:153` window_start coarse filter drops rows near hour boundaries | gates-green-but-wrong | planning claimed "provably implied" (false); aligned-clock fixtures can't catch it | deterministic-check (U-03 proof-claim) + eval-defect (U-23 plan-audit-proof) |
| R2-2 | `events_repo.py:155` OFFSET pagination over a live window dup/skips under ingest | correctness | AC2 test used static data | accepted:app-backlog |
| R2-3 | `events_list_service.py:48` has_more=true on last page advertises a 422 page | correctness | boundary arithmetic untested | accepted:app-backlog |
| R2-4 | `events_list.py:33` populate_by_name accepts undocumented from_ts/to_ts | contract-drift | schema-vs-OpenAPI drift | accepted:app-backlog |
| R2-5 | READMEs name `create_or_replay_event`/`window_start_utc` (don't exist) | doc-invention | nothing checked documented identifiers | deterministic-check (U-13) + eval-defect (U-23 doc-invented-name) |
| R2-6 | `events_list_service.py:32` MAX_OFFSET enforced against a throwaway computation | correctness | duplicated arithmetic | accepted:app-backlog |
| R2-7 | `test_events_list_perf.py:46` ~120 lines duplicated; scenario still named 'ingest' | test-duplication | no rule against forking harnesses | convention (U-21 rule-of-two) |
| R2-8 | `test_events_list_endpoint.py:77` raw-SQL seed repeated 5× | test-duplication | same class as R2-7 | convention (U-21) |
| R2-9 | `events_repo.py:101` triple 1:1 row repr; timestamps typed str ⇒ OpenAPI loses format | quality | style, not correctness | accepted:app-backlog |
| R2-10 | `routes/events.py:26` auth+throttle dep copy-pasted; docstring claims DRY | quality | rule-of-three | accepted:app-backlog |
| R2-tel | capped testing line carried the prior run's "142/142 passed" + coverage | telemetry | log-run read a stale artifact on a capped line | deterministic-check (U-16d) |

### Run 3 — first design-source (usage dashboard)

| # | Finding | Class | Escaped because | Action |
|---|---|---|---|---|
| R3-1 | `dashboard_service.py:189` reader-key BFF empty in prod; tests seed as the reader | gates-green-but-wrong | tests encoded the production topology as a passing isolation test | deterministic-check (U-03 cross-feature trace) + convention (U-03 production-shaped fixtures) + eval-defect (U-23 fixture-mask) |
| R3-2 | `dashboard_service.py` day fan-out ~264 txns, per-request semaphore, fail-open ⇒ pool exhaustion | async-runtime/DoS | anonymous endpoint, no load test at fan-out | accepted:app-backlog |
| R3-3 | `dashboard_service.py:118` day delta compares partial vs full prior day | correctness | boundary logic untested | accepted:app-backlog |
| R3-4 | `dashboard_reader.py:49` reader resolution blocks the loop + memoization stampede | async-runtime | same class as R1-4 | efficacy-question (U-02 async-runtime) |
| R3-5 | `services/README.md` invented `get_usage_series(principal,params)` sig + false "validates" | doc-invention | existence check alone would pass a real name with a wrong signature | deterministic-check (U-13 signature compare) + eval-defect (U-23 doc-invented-name) |
| R3-6 | `scripts/seed_api_key.py:45` --write-to-secret bypasses the SecretsFacade | contract-drift | facade contract not reconciled to consumer | efficacy-question (U-02 contract-drift) |
| R3-7 | `test_dashboard_perf_k6_load.py` k6 harness forked again; docstring dropped | test-duplication | third fork; no rule | convention (U-21) |
| R3-8 | `schemas/dashboard.py:101` config.granularities dead contract field; UI ignores it | contract-drift | UI/server drift | accepted:app-backlog |
| R3-9 | `middleware.py:45` page CSP coupled to routes only by hardcoded strings | quality | brittle coupling | accepted:app-backlog |
| R3-10 | `dashboard.js:224` client retry after config-fetch failure is a dead loop | correctness | no loading-state test | accepted:app-backlog |
| R3-tel | DAST scanned only 404s (target `/`, page at `/dashboard`); "within budget" vacuous | opt-in-stage-misconfig | health precheck passed; scan target never verified | deterministic-check (U-14 target_reached) |
| R3-tel2 | design-review (FE Layer 4) silently skipped on the first design-source run | opt-in-stage-skip | no ui.env, no record of the skip | deterministic-check (U-14 disclose-the-skip) |
| R3-tel3 | test-results 161 total / 160 passed / 0 failed — 1 test silently unaccounted | telemetry | schema had no skipped field | deterministic-check (U-16g) |

---

## Ledger deltas — M4 and beyond

Add a section per run. The M4 audit MUST verify every M4 escape became a row here with an
action — audit-over-audit is how the net is proven to be growing, not just claimed.

### M4 — brownfield proof run 1 (per-customer metric quotas), audited 2026-07-09

Rows written by the M4 from-disk audit (`run-evidence/m4/AUDIT-REPORT.md`). The 8 review rows
are the /code-review pre-step findings (0 new CONFIRMED correctness bugs — first run where the
early layers starved the late review; the deepest bug, the EvalPlanQual stale-join, died
in-stage via A-2 test-first and never escaped, so it gets no row). Deployment was pending at
audit; re-verify this section post-deployment.

| # | Finding | Class | Escaped because | Action |
|---|---|---|---|---|
| M4-1 | `pipeline-ci.yml` coverage floor unenforced — `<COVERAGE_FLOOR>` placeholder never filled, no `--cov-fail-under` anywhere, contradicts CLAUDE.md's 85% done-bar (pre-existing, inherited) | gate-arithmetic | no stage owns filling CI placeholders; the job is green vacuously | deterministic-check (CI-template lint: fail the pipeline-ci job if placeholders remain in enabled jobs; testing stage fills the floor) |
| M4-2 | `events`/`usage_rollup` RLS is ENABLE-only — inert for the owning role (pre-existing, outside diff; security flagged, PR carries the follow-up) | DB-privilege | outside the diff scope; R1-1's fix in run 1 predated the FORCE lesson | accepted:app-backlog (follow-up migration named in pr-description.md) |
| M4-3 | k6 harness forked a 4th time — perf fixture ~90-line copy-paste + `load_events_quota.js` near-duplicate, drift already present (/code-review #3) | test-duplication | U-21 rule-of-two is a convention with no teeth; implementation never consulted it under cap pressure | deterministic-check candidate (duplication lint scoped to `tests/integration/k6/`) + eval-defect (U-23 planted harness-fork) — final form decided at the M4 retrospective |
| M4-4 | `_quota_perf_workers()` dead-flexibility knob asserted away by its own test (/code-review #4) — R2-9/R2-10 class despite the SK YAGNI enrichment | quality | skill guidance alone doesn't bind mid-implementation | eval-defect (U-23 planted dead-knob) |
| M4-5 | `QuotaUpsertOutcome` pattern divergence from the codebase's existing outcome idiom (/code-review #5) | quality | style-level; no gate models idiom consistency | accepted:app-backlog |
| M4-6 | `src/api/routes/`+`src/api/schemas/` READMEs missing while sibling dirs got them (/code-review #6) | doc-completeness | doc agent capped mid-READMEs; resume prioritized updates over gaps | accepted:app-backlog (next doc pass) |
| M4-7 | isolation-test teardown singleton mismatch (/code-review #7) | test-hygiene | no runtime symptom yet | accepted:app-backlog |
| M4-8 | duplicate baseline k6 run wastes ~25 s per suite run (/code-review #8) | efficiency | harmless-but-wasteful class not gated | accepted:app-backlog |
| M4-tel1 | run-log line 5: implementation attempt 3 `status:"unknown"` stamped 5 s before smoke-status.json's pass — log-run/smoke-check Stop-hook read race (F-M4-3) | telemetry | log-run trusts whatever smoke-status is on disk at hook time | deterministic-check (log-run freshness check: refuse/retry a smoke-status older than the stage stop) |
| M4-tel2 | run-summary.json snapshot stale (generated pre-documentation); journal + handoff quoted 35.7% where the log says 6/16 = 37.5% (F-M4-8) | telemetry | summary is stamped once, snapshots copy it uncritically | deterministic-check (snapshot step re-runs run-summary.sh; audit rule already recomputes) |
| M4-tel3 | "stray dashboard files" environmental claim propagated implementation→testing reports unverified; root cause = Entry-3 conversion missed `__pycache__` purge, leaving run-3 dashboard .pyc on disk (F-M4-4) | report-accuracy | agents repeat prior-report environment claims without disk verification; the journal's own check missed bytecode | convention (environment claims in reports must be disk-verified) + deterministic-check (conversion/bootstrap purges `__pycache__`/build caches) |
| M4-tel4 | 14 of 34 preserved transcripts are 0-byte files; INDEX claims all 33 preserved; blocked the repomix-consumption question (F-M4-7) | evidence-preservation | preservation grepped the parent session JSONL instead of copying the per-agent store (`<session>/subagents/`); nothing asserted non-empty | deterministic-check (preserve-transcripts.sh copies subagents/ + tool-results/, asserts non-empty; m4-prime-fix-plan 1.4) — **recovery done 2026-07-09: 13/14 recovered + committed; b01lex8rm unrecoverable (no source, impact nil)** |
| M4-tel5 | U-13 doc-identifier warn-only tally unreconstructable — hook writes stderr only, nothing persisted (F-M4-9) | evidence-preservation | warn-only channel has no artifact | deterministic-check (hook also writes `.pipeline/doc-identifiers.json`) |
