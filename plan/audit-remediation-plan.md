# Audit remediation plan — Ledgerly run fcd45e7 (dual-audit consensus)

**Inputs:** two independent audits of the Ledgerly v1 run (2026-07-02), convergent on all
material findings. IDs below reference the shared ledger: app A-N1…A-N7, engine
E1/E3/E4, T1–T4, B3/B6/B7, B-N1.

---

## Plan-audit corrections (this plan was audited before execution)

A skeptical pass over an earlier draft of this plan found seven wrong/unverified claims,
fixed here before implementation:

1. **CVE-floor mirror target was wrong** — "mirror in `record-clean.sh`" was incorrect
   (`record-clean.sh` only resets debug counters, is explicitly *not a gate*). The real
   mirror is the loop-exit security predicate (SKILL + invariant harness). **Applied.**
2. **Hard-gate additions must preserve `loop-exit ≡ gate`** — `loop-exit-invariant.sh`
   asserts three GREEN-predicate copies (gate, SKILL, `loop-exit-predicate.jq`) are
   byte-equivalent. Every hard-gate addition must land in all copies or the loop deadlocks.
   The B6 floor was implemented across all three + the invariant battery. **Applied.**
3. **`run-log-digest.sh` already exists** (`scripts/`, published by `install-global.sh`) —
   T4 is an *enhancement*, not a new ship. **Applied as enhancement.**
4. **`run-eval.sh` already targets `global-hooks/`** (`assert.sh:11 HOOKS=$REPO_ROOT/global-hooks`) —
   no repoint needed; just add suites. **Corrected.**
5. **B3 compute-time formula didn't work** — tick-to-tick elapsed still includes human wait;
   loop-guard alone can't separate compute from wait. **Deferred** (needs per-stage timing
   from `log-run` timestamps — see Deferred section).
6. **WS3-1 hard mutation gate relitigated settled M1 scope** ("advisory quality + hard
   perf-pairing only"). **Deferred / reframed** as a narrow scope-pairing predicate, not a
   general quality hard-gate.
7. **hash-determinism test conflated two bugs** — a spaced filename tests the `xargs` split,
   not locale sort (which needs mixed-case/punctuation names). The suite now covers **both**,
   plus a static regression guard. **Applied.**

## Implementation status (branch `fix/audit-remediation-engine`)

**LANDED + eval-green (10/10 suites pass):**
- **E1** — `compute-change-hash.sh` NUL-safe + `LC_ALL=C sort -z` in **repo-of-record**
  `global-hooks/` and synced to `~/.claude/hooks/`; verified hash-preserving for ordinary
  filenames (no gratuitous re-approval). New `tests/suites/hash-determinism.sh` (static +
  behavioral) would fail against the old bare-`sort` copy.
- **E1-a / B-N1** — `bootstrap-project.sh` now writes `.gitattributes` (`* text=auto eol=lf`),
  sets repo-local `core.autocrlf=false`, and gitignores `reports/`, `scratch_*`,
  `load/results.json`.
- **B6** — deterministic CVE-severity floor (`osv_max_cvss >= 7.0` blocks without
  `osv_waiver`) in `deployment-gate.sh` + mirrored in the SKILL security predicate + the
  invariant harness + `security.md` (agent now emits `osv_max_cvss`/`osv_waiver`) + fixture;
  4 new gate/invariant cases.
- **E3** — new `guard-source-markers.sh` blocks revert/do-not-commit markers in the change
  set; wired as a hard deploy-gate check + Stop-hook on debugging & implementation; gate suite
  case added.
- **T3** — `loop-guard.sh` journals every terminal state to append-only `loop-events.jsonl`;
  `reset` can no longer erase a cap-out; 2 new loop-guard cases.
- **T4** — `run-log-digest.sh` surfaces cap-outs from the journal + flags `unknown`
  status/model lines as suspected cap-outs.
- **WS3-3** — perf-scenario disclosure: `.perf.scenario` required when perf ran, mirrored
  across `loop-exit-predicate.jq` + `deployment-gate.sh` + the SKILL (loop-exit ≡ gate,
  pinned by the 384-permutation invariant battery) + fixture; 2 gate + 2 invariant cases.
- **WS3-1** — mutation scope-pairing: a DEPLOY-ONLY honesty check (deliberately not in the
  loop-exit — quality is settled-advisory and per-loop mutation is the cost problem). Blocks
  only `quality_ok:true` asserted while `mutation.scope` fails to cover
  `mutation.configured_scope`, absent a `quality_waiver`; testing agent now emits
  `configured_scope`/`quality_waiver`; 5 gate cases.

**SECOND BATCH — now also LANDED + eval-green (10/10, 155→169 assertions):**
- **E2** — testing `maxTurns` 30→50 + an explicit incremental-artifact/resume contract in
  `testing.md` (leave a valid `test-results.json` after each sub-step; run cap-prone work
  last) and a "the tree you leave IS the deliverable / prove repros in scratch" contract in
  `debugging.md`. (Full sub-stage split remains an option if caps persist; the budget +
  resume contract is the lower-risk form.)
- **T1/T2** — `log-run.sh` now stamps an `attempt` number per `(feature,stage)` and the
  orchestration SKILL instructs the orchestrator to emit `log-run.sh <stage> "" capped` on
  observing a cap-out, so caps/resumes are distinct countable lines, not silent gaps.
- **T4** — per-tier (`unit`/`integration`) coverage recorded in `log-run.sh` + surfaced by
  `run-log-digest.sh`, which also lists explicit cap-out breadcrumbs.
- **B7** — new `scripts/run-summary.sh` emits `.pipeline/run-summary.json` at GREEN
  (per-stage invocations/attempts/caps/models from the log + loop journal); the SKILL now
  mandates the retrospective quote model/cost from that file, never hand-write it.
- **B3** — `loop-guard.sh` gains a compute-time budget (`max_compute_s`, default 1800) that
  caps each cycle's contribution at `max_cycle_s` (600) so human-wait between ticks no longer
  trips the breaker; wall-clock kept as a generous absolute backstop (7200). 4 new cases,
  incl. the property that a ~28h human-wait gap contributes ≤600s.
- **WS3-2** — adversarial test-shape rules added to `test-conventions` (two-principals-one-IP
  rate-limit, A==A self-reference, per-constraint 4xx sweep, assert-the-loser concurrency,
  replay-body pin, middleware-order-through-lifecycle) — the shapes that would have forced
  the A-N1/A-N2 tests into existence.
- **Hygiene** — `lockfile-check.sh` `sort -u` → `LC_ALL=C sort -u`.

**THIRD BATCH — gaps caught by a self-audit of the implementation:**
- **E5** — `test-conventions` now mandates true-percentile measurement (nearest-rank over
  captured samples; forbid trusting a tool's possibly-absent percentile field — autocannon
  has no p95 bucket, which is how a p97.5 was reported as "p95"; assert measured percentile
  == budgeted percentile). Was missed — WS3-3 only added scenario disclosure.
- **E6** — `test-conventions` + `planning.md` now distinguish create-migration reversibility
  (schema/constraint round-trip; row loss on down expected) from expand/contract (row
  preservation required), and have planning phrase the AC accordingly. Was missed.
- **E4 (second half)** — `security.md` + `testing.md` now instruct routing raw tool output
  (semgrep/OSV JSON, Stryker reports, load results) to the scratchpad, not the repo tree —
  defense-in-depth beyond the gitignore backstop. Was missed.

Verified behaviorally (not just eval): source-marker guard blocks/allows/no-ops correctly;
loop-guard migrates a legacy state file without crashing and excludes human-wait from the
compute budget; log-run attempts increment (1,2,3) with the capped breadcrumb; run-summary +
digest surface caps and per-tier coverage; published `~/.claude` hooks match repo-of-record
(zero drift). E7 covered via WS3-2's assert-the-loser rule; /code-review M5 pre-step already
present.

**ALL pipeline findings from the M2 audit are now implemented.** Only intentionally-out-of-
scope items remain: **WS1 app fixes dropped** (Ledgerly was a pipeline-evaluation trial, not
shipping — its defects mattered only as evidence, now closed by B6/WS3-1/WS3-3/WS3-2), and a
full testing sub-stage split (E2's heavier alternative) is noted as available if the raised
budget + resume contract prove insufficient in a future run.

**Three workstreams:**
1. Fix the Ledgerly app (blockers before multi-tenant use).
2. Fix the pipeline engine (the bugs the run itself surfaced).
3. **Harden the evaluation metrics** — change what "GREEN" measures so these defect
   *classes* can't ship silently again. This is the root-cause layer: every app defect
   that escaped did so because a gate checked an artifact status field instead of the
   property, or a test was shaped to pass.

**Sequencing:** WS2-P0 + WS3 eval-suite additions land first (the engine must be fixed
before it's trusted to fix the app), then republish via `install-global.sh`, then run the
Ledgerly fix PR **through the pipeline itself** as the validation exercise.

---

## Workstream 1 — Ledgerly app (repo: `ledgerly`, follow-up PR on `main` after PR #1)

### PR-A1 (blocker): per-owner rate limit actually keyed by owner — A-N2
- `src/http/rateLimit.ts`: add `hook: "preHandler"` to the route rate-limit config so the
  limiter runs after auth; **remove the `ip:` fallback** — fail closed:
  ```ts
  keyGenerator: (req) => {
    if (!req.principal) throw new UnauthorizedError("auth must precede rate limiting");
    return `owner:${req.principal.owner}`;
  }
  ```
- `src/app.ts` / `src/routes/transfers.ts`: ensure `requireAuth` is registered so it
  precedes the limiter on the same route (route-level `preHandler` array order:
  `[requireAuth, <limiter>]` — @fastify/rate-limit appends, so declaring
  `preHandler: requireAuth` already yields the right order; assert it in the test).
- Optional hardening: add a *global* IP-keyed limiter at `onRequest` for unauthenticated
  traffic (today failed-auth requests are never rate-limited at all).
- **Proving test** (`tests/integration/transfers.test.ts`): two principals, one IP —
  alice exhausts `rateLimitMax` → 429; bob's **POST /transfers** from the same
  127.0.0.1 → 200. Fails on current code (bob shares alice's `ip:` bucket).
  Second assertion: same principal, two spoofed IPs (`x-forwarded-for` off — inject
  `remoteAddress`) still shares one bucket.

### PR-A2 (blocker): self-transfer + unhandled SQLSTATE class — A-N1, A-N3
- `src/routes/transfers.ts` (or the body schema via JSON-schema `not`): reject
  `from_account === to_account` with `ValidationError` (422) before any DB work.
- `src/http/errorEnvelope.ts` (defense in depth): map pg error codes
  `23514` (check violation) and `23503` (FK violation) → 422 envelope instead of the
  500 fallthrough, keeping the server-side log at full detail.
- **Proving tests:** `from==to` with sufficient balance → 422, zero rows written
  (today: 500); credit that would exceed the 10^15 ceiling → 4xx (today: 500).

### PR-A3 (follow-ups, same or next PR)
- **A-N6:** document (or change) replay semantics — replayed responses return *current*
  balances, not at-transfer balances. Cheapest correct fix: persist
  `from_balance/to_balance` on the transfer row at insert time and return those on
  replay; otherwise a README/API-doc note + a test pinning the chosen semantics.
- **A-N7:** add a CI job (not per-loop) running the *already configured* Stryker scope
  (`src/domain/** + src/http/ssrfGuard.ts`) plus `src/services/**` with a long budget;
  fail the job under a threshold (start 75%).
- **A-N5:** add a second load lane: webhook enabled (local sink), mixed
  overdraft/self-transfer rejects, one contended hot account; record both lanes in
  `load/results.json` with scenario flags (see WS3-3).
- qs/uuid dev-CVE bumps (`npm audit fix` scope — dev-only, no urgency, closes the OSV noise).
- A-N4: comment already present at `db.ts:34`; add a lint-style note in the repo README
  that any new bigint column must be capped or the parser scoped per-pool.

---

## Workstream 2 — pipeline engine (repo: `claude-agentic-workflow` → `install-global.sh`)

### P0 — determinism + the shipped-High class
1. **E1 canonical (repo-of-record still broken):** `global-hooks/compute-change-hash.sh:11`
   → NUL-safe, locale-pinned:
   ```bash
   { git diff HEAD 2>/dev/null; git ls-files -z --others --exclude-standard | LC_ALL=C sort -z | xargs -0 -r cat; } | sha256sum | awk '{print $1}'
   ```
   Apply the same line to the published copy so repo == published (they have drifted —
   the published hook has `LC_ALL=C sort` but not `-z`; the repo has neither).
2. **E1-a:** `scripts/bootstrap-project.sh`: write a `.gitattributes`
   (`* text=auto eol=lf`) when absent and `git config core.autocrlf false`.
3. **B6 CVE-severity floor:**
   - `global-agents/security.md`: require `osv_max_cvss` (max CVSS across remaining OSV
     findings, 0 when none) in `security-status.json`, plus an optional
     `waiver: {id, reason, approved_by}` object.
   - `global-hooks/deployment-gate.sh` (mirror in `record-clean.sh`): block when
     `osv_max_cvss >= 7.0` and no waiver — deterministic, independent of the LLM's
     `status` judgment.

### P1 — telemetry that survives cap-outs (T1–T4, T3, B3)
4. **T3:** `global-hooks/loop-guard.sh`: `reset` refuses to destroy a terminal record —
   append the outgoing state to `.pipeline/loop-events.jsonl` before `init_state`, and
   have `mark_capped`/`mark_done` append there too. `loop-state.json` stays the
   current-round view; history is append-only.
5. **T1/T2:** make `log-run.sh` callable with an explicit `--attempt N --status capped`
   by the orchestrator at resume time (Stop hooks can't fire on maxTurns; the
   *orchestrator* observes the cap and must write the breadcrumb). Add `attempt` to the
   line schema.
6. **T4:** ship `global-hooks/run-log-digest.sh`: cross-checks stages the orchestration
   skill says ran vs lines present; prints "suspected cap-out (no Stop line)" rows.
7. **B3:** loop-guard tick takes the *max of per-cycle compute spans* rather than
   `NOW - started_epoch`: stamp `cycle_started_epoch` on each tick and accumulate
   `compute_s += NOW - cycle_started_epoch` at the next tick; cap on `compute_s`.
   Human-wait between cycles no longer trips the breaker.
8. **B7 / auditability:** orchestration skill emits `.pipeline/run-summary.json` at GREEN
   ({invocations, caps, resumes, per-stage wall, model-from-frontmatter}); the
   retrospective template's model column must be copied from run-log/frontmatter, never
   hand-written.

### P2 — guards + hygiene
9. **E3:** new `global-hooks/guard-source-markers.sh` (Stop hook on debugging +
   implementation; also called by deployment-gate): grep `git diff HEAD` +
   untracked source for `\b(TEMP|REVERT|XXX|DO NOT COMMIT|HACK-REMOVE)\b` → exit 2.
   Bake "prove repros in scratch, never in the tree" into `global-agents/debugging.md` +
   `debugging-escalation-protocol`.
10. **B-N1 (E4 completion):** bootstrap `.gitignore` loop adds `reports/`, `scratch_*`,
    `load/results.json`.
11. **E2:** split `testing` into `testing-unit` / `testing-integration` /
    `testing-perf-quality` sub-stages with own `maxTurns` (or raise testing/implementation
    budgets first as the cheap interim); promote "write artifacts incrementally; resume
    from the artifact" from ad-hoc instruction to agent-def contract.

---

## Workstream 3 — evaluation-metric hardening (the "never again" layer)

Each item names the escape it closes.

1. **Mutation-scope pairing gate (closes A-N7's silent scope shrink).**
   The run wrote `quality_ok: true` after Stryker's scope silently shrank from the
   configured `src/domain/** + ssrfGuard.ts` to `money.ts` only. Add to
   `deployment-gate.sh` (advisory→hard, matching the perf-pairing precedent):
   `test-quality.json` must record `mutation.configured_scope` and `mutation.scope`;
   if `scope ⊂ configured_scope` then `quality_ok` must be `false` **or** an explicit
   `scope_waiver` present. The testing agent writes both fields (source of truth:
   `stryker.conf.json` `mutate` globs).

2. **Test-shape rules → `global-project-skills/test-conventions/SKILL.md`
   (closes the shaped-to-pass test class).** New mandatory adversarial cases the testing
   agent must generate and the plan-audit agent must check ACs against:
   - **Rate limiting:** the test must prove the *key dimension* — two principals on one
     IP (distinct buckets) and one principal across two IPs (same bucket). A
     "different owner unaffected" assertion must target the **rate-limited endpoint**
     (AC11's used the unlimited POST /accounts — vacuous).
   - **Self-reference:** any resource-pair operation (transfer, link, merge) gets an
     `A==A` case asserting a 4xx, not 5xx.
   - **Unhandled-SQLSTATE sweep:** every CHECK/FK/UNIQUE constraint in the migration
     must map to a test asserting a 4xx envelope. Constraints are enumerable from the
     migration file — this is mechanical, not judgment.
   - **Assert-the-loser concurrency (E7):** concurrency tests must assert the *loser's*
     status (200-replay/409), not merely "one transfer exists".
   - **Replay-semantics pin (A-N6):** any idempotent endpoint needs a test that pins
     what a replayed response body contains after intervening state changes.
   - **Middleware-order property (A-N2's root cause):** when an AC states an ordering
     property ("per-owner", "after auth"), the test must observe the property through
     the full HTTP lifecycle with the discriminating variable varied (owner vs IP) —
     unit-testing the keyGenerator function alone proved nothing.

3. **Perf-scenario disclosure (closes A-N5's best-case-as-headline).**
   `test-results.json .perf.measured` gains required scenario fields:
   `{webhook_enabled, contention, amount_profile, lanes}`. `deployment-gate.sh` doesn't
   judge them (that's human/review territory) but blocks if they're absent — the same
   pattern as the perf-pairing predicate: you may ship a best-case number, you may not
   ship an *undisclosed* best-case number.

4. **Eval-harness additions (`tests/suites/`) — the engine's own regression net:**
   - `hash-determinism.sh`: change-hash under `LC_ALL=C` vs `en_US.UTF-8`, LF vs CRLF
     checkout, and a filename containing a space → byte-identical (E1 class; fails
     against `global-hooks/` today, proving the repo-of-record gap).
   - `loop-guard.sh` suite: **reset-after-capped preserves the capped record** in
     `loop-events.jsonl` (T3 class — the suite currently only tests `done`-won't-clobber).
   - `marker-guard.sh` suite: add source-marker cases (`// TEMP-REVERT` in a staged file
     blocks) once WS2-9 lands (E3 class).
   - `gate.sh` suite: `status:"clean"` + `osv_max_cvss:7.5`, no waiver → gate blocks
     (B6 class); `mutation.scope` ⊂ configured, `quality_ok:true`, no waiver → blocks
     (WS3-1).
   - `run-eval.sh` runs all suites against **`global-hooks/` (repo-of-record), not
     `~/.claude/hooks/`** — this is what would have caught the E1 published-vs-repo drift.

5. **Publish-drift check:** add `tests/suites/publish-drift.sh` — diff `global-hooks/*`
   vs `~/.claude/hooks/*` and fail on any mismatch. Root cause of "fixed in env, broken
   in repo": the two copies have no consistency check.

6. **Auditability contract (closes the reconstructed-timeline problem):** next run must
   need no archaeology — WS2-5/6/8 give: a line for *every* invocation (capped or
   clean), attempt ids, append-only loop events, `run-summary.json` at GREEN, and
   per-tier coverage recorded in `test-results.json`. Acceptance: an auditor can compute
   invocation/cap/resume counts and per-stage cost from `.pipeline/` alone.

---

## Order of execution

| Step | What | Where | Gate |
|---|---|---|---|
| 1 | WS2-P0 (E1 canonical, .gitattributes, B6 floor) + WS3-4/5 eval suites | engine repo | `tests/run-eval.sh` green, incl. new suites |
| 2 | WS2-P1 telemetry (T1–T4, B3, run-summary) | engine repo | loop-guard + digest suites green |
| 3 | Republish (`install-global.sh`), verify publish-drift suite passes | ~/.claude | drift suite green |
| 4 | WS3-1/2/3 (gate predicates + test-conventions rules) | engine repo | gate.sh suite green |
| 5 | PR-A1 + PR-A2 **run through the pipeline** (dogfood: the new test-shape rules must force the two proving tests into existence) | ledgerly | pipeline GREEN + the two new tests present & passing |
| 6 | WS2-P2 (E3 guard, gitignore, E2 split) + PR-A3 follow-ups | both | marker suite green; mutation CI job runs |

**Success criterion for the whole plan:** re-run both audits' proving probes against the
fixed Ledgerly (from==to → 422; two-principals-one-IP → independent buckets) and re-run
`tests/run-eval.sh` — every finding class from both ledgers has either a passing fix-test
or an explicit, recorded waiver.
