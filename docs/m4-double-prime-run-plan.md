# M4″ proof run — plan (brownfield run #6: proof-gate attempt, post-M4′-reset)

> Derived from `docs/m4-prime-run-plan.md` — everything not stated here carries over
> unchanged (brownfield discipline, rule-0 instrumentation, per-stage scorecard anchors,
> from-disk audit, "success = boring"). M4′ audited **RESET on criterion 1 alone**
> (21.4% cap tax vs <10%; 5/6 criteria held, per-stage avg 4.22) — see
> `examples/meterly/run-evidence/m4-prime/AUDIT-REPORT.md`. The M4″ fix list
> (AUDIT-REPORT §7) is implemented at engine `7149e86` and this run tests it.
> **This is proof-gate run 1 of 2–3 — the count is at zero.**

## Feature: quota administration — list and delete

- `GET /v1/quotas` (admin-scoped API key) lists quotas.
- `DELETE /v1/quotas` removes the quota for `{customer_id, metric}`.
- Existing API-key auth applies. No behavior change to `POST /v1/events` when no quota exists.
- **The pipeline-ci workflow must be green on the PR** (branch protection now makes it a
  required merge check — M4P-16 closed by the operator pre-run). The CI-green line is intent,
  not recipe: how the seed-script import (M4P-9), the fixture-FP ignore entries (M4P-12/13),
  and the perf marker (M4P-10) get resolved is the pipeline's problem, in-run.
- Design source: none. Brownfield base = merged CSV-export feature (PR #3, merge `ef3fb3f`).
- Deliberately thin brief: **tenant scoping of list/delete is deliberately unstated — whether
  one admin key can see or delete another tenant's quotas is the planted efficacy-class trap
  this run (the IDOR/DB-privilege class).** Also unstated for the interview: delete
  idempotency vs 404, pagination, immediate effect on in-flight enforcement, response
  envelope, audit logging of deletes.

## Deltas from the M4′ plan

1. **Scorecard: same six criteria.** Criterion-1 metric (`capped_lines / log_lines < 10%`)
   unchanged. Expectation is **0 caps including implementation** — per-task segments are the
   fix under test (decomposition default at ≥8 estimated files; this feature is ≥8).
2. **Sanctioned-touchpoint definitions now live in the orchestration SKILL** — see
   `global-skills/pipeline-orchestration/SKILL.md` § "Operator touchpoints — what counts as
   an intervention (proof-gate criterion 2)". The audit cites that section; this plan does
   not restate it. (Host provisioning per the F-M4′-5 boundary is defined there too.)
3. **Behavioral-fix watchlist** (each is a named fix under live test; a miss = F-M4″ finding,
   not something to fix by hand mid-run):
   - **`tasks.md` MUST trigger this run** — the feature is ≥8 estimated files, the new
     decomposition default's territory. Planning emits it; implementation runs per-task
     segments, each ending suite-green + bootable and logging a clean `pass` line. Absence
     of tasks.md, or a single-shot implementation, is a watchlist miss.
   - **0 caps expected, including implementation** (the per-task shape restores the cap as a
     pure failure signal; debugging budget raised 40→50 per the M4′ decision).
   - **Doc-contract re-check (step 5a)** runs after documentation and before the diff
     checkpoint (M4P-11 fix: nothing used to re-run tests after documentation's edits).
   - **Security commits ignore-file entries** (`.gitleaksignore` / tool-native equivalents,
     each with a comment naming the triage) for any FP it triages that CI re-scans
     (M4P-12/13 fix — the CI waiver channel, populated in-run).
   - **Timing tests carry the perf marker and CI excludes them** from the `--cov` invocation
     (M4P-10 fix; timing is owned by local runs + the load-campaign workflow).
   - **`preserve-transcripts.sh` uses the run-started filter** — the manifest must contain
     ONLY this run's transcripts (F-M4′-7 fix; M4′ preserved 23 carryover files).
   - **ast-grep stamps even a skip** in `scan-log.jsonl` (disclosed-skip is the contract;
     silent absence is the miss).
   - **U-13 tally re-collected post-parser-fix** from `.pipeline/doc-identifiers.json`;
     still warn-only — the promote-or-not decision re-decides on THIS run's data (M4′ tally
     was FP-dominated: 24 warnings, `async def` tokenizer + arg-parse defects).

## Run discipline (unchanged, restated)

Bare kickoff (U-12): "Run the pipeline from planning for the feature in PROJECT.md." — zero
re-teaching; any tempted re-teach is itself a finding. Operator pre-step: requirements-
elicitation, answered minimally. Two human checkpoints (plan, diff) + sanctioned touchpoints
per the SKILL section cited in delta 2. Mid-run host-tool installs (the ast-grep class) are
sanctioned provisioning — journaled verbatim. Merge only on green pipeline-ci (branch
protection enforces this). Journal + evidence to `examples/meterly/run-evidence/m4-double-prime/`,
committed as observed. From-disk audit fills the scorecard; quote numbers from
`run-summary.json` / `run-log.jsonl` only (B7).

## Success

Six-for-six ⇒ proof-gate run 1 of 2–3 holds and M5 is "run it again." Any criterion miss ⇒
reset again: fix PR first, then M4‴.
