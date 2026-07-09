# M4′ fix plan — clearing the M4 audit findings before proof-gate run 1 retry

> Inputs: `examples/meterly/run-evidence/m4/AUDIT-REPORT.md` (incl. §7b re-audit deltas),
> §8 "M4 run (Meterly quotas)" in `pipeline-june-analysis.md`, the 13 M4 ledger rows.
> Goal: every fix lands with a deterministic check or eval so M4′ can go six-for-six on the
> proof-gate scorecard **without gaming any metric**. Findings are grouped into four PR-sized
> tracks + operator actions. Each item names its finding, the change, where, and its
> stays-fixed mechanism (the U-23/static-suite pattern).

**Verdict being fixed:** RESET — criterion 1 (cap tax 37.5% vs <10%) and criterion 5
(transcript preservation) missed. Everything else passed; the app-quality axes were the best of
the series. This plan is engine/process work only — zero app code.

---

## Track 1 — PR: telemetry + evidence determinism (fixes the criterion-5 class)

| # | Finding | Change | Stays-fixed mechanism |
|---|---|---|---|
| 1.1 | F-M4-3 / M4-tel1 — parallel Stop hooks let log-run read a stale smoke-status (`status:"unknown"`, `suspected_underlog:1`) | **Freshness wait in `log-run.sh`**: when deriving implementation status, poll `smoke-status.json` until its `ran_at`/mtime ≥ the hook's own start time (bounded, ~15 s), else log `status:"pending-smoke"` — never `unknown` from staleness. (Root cause is concurrent same-event hook execution — do NOT "fix" by re-ordering frontmatter; order isn't sequencing.) | New eval: `tests/suites/telemetry` case — stale smoke-status + fresh stop ⇒ no `unknown` line |
| 1.2 | F-M4-8 / M4-tel2 — stale `run-summary.json` quoted as current (35.7% vs true 37.5%) | `run-summary.sh` becomes part of every snapshot: orchestration SKILL's snapshot step and the 6b post-deployment step both **re-run it before copying**; the script stamps `log_lines_at_generation` so a mismatch with the live log is detectable | Static-suite check: snapshot dirs' run-summary `log_lines` == line count of the run-log.jsonl beside it |
| 1.3 | F-M4-9 / M4-tel5 — U-13 warn-only tally unreconstructable (stderr only) | `check-doc-identifiers.sh` also writes `.pipeline/doc-identifiers.json` (`{checked, unresolved[], ran_at}`); documentation's report quotes it; M4′ retro decides promotion on a real tally | Existing `doc-identifiers` eval suite gains an artifact-exists assertion |
| 1.4 | F-M4-7 / M4-tel4 — 14/34 transcripts empty at teardown (recovered post-hoc 2026-07-09; root cause: preservation grepped the parent session JSONL instead of copying the per-agent store) | New `scripts/preserve-transcripts.sh`: copy from `<session>/subagents/agent-<id>.jsonl` (named agents) + `<session>/tool-results/<id>.txt` (task results), **assert non-empty bytes**, flag byte-identical pairs (the `b79on0wti`≡`bl2q7axu7` case was identical at source — flag, don't fail), write a sha256 manifest into INDEX.md, exit non-zero on empty/missing. Orchestration SKILL's teardown step calls it (rule 0) | The script IS the check; add a static-suite smoke test with a fixture dir |
| 1.5 | F-M4-1 — unchecked cwd precondition at kickoff | Orchestration SKILL pre-flight (before the repomix pre-step): assert `git rev-parse --show-toplevel` is the repo whose `.pipeline/state.json` feature matches PROJECT.md's feature slug; print all three and STOP on mismatch | Eval: gate suite case with a mismatched state.json |
| 1.6 | F-M4-4 root cause / M4-tel3 — run-3 `__pycache__` bytecode survived conversion and seeded a false claim | **(moved to the pre-flight, not bootstrap — plan-audit 2026-07-09):** bootstrap's contract is explicitly non-destructive, so the purge lives in the orchestration pre-flight beside 1.5: delete `__pycache__/`, `*.pyc`, `.pytest_cache/`, `.hypothesis/` before kickoff (junk by definition — all regenerable) | Pre-flight suite case: seeded stale .pyc ⇒ gone before planning |
| 1.7 | **M4-1 (ledger row had no plan item — plan-audit catch)** — CI coverage floor unenforced: `<COVERAGE_FLOOR>` never filled, no `--cov-fail-under`, coverage job green vacuously | Two-part: (a) `pipeline-ci.yml` template gains a first step in every enabled job that fails on unfilled `<PLACEHOLDER>` tokens (vacuous-green becomes red); (b) the testing agent fills `COVERAGE_FLOOR` from CLAUDE.md's done-bar when it first writes test-results | `ci-scan-base`/static suite case: template with a live placeholder in an enabled job ⇒ fail |

## Track 2 — PR: cap policy (fixes criterion 1 — the reset driver) — **needs one human decision first**

Mined demand vs current budgets (AUDIT-REPORT §7b.5):

| stage | maxTurns now | observed demand (M4) | proposed |
|---|---|---|---|
| security | 30 | ~38–45 | **45** |
| testing | 50 | ~70–75 | **75** |
| documentation | 25 | ~37–40 | **40** (sonnet — see decision 2 note: haiku@35 *and* sonnet@35 would likely still cap; @40 is the honest single-variable trial) |
| debugging | 30 | ~35 | **40** |
| planning / plan-audit | 30 / 20 | no caps ×2 runs | unchanged |
| implementation | 60 | ~130+ turns / ~250 tool uses | **unchanged cap + per-task invocation** (below) |

- 2.1 **Implementation goes per-task when `tasks.md` exists** (F-M4-11): one invocation per task
  boundary (T1…Tn), same warm agent continued via the existing C-2 path, each segment ending in a
  clean Stop under budget → run-log records n `pass` lines, 0 caps. A cap then *means failure*
  again, instead of "feature bigger than one context window". This is the structurally honest fix:
  no realistic single budget fits ~130 turns, and tasks.md already exists exactly for this.
  *Design note (plan-audit 2026-07-09): smoke-check fires at every segment Stop, so each task
  boundary must leave the app bootable and the suite green — which is exactly the A-2 test-first
  contract already in force (M4's T1–T5 each ended green). State it explicitly in the segment
  prompt so a mid-task stop is never a "clean" stop.*
- 2.2 **The metric decision (operator, before M4′ — do not decide silently):**
  - *(recommended)* keep `capped_lines / log_lines < 10%` as-is; with Track-2 budgets + per-task
    implementation, projected M4′ caps ≈ 0–1 on ~20 lines — passable without redefinition; or
  - redefine the numerator to *unplanned* caps only (a planned-segment Stop is not a cap). Defensible
    — but it's a proof-gate criterion; changing it is itself a scorecard event and must be recorded
    in the M4′ run plan.
- 2.3 **Codify "sanctioned escalation" for criterion 2** in the M4′ run plan: a pipeline-initiated,
  journaled-verbatim escalation answered by option-selection (no re-teaching) does not count as an
  improvised intervention. M4's AC20 adjudication becomes the named precedent instead of a judgment
  call.

## Track 3 — PR: agent/skill semantics

| # | Finding | Change |
|---|---|---|
| 3.1 | F-M4-5 / re-audit 3 — ast-grep "optional adjunct" never fired | `security.md`: replace "optional" with a **trigger condition** — *when the diff touches SQL/queries, RLS/migrations, or async entrypoints, run the `ast-grep-rules` pack and stamp a scan-log line via a new `ast-grep-scan.sh` wrapper* (same pattern as `semgrep-scan.sh`/`osv-scan.sh`; advisory: still excluded from status counts). *Plan-audit note: verify `reconcile-scans.sh` tolerates an unknown/advisory tool line in scan-log.jsonl before shipping — the U-09 count reconciliation must not break on the new tool name.* Eval: security suite case asserts the scan-log line when a fixture diff touches a migration |
| 3.2 | Decision 1 — U-03 subsume into A-2 | Remove the pilot block from `pipeline-orchestration/SKILL.md:280`; fold its checklist (data-path reads feeding state changes, window boundaries, lock/snapshot semantics, production-shaped fixtures) into the A-2 test-first charter in `implementation.md` **and** testing's adversarial charter — the checklist survives, the ~54k-token stage does not |
| 3.3 | F-M4-4 / M4-tel3 — unverified environment claims propagated report-to-report | One rule added to `code-standards` + testing/implementation defs: *a report claim about the tree/environment must cite the command that verified it this session; claims inherited from another report must be re-verified or attributed* ("per implementation's progress file, unverified") |
| 3.4 | F-M4-6 — **CONFIRMED not consumed (recovery pass): planning tried `Read(repomix-pack.xml)`, got "too large to read whole", and fell back to 30 direct file reads.** The pre-step produced a 149k-token pack its only consumer cannot ingest | Two-part fix: **(a) size the pack to fit** — orchestrator pre-step runs `repomix --compress` (or `--include` scoping to the feature's likely surface) with a hard budget ≈ 40k tokens, falling back to a directory-tree + public-API summary if still over; **(b) evidence by construction** — planning records the pack's sha256 + file/token counts in `plan.md` frontmatter; plan-audit verifies the sha matches disk |
| 3.5 | F-M4-2 (downgraded, re-audit 1) — tasks.md AC-leg trigger | Drop (or raise to 25) the AC leg in `planning.md:336`; keep the ≥25-file leg. Rationale recorded: AC count measures planning's own granularity, and M4 showed the file leg + per-task invocation (2.1) carry the value |
| 3.6 | Criterion-5 hygiene | The AUDIT-HANDOFF template gains a "transcript integrity verified (non-empty, deduped, manifest)" checkbox wired to 1.4 |

## Track 4 — PR: evals that make the classes permanent (U-23)

- 4.1 F-M4-10a — planted **dead-flexibility knob** (parameter asserted to a constant by its own
  test) in the eval corpus; graded against the code-standards YAGNI section.
- 4.2 F-M4-10b — planted **harness fork** (near-duplicate k6 script + fixture) ; graded against
  U-21 rule-of-two. If the eval alone doesn't move behavior in M4′, escalate to a duplication
  lint scoped to `tests/integration/k6/` (the ledger M4-3 action's second stage).
- 4.3 F-M4-3 — deterministic race regression: fixture with stale smoke-status + fresh stop
  (belongs to 1.1's suite; listed here for the ledger's eval-defect action).

## Operator actions (no PR; two are perishable)

1. ~~Perishable — codeburn export of the empty transcripts~~ **DONE (2026-07-09, audit
   session):** 13/14 recovered from `<session>/subagents/`; `b01lex8rm` has no source anywhere
   (unrecoverable, impact nil); the `b79…`≡`bl2q…` duplicate is identical at the platform
   source, nothing lost. Question (a) resolved: pack NOT consumed — too large (see 3.4).
   Remaining optional analytics: per-stage token economics from the recovered transcripts
   (TA/B-6 measured-cost column) — can be mined any time now that the files are committed.
2. **Diff approval → deployment → post-deployment addendum** in the throwaway: unblocks the 6b
   re-stamp, deployment-gate grading, and criteria 4–6 finalization (the M4 RESET is unaffected).
3. **Three retrospective sign-offs**: U-03 subsume (3.2), documentation = sonnet@40 as M5's
   single variable (Track 2 table), and the criterion-1 metric decision (2.2). Say "change X"
   on any of these; Tracks 1/3/4 don't depend on them, Track 2 does.

## Sequencing

1. Tracks **1 + 3** in parallel (independent; both small, deterministic).
2. Track **2** after the metric decision (2.2) — it's the only blocking input.
3. Track **4** last (evals reference the Track-3 wording).
4. `bash tests/run-eval.sh` green → `install-global.sh` → restart → **M4′** on the same corpus,
   same feature class (next thin brownfield slice), same bare-prompt discipline.

## Exit criteria — what "clean" means for M4′

| Criterion | Projected after this plan |
|---|---|
| 1. Cap tax < 10% | budgets fit observed demand; implementation segments are planned passes → expected caps 0–1 of ~20 lines |
| 2. Improvised interventions = 0 | unchanged behavior + codified escalation definition (2.3) removes the adjudication ambiguity |
| 3. Efficacy catch | machinery unchanged (it passed); ast-grep now actually fires (3.1) |
| 4. Reconstructability | 3.3 + 3.4 close the two blemish classes (environment claims, unprovable consumption) |
| 5. Evidence preservation | 1.2 + 1.4 + 3.6 make staleness and empty/duplicate transcripts fail loudly at teardown, not at audit |
| 6. Ledger | unchanged process; M4 rows already carry actions that this plan implements (M4-tel1..5, M4-3/4) |

If M4′ then goes six-for-six, it counts as proof-gate run 1 of 2–3 and M5 is "run it again."

---

## Implementation readiness (plan-audit pass, 2026-07-09 — verified against engine source)

Feasibility confirmed per item; exact touch points:

| Fix | Files to change | Verified |
|---|---|---|
| 1.1 | `global-hooks/log-run.sh` (~line 112: the implementation case whose comment *asserts* the false sequential-hook assumption — "writes this fresh on every run") | race applies only to implementation (security/testing statuses are agent-written pre-Stop, not sibling-hook-written) |
| 1.2 | `scripts/run-summary.sh` (+`log_lines_at_generation`); orchestration SKILL snapshot steps (the 4c/4d block ~line 182 already documents the miss-late-stages hazard — wire the re-stamp there) | ✓ |
| 1.3 | `global-hooks/check-doc-identifiers.sh`; `tests/suites/` doc-identifiers suite exists (9 cases) | ✓ |
| 1.4 | new `scripts/preserve-transcripts.sh`; teardown step in orchestration SKILL | copy sources confirmed real: `<session>/subagents/agent-<id>.jsonl`, `<session>/tool-results/<id>.txt` |
| 1.5+1.6 | orchestration SKILL pre-flight: cwd/state.json/PROJECT.md identity assert + cache purge | ✓ |
| 1.7 | `templates/ci/pipeline-ci.yml` placeholder-guard step; `global-agents/testing.md` fills `COVERAGE_FLOOR` | ✓ |
| 2 budgets | one-line `maxTurns` frontmatter edits: security 45, testing 75, documentation 40, debugging 40 | ✓ |
| 2.1 | orchestration SKILL implementation-stage block + `global-agents/implementation.md` (segment contract: green suite at every boundary) | ✓ |
| 2.3 | M4′ run-plan template text (sanctioned-escalation definition) | ✓ |
| 3.1 | `global-agents/security.md:53`; new `global-hooks/ast-grep-scan.sh` (pattern: `semgrep-scan.sh`); **pre-check `reconcile-scans.sh` tolerance for the new tool line** | wrapper pattern exists ✓ |
| 3.2 | orchestration SKILL ~line 280 (remove pilot); `implementation.md` + `testing.md` (fold checklist) | ✓ |
| 3.3 | `global-skills/code-standards/SKILL.md` + testing/implementation defs (one rule) | ✓ |
| 3.4 | orchestration SKILL repomix pre-step (`--compress` flag confirmed available in repomix 1.16) + `planning.md` frontmatter contract + `plan-audit.md` sha verify | ✓ |
| 3.5 | `global-agents/planning.md:336` (drop/raise the AC leg) | ✓ |
| 4.x | `tests/agent-evals/` corpus (existing layout: one dir per planted defect — add `impl-dead-knob/`, `impl-k6-fork/`); 1.1's race fixture in `tests/suites/telemetry` | corpus layout confirmed ✓ |

Order of work: Track 1 → Track 3 → Track 2 (budgets + 2.1) → Track 4 → `bash tests/run-eval.sh`
green → `install-global.sh` → restart → M4′. Defaults applied unless overridden: criterion-1
metric kept as-is (2.2 recommended option); documentation sonnet@40; U-03 subsumed.
