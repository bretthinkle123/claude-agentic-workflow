# M4 proof run — plan (brownfield run #4: first scorecard run of the proof gate)

> **Purpose.** M4 is the codified next validation run (the name is woven through 6 engine
> files — it is the proof run, not an engine track). It is the **first of the 2–3
> consecutive runs** the proof gate requires before the pipeline may claim 10/10, and the
> first run on the **combined overhaul**: the 22 M3 U-fixes (PR #34, `fix/m3-unified-v2`),
> the TA tooling/adaptation track (PR #35, `feat/ta-overhaul`), and the SK enrichment
> (PR #36, `feat/sk-enrichment`). Attribution across the three is accepted as blurred
> (settled 2026-07-07) — M4 measures the *system*, not the individual PRs.
>
> **Brownfield by design** (per `.pipeline/pipeline-fix-plan-final.md`): diff-scoped
> scanning, existing HEAD, a different failure surface than run 1's greenfield. Runs 2–3
> were already brownfield increments; M4 continues on the same corpus so the cross-run
> trend line stays comparable.
>
> Log findings as **F-M4-…** into §8 of `pipeline-june-analysis.md`; ledger deltas into
> `docs/finding-ledger.md` (the M4 audit MUST verify every M4 escape became a row —
> audit-over-audit is how U-10 is proven). Audit **from disk**, never from the producing
> session's self-report.

## Decisions taken by this plan (say "change X" to override)

1. **Brownfield base = `meterly-pipeline-test`** (still on GitHub, updated 2026-07-06).
   Clone it fresh into a throwaway working copy **keeping its history** — brownfield
   means existing HEAD, prior migrations, and the accepted app-backlog findings in the
   tree. `examples/meterly/` holds only run evidence (no app tree), so the GitHub repo is
   the only brownfield source — **do not delete it before M4**.
2. **Feature = per-customer metric quotas** (see below). Chosen to touch every new
   machinery axis at once; alternatives (billing/CSV export, webhooks) exercise less.
3. **AWS delivery half: skipped.** All six proof-gate criteria are pre-merge-measurable.
   The Phase-B-style AWS execution (deploy/canary/DR/DAST L2-L3) remains a separate,
   still-unexecuted workstream — it is not a proof-gate input and would confound the
   scorecard with infra noise.
4. **No design source.** Run 3 covered the design-spec path; M4's PROJECT.md declares
   `Design source: none` so the run stays on the daily-loop shape.

## The feature: per-customer metric quotas

One thin vertical slice on the existing app:

- `PUT /v1/quotas` (admin-scoped API key) — set `{customer_id, metric, limit_per_window}`.
- Ingestion enforcement: `POST /v1/events` returns **429 + a quota error envelope** when
  the current-window rollup for that customer/metric would exceed the quota. Unquoted
  customers are unlimited (no behavior change).
- One migration: a `quotas` table (expand-only; no backfill needed).

Why this slice hits every M4 measurement surface:

| Surface | How the feature exercises it |
|---|---|
| Brownfield increment | Touches the hot ingestion path, existing auth, existing rollup reads — diff-scoping, SCAN_BASE, incremental docs all get a real increment |
| Perf-budgeted AC (U-07) | Quota check sits on `POST /v1/events` — the existing "p95 < 50 ms under load" budget now covers new code; watch whether the k6 recipe + `.perf.scenario` appear **unprompted** |
| U-03 pilot material | A data-path read (rollup count) feeding state-changing logic (reject/accept) with a window-boundary — exactly the query class R2-1/R3-1 escaped through |
| Data classification | `limit_per_window` + admin-key scoping: does planning classify the new stored fields and the new privilege tier unprompted? |
| api-edge / STRIDE enabling conditions | A new 429 path interacts with the existing throttle — the plan must state which fires first and key derivation (the U-02 topology class) |
| Test-first + adversarial charter (A-2) | Boundary-rich logic (window edges, concurrent posts racing a quota edge) — real material for the adversarial "what does this test not catch" pass |
| Requirements-elicitation (C-1/A-1, first live run) | The brief above is deliberately thin: window semantics, race behavior at the quota edge, admin-key provisioning, and 429-vs-throttle precedence are all **left unstated** for the interview to surface |

## Run discipline

- **Bare orchestrator prompt (U-12 acceptance).** Kick off with only the standard
  orchestration entry — zero re-teaching. The three behaviors that graduated from
  prompts to definitions must persist on their own; any re-teach you're tempted to type
  is itself a finding.
- **Operator-invoked pre-step:** run `requirements-elicitation` first (its first real
  execution — grade the interview quality in the scorecard), answer honestly and
  minimally, let it write `.pipeline/requirements.md`.
- **Under-specify on purpose.** PROJECT.md/brief state budgets and intent, never
  recipes. Watched derivations: the k6 recipe (U-07), new-field data classification,
  DAST-readiness ACs on the changed surface, quota-vs-throttle precedence contract.
- **Two human checkpoints only** (plan, diff). Any other intervention = an improvised
  intervention = a scorecard fail on criterion 2. If unavoidable, journal it verbatim —
  it is the finding.
- **Deliberate micro-test:** at the plan checkpoint, attempt the human
  `touch .pipeline/plan-approved` once and record what happens — settles the M3
  "what actually denied the touch" unknown (U-04/P2-1 residual).

## What M4 must measure (the codified experiment conditions)

**1. The proof-gate scorecard** (from the fix plan — a miss on any row resets the
consecutive-run count after its fixes land):

| Criterion | Threshold |
|---|---|
| Cap-out tax (`capped_lines / log_lines`) | **< 10%** |
| Improvised interventions beyond the 2 checkpoints | **0** |
| Security catches efficacy-class defects | ≥ 1 caught pre-/code-review, **or** /code-review confirms zero escapes |
| Report-claim reconstructability | every "executed"/"covered"/"verified" claim artifact-backed (scan-log, by_id, ledger) |
| Evidence preservation | full run reconstructable after session teardown |
| Ledger | every escape has a row + action |

**2. U-03 correctness-review pilot** (advisory, this run only — already wired into the
orchestration SKILL): after implementation passes smoke, before arming the loop, one
scoped review over the diff's data-path queries + state-changing logic. Record
**catch-vs-cost** in the retrospective. **Coordination flag (from the TA audit):**
evaluate U-03 **together with A-2's test-first charter** — decide keep / drop / subsumed;
do not let them silently duplicate.

**3. U-06 documentation-model experiment:** documentation runs `sonnet` @ maxTurns 25
(the shipped experiment condition). Cap gone ⇒ keep sonnet (or trial haiku@35 for cost);
cap persists ⇒ revert haiku @ 35. **One variable, this run decides.** Also assert
`.pipeline/implementation-progress.md` exists post-implementation (the A-2 test-first
trail lives there too — the pipeline still makes its single commit at deployment).

**4. U-13 doc-identifier check calibration:** it runs **warn-only** this run. Collect
its false-positive/true-positive tally from the run artifacts; the promote-to-exit-2
decision happens in the M4 retrospective.

**5. TA machinery, first live validation:**
- `repomix` pack (`.pipeline/repomix-pack.xml`) produced by the orchestrator pre-step and
  actually read by planning (main-thread pre-step — planning has no Bash).
- `ast-grep` invoked by security (the one agent-invoked B-tool).
- `tasks.md` size trigger: a thin feature **should NOT trigger it** — a tasks.md
  appearing on this slice is a threshold-calibration finding, not a pass.
- Warm-resume (C-2) on any cap-out: the resumed agent reads the progress file instead of
  re-deriving (compare resume-turn burn vs runs 1–3).
- U-14 skip disclosure: DAST-L1/design-review skips must be **recorded**, not silent
  (R3-tel/R3-tel2 regression check); if DAST-L1 runs, verify `target_reached`.
- U-16 telemetry: capped lines carry no stale artifacts; `skipped` field present in
  test-results.

**6. SK delta:** the `code-standards` YAGNI section is the one enrichment — grade
whether the R2-9/R2-10 over-engineering class (dead contract fields, copy-pasted deps,
1:1 wrappers) shrinks. Also watch U-21 rule-of-two: no fourth fork of the k6 harness.

## Instrumentation — rule 0 is non-negotiable (the M2 lesson)

- **Journal + evidence live in the engine repo** (`examples/meterly/run-journal.md`,
  `examples/meterly/run-evidence/m4/`), never only in the throwaway. Commit + push the
  moment anything is observed. A number living only in a terminal doesn't exist.
- **Snapshot before anything overwrites:** `.pipeline/*`, `run-log.jsonl`,
  `loop-events.jsonl`, `run-summary.json`, `scan-log.jsonl` + archived per-attempt
  security reports (new U-09 artifacts — M4 is their first real preservation test),
  coverage + test/security reports → `run-evidence/m4/`, committed, before teardown.
- **From-disk audit** fills the scorecard; quote every number from
  `run-summary.json` / `run-log-digest.sh`, never hand-write (the B7 rule).
- 60-second end-of-phase check: journal current? snapshot pushed? terminal-only numbers?

## Per-stage scorecard (grade 1–5 during the from-disk audit)

Same anchors as M3 (3 = acceptable, 5 = passes senior human review as-is), one evidence
sentence each: requirements-elicitation (new row — did the interview surface the planted
ambiguities?), planning (derivations unprompted? repomix pack consumed?), plan-audit
(flags material, U-13 signal quality), implementation (mergeable? YAGNI delta? test-first
trail real?), U-03 pilot (catch-vs-cost), security (efficacy questions answered per
category, ast-grep used, reconciliation clean), testing (adversarial charter output in
`test-quality.json`, perf unprompted, break 3 tests by hand), documentation (sonnet
experiment; identifier check tally), deployment gate (delegated-criteria arithmetic on a
real run). Then the cross-run table: runs 1–3 vs M4 on wall-clock, cap-outs, human
turns, loop iterations, findings, coverage, scorecard average.

## Success = boring

M3's definition stands: the audit of a proof-gate run should be boring. Success is all
six scorecard rows green **plus** honest ledger rows for whatever /code-review still
catches (it was 3-for-3 sole catcher of each run's deepest bug — zero escapes would be
surprising; *undocumented* escapes are the failure). A run that trips a criterion is not
a wasted run: its fixes land, the count resets, M5 goes again.

## Prerequisites (do in order, before bootstrap)

1. `bash tests/run-eval.sh` green on current main.
2. **Publish:** `bash scripts/install-global.sh` + restart, so the run tests the merged
   engine (main currently has PRs #34–36 merged but the installed copy may predate
   them). Record the engine SHA in the journal.
3. Optional housekeeping: delete the merged `feat/ta-overhaul` / `feat/sk-enrichment`
   branches (local + remote).
4. Clone `meterly-pipeline-test` fresh; verify HEAD matches run 3's final state; branch
   per the normal pipeline flow.

## Deliverables

1. `examples/meterly/run-evidence/m4/` + journal entries (rule 0).
2. §8 entry "M4 run (Meterly quotas)" with F-M4-* findings + the filled scorecard +
   cross-run table.
3. Ledger deltas section for M4 (audit-over-audit proof).
4. Four explicit decisions recorded in the retrospective: U-03 keep/drop/subsume (with
   A-2), U-06 documentation model, U-13 promote-or-not, and proof-gate run 1 of 2–3
   **pass/reset**.
5. If the run passes: M5 planning is just "run it again" — the next brownfield increment
   on the same corpus, no new machinery. If it resets: a fix PR first, then M4'.

## Explicitly out of scope

The AWS delivery half (deploy/canary/load/DR/DAST L2-L3 — separate workstream, still
never executed end-to-end); any design-source feature; the red-team app itself (it
starts only after the proof gate holds — it is the pipeline's first real customer, not
its test subject); iOS/macOS-bound gate adapters.
