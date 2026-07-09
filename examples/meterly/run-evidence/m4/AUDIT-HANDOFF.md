# M4 audit handoff — Meterly per-customer metric quotas (proof run 1 of 2–3)

Written by the orchestrating session at the diff checkpoint, for a FRESH session to run the
from-disk audit. **Audit from disk only — never from the producing session's self-report**
(`docs/m4-proof-run-plan.md` rule; this file is a map, not evidence).

## Run state at handoff

Pipeline complete through the M5 diff-review checkpoint. Loop exited GREEN at cycle 3/5;
DAST L1 within budget; documentation + pr-description done; /code-review pre-step done
(8 advisory findings, 0 new CONFIRMED correctness bugs). **Pending at handoff:** human
`diff-approved` → deployment (commit + PR) → 6b run-summary re-stamp → §7 ledger deltas →
final `.pipeline` snapshot. If those have since happened, the journal below has entries past
Entry 12 and fresher evidence copies — always audit the LATEST journal/evidence state.

## Where everything lives

| What | Where |
|---|---|
| Run plan (the experiment definition) | `docs/m4-proof-run-plan.md` |
| Journal (M4 Entries 0–12+, all interventions verbatim) | `examples/meterly/run-journal.md` |
| All run artifacts (plan, acceptance ×2 forms, reports, telemetry, DAST, PR text) | `examples/meterly/run-evidence/m4/` |
| Subagent transcripts (33 final-message logs + ID→stage index) | `examples/meterly/run-evidence/m4/transcripts/` + `INDEX.md` |
| Original (pre-revision, absolute-AC20) acceptance.md | git history — Entry 4 commit `dcfd919`; revised form is the current file |
| Run-3 baseline for the cross-run table | `examples/meterly/run-evidence/m3-final-pipeline/` |
| Findings log target (§8) + ledger | `pipeline-june-analysis.md` §8, `docs/finding-ledger.md` |
| Throwaway repo (working tree, `.pipeline/` live state, branch `feature/metric-quotas`) | `c:\Users\brett\OneDrive\Documents\GitHub\meterly-pipeline-test` (base `faabe9d`; run-3 state preserved on `archive/run3-final` + engine snapshot) |

## What the audit must produce (per the run plan)

1. **Proof-gate scorecard** (all six criteria; a miss on any row = reset of the consecutive-run
   count). Known at handoff, verify from disk: cap-out tax **5/14 = 35.7% vs <10% threshold —
   criterion 1 fails as it stands** (recompute from the re-stamped post-deployment
   run-summary.json; also identify `suspected_underlog: 1`). Criterion 2: two sanctioned
   checkpoints + ONE debugging escalation (AC20 budget decision, Entry 10) + interview answers
   (Entry 2, operator pre-step) + option-selections — adjudicate. Criterion 3: security's
   FORCE-RLS owner-bypass catch (Entry 8) — grade efficacy-class. Criteria 4–6:
   reconstructability / evidence preservation / ledger rows.
2. **Per-stage scorecard** (1–5 + one evidence sentence each): requirements-elicitation (first
   live run — Entry 2), planning, plan-audit, implementation, U-03 pilot, security, testing,
   documentation, deployment gate. Then the cross-run table (runs 1–3 vs M4).
3. **Four explicit decisions:** U-03 keep/drop/subsume with A-2 (early signal in Entry 7:
   subsume — the deepest bug died in-stage via test-first, pilot's net add was one latent pin);
   U-06 documentation model (cap PERSISTED on sonnet@25 — Entry 12); U-13 promote-or-not
   (tally the warn-only run: note the doc agent itself caught+fixed a stale `--key_id` claim);
   proof-gate run 1 of 2–3 **pass/reset** (cap-tax row alone likely forces reset — if so, the
   deliverable is the fix list, then M4′).
4. **F-M4-\*** findings into §8 + **ledger deltas** (every escape a row with an action).

## Pre-logged candidate findings (verify, then number as F-M4-\*)

- **cand-1** kickoff has an unchecked cwd precondition (Entry 3) — orchestrator caught manually.
- **cand-2** tasks.md large-feature trigger fired on a thin slice (Entry 4) — calibration.
- **cand-3** log-run/smoke-check Stop-hook order race → implementation final logged "unknown" (Entry 7).
- **cand-4** testing agent fabricated an environmental claim ("stray dashboard files", Entry 9).
- Plus graded surfaces: U-21 rule-of-two breach (k6 fixture+JS forks, /code-review findings 3–4);
  YAGNI delta not clean despite SK enrichment; warm-resume C-2 worked (compare resume burn vs M3).

## Open transcript-level questions (transcripts/ has the material)

(a) Did planning actually READ `.pipeline/repomix-pack.xml`? (measurement surface 5)
(b) Did security invoke `ast-grep`? (check scan-log.jsonl + its transcripts)
(c) The cand-4 false claim — final-message transcripts may not suffice; full traces are in the
operator's local session JSONL (ask the operator for a codeburn export if needed; also wanted
for the retrospective's measured-cost column, TA/B-6).

## Numbers discipline

Quote every quantitative claim from `run-summary.json` / `run-log.jsonl` /
`run-log-digest.sh` output — never from prose, including this file's (B7 rule).
