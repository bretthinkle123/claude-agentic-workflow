# M4′ proof run — plan (brownfield run #5: proof-gate attempt, post-M4-reset)

> Derived from `docs/m4-proof-run-plan.md` — everything not stated here carries over
> unchanged (brownfield discipline, rule-0 instrumentation, per-stage scorecard anchors,
> from-disk audit, "success = boring"). M4 audited **RESET** (criterion 1 at 35.3% final;
> criterion 5 process miss, cured) — see `examples/meterly/run-evidence/m4/AUDIT-REPORT.md`.
> The M4′ fix tracks are implemented (`b2eff68` + `53dd128`, stamped `64bd3eb`) and this run
> tests them. **This is proof-gate run 1 of 2–3** (the M4 reset zeroed the count).

## Feature: usage CSV export

- `GET /v1/usage/export` returns the caller's usage rollups
  (`customer_id, metric, window_start, total_quantity`) as CSV.
- Existing API-key auth applies. No behavior change to any existing endpoint.
- Design source: none. Brownfield base = merged quotas feature (PR #2, merge `43da320`).
- Deliberately thin brief: time-range semantics, pagination/size limits, CSV escaping,
  content-type/filename, empty-result behavior, and which key scope may export are ALL left
  unstated for requirements-elicitation to surface. **The CSV-injection surface
  (`=cmd`, `+`, `-`, `@` cell prefixes) is a deliberate efficacy-class plant for security.**

## Deltas from the M4 plan

1. **Scorecard: same six criteria.** Criterion-1 metric (`capped_lines / log_lines < 10%`)
   **KEPT AS-IS** (fix-plan decision 2.2) — the fix was cap policy + budgets, not the metric.
   With Track-2 budgets, the expectation is **0 caps**; any cap is a finding even if the tax
   stays under 10%.
2. **Sanctioned-escalation definition (fix-plan 2.3), now codified:** a **pipeline-initiated**
   escalation (debugging cap-out, unpatchable finding, or an AC that cannot honestly pass),
   journaled **verbatim**, answered by **option-selection** with no re-teaching content, is
   **NOT an improvised intervention** for criterion 2. Anything operator-initiated mid-run, or
   any answer that re-teaches, still counts.
3. **U-13 stays warn-only.** Collect the tally from `.pipeline/doc-identifiers.json` (the hook
   now persists it — F-M4-9 fix); promote-or-not decides on M4′ data.
4. **Behavioral-fix watchlist** (each is a named fix under live test; a miss = F-M4′ finding):
   - **ast-grep**: invocation stamp appears in `scan-log.jsonl` when the diff touches
     SQL/RLS/async code (spec was "optional" in M4 — now required-when-applicable).
   - **repomix**: consumption receipt in `plan.md` frontmatter (M4's pack was produced but
     never readable — pack-sizing fix + receipt requirement).
   - **Budgets hold**: 0 caps expected across all stages (Track-2 cap policy); every cap-out
     breadcrumb + warm-resume still applies if one happens.
   - **No `tasks.md` on a thin slice** — trigger recalibrated to ≥25 files (F-M4-2). The CSV
     export must NOT produce one.
   - **Telemetry**: no `status:"unknown"` lines (F-M4-3 freshness fix); snapshot steps re-run
     `run-summary.sh` before copying (F-M4-8); environment claims in reports disk-verified
     (F-M4-4).
   - **Evidence**: `preserve-transcripts.sh` (now published) used for every snapshot;
     non-empty asserted (F-M4-7).

## Run discipline (unchanged, restated)

Bare kickoff (U-12): "Run the pipeline from planning for the feature in PROJECT.md." — zero
re-teaching; any tempted re-teach is itself a finding. Operator pre-step: requirements-
elicitation, answered minimally. Two human checkpoints (plan, diff) + sanctioned escalations
per delta 2. Journal + evidence to `examples/meterly/run-evidence/m4-prime/`, committed as
observed. From-disk audit fills the scorecard; quote numbers from `run-summary.json` /
`run-log.jsonl` only (B7).

## Success

Six-for-six ⇒ proof-gate run 1 of 2–3 holds and M5 is "run it again." Any criterion miss ⇒
reset again: fix PR first, then M4″.
