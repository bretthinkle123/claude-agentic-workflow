# M4′ audit handoff — Meterly usage CSV export (proof-gate run 1 of 2–3, post-M4-reset)

Written by the orchestrating session after deployment + merge. **Audit from disk only** —
quote numbers from `run-summary.json` / `run-log.jsonl`, never prose (B7); never trust the
producing session's self-report (this file is a map, not evidence).

## Run state at handoff

Complete end-to-end: plan → plan-audit (+1 revision) → implementation → loop GREEN (cycle 3/5)
→ DAST → documentation → /code-review → human diff-approved → deployment → **PR #3 merged**
(merge `ef3fb3f`, 2026-07-09T21:02Z). Ledger deltas M4P-1…8 written. Engine under test:
`73485d1` (M4′ fix tracks), published pre-run; operator waived the IDE restart (Entry 2 —
in-session evidence + audit watchpoints recorded there).

**OPEN AT HANDOFF — post-merge CI (first-order audit material):** the `pipeline-ci` run on
`feature/usage-export` shows **secrets / sast / deps / containers-iac FAILED, codeql failed on
its literal `<CODEQL_LANGUAGE>` placeholder matrix, build-and-test still in_progress** when
this file was written (check its final conclusion — it carries the M4P-1 perf-flake
prediction). The secrets job's 2 gitleaks hits are the exact test-fixture FPs the local
security stage triaged (fingerprints in the job log; no `.gitleaksignore` channel exists).
The PR merged anyway (no branch protection enforcing the gate). Audit question: the Layer-2
CI merge gate appears to have never been green on this repo (check PR #2's run for the same
cluster) — local↔CI scanner reconciliation and the CI waiver channel are unimplemented
surface, and merges bypass the gate silently.

## Where everything lives

| What | Where |
|---|---|
| Run plan (deltas + watchlist definitions) | `docs/m4-prime-run-plan.md` |
| Journal (M4′ Entries 0–9, verbatim escalation + waiver decisions) | `examples/meterly/run-journal.md` |
| All run artifacts | `examples/meterly/run-evidence/m4-prime/` |
| Transcripts (40 + MANIFEST.sha256, per-agent store copies) | `…/m4-prime/transcripts/` |
| Pre-revision acceptance/plan forms | git history of this directory (Entry 4 commit `6497980`; AC16 revision in later commits) |
| M4 baseline (for the cross-run table) | `…/run-evidence/m4/` + its AUDIT-REPORT.md |
| Findings target + ledger | `pipeline-june-analysis.md` §8, `docs/finding-ledger.md` (M4P rows already written) |
| Throwaway repo | `c:\Users\brett\OneDrive\Documents\GitHub\meterly-pipeline-test` (main @ merge `ef3fb3f`; PR #3; pipeline-ci run logs on GitHub) |

## Scorecard obligations (docs/m4-prime-run-plan.md)

1. **Six criteria.** Known at handoff, verify from disk: **criterion 1 = 3/14 = 21.4%**
   (re-stamped post-deployment run-summary; caps: implementation ×2 attempts 1–2,
   debugging ×1 — vs M4's 35.3%; still >10% ⇒ likely RESET again; the isolated offender is
   the single-shot implementation budget, since per-task segments only engage with tasks.md).
   **Criterion 2:** two checkpoints + ONE pipeline-initiated escalation (AC16 budget,
   Entries 6–7, option-selection, journaled verbatim — sanctioned per the codified 2.3
   definition) + the operator's restart waiver (Entry 2, pre-kickoff operator setup) + the
   mid-run ast-grep install (Entry 6, operator setup, journaled). Adjudicate each.
   **Criterion 3:** candidates — the CSV-injection plant was surfaced by the INTERVIEW and
   planned/implemented as a control (security verified-effective rather than caught-missing;
   grade whether that satisfies the efficacy clause), plus /code-review's 0-CONFIRMED result.
   **Criteria 4–6:** reconstructability / preservation (40 transcripts, manifest, non-empty
   asserted — the F-M4-7 fix's first clean end-to-end run) / ledger (M4P-1…8 present).
2. **Watchlist verdicts** (each fix live-tested this run): repomix receipt ✓ (frontmatter
   sha/counts; 17 tool uses vs M4's 37); no tasks.md on thin slice ✓; ast-grep stamp ✓ (but
   only after a mid-run operator install — the host prerequisite was never provisioned;
   disclosed-skip behavior worked); telemetry unknown-status ✓ eliminated (Entry 5); U-13
   tally persisted ✓ but **FP-dominated** (24 warnings; `async def` tokenizer + arg-parse
   defects — calibration: keep warn-only, fix the checker); documentation cap ✓ flipped
   (uncapped @ 646 s); **0-caps expectation ✗ MISSED** (implementation ×2 + debugging ×1).
3. **Per-stage scorecard + cross-run table** (runs 1–3, M4, M4′).
4. **Explicit decisions:** U-13 promote-or-not (tally says no — checker first); the
   implementation single-shot budget (the remaining cap source — segment-by-default? raise?);
   proof-gate run 1 of 2–3 **pass/reset**.

## Candidate F-M4′ findings pre-logged in the journal (verify, then number)

- Entry 2: IDE-restart waiver — harness caching risk accepted; watchlist presence = proof the
  new engine was live (all watchlist behaviors DID appear ⇒ resolved).
- Entry 5: single-shot implementation budget miss ×2; A-2 progress file absent at cap 1.
- Entry 6: ast-grep host prerequisite missing (operator gap, agent disclosed correctly).
- Entry 8: U-13 checker parser FPs.
- Entry 9: preserve-transcripts.sh resolves session store from CWD (silent no-op from the
  wrong repo — usability).
- This file: the post-merge CI cluster (secrets FP waiver channel, sast full-tree vs local
  diff-scope severity drift, deps/containers-iac failures unexplained at handoff, codeql
  placeholder job never runnable, merge-without-green unenforced).

## Open transcript-level questions

None blocking — the three M4 questions' fixes all produced disk evidence this run. If the
per-stage grading wants turn-level detail, transcripts are complete (one known dual-ID pair
flagged at source in MANIFEST notes).

## Numbers discipline

`run-summary.json` (stages=8, log_lines=14, capped=3, suspected_underlog=0) is the
post-deployment 6b re-stamp — the whole-run truth. Cross-check against `run-log.jsonl`
line count as always.
