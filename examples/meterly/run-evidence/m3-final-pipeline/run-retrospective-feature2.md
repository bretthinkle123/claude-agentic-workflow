# Pipeline run retrospective — Feature 2: GET /v1/events (2026-07-06)

Companion to `run-retrospective.md` (feature 1 / the M3 run). Same audience: the session
auditing and fixing the pipeline. This run is the **brownfield control case** — same
pipeline, same machine, but an existing codebase and a small scoped feature — so
differences from feature 1 isolate what was greenfield-cost vs pipeline-cost.

## Outcome

- Feature: GET /v1/events — paginated, time-range, tenant-scoped listing. 4 source
  files, no migrations, no new dependencies.
- All gates GREEN; loop exited in **1 cycle, 0 remediations** (feature 1: 3 cycles, 2).
- Human reviewed the diff + findings and approved **as-is** (explicitly prioritizing
  pipeline evaluation over app polish); the 10 review findings below are deferred.
- Deployment/PR/merge status: see the addendum at the bottom (written after deploy).

## Per-stage data (quote .pipeline/run-log.jsonl lines for feature/events-listing)

| stage | attempts | caps | model | notes |
|---|---|---|---|---|
| planning | 1 | 0 | opus | single pass; flagged Q1 (missing index) as material open question |
| plan-audit | 1 | 0 | sonnet | 2 advisory flags, 0 material; independently re-verified plan's factual claims against code |
| implementation | 1 | 0 | sonnet | **single pass, no cap-outs** (feature 1: 3 caps). Smoke ran in real-server mode, passed first try |
| security | 1 | 0 | opus | first-pass clean; diff-scoped (4 files); correctly skipped Checkov/Trivy (no infra in diff); no temp-file leak this time |
| testing | 2 | 1 | sonnet | 1 cap-out (fixture SQL); 59 tests added, honest scale disclosure on perf |
| documentation | 2 | 1 | haiku | 1 cap-out almost immediately after start |
| deployment | see addendum | | | |

Loop: `loop-state.json` cycles 1/5, status completed. `run-summary.json` regenerated at
loop-GREEN; regenerate again post-deployment for final numbers (known feature-1 retro
item 10 — the tool undercounts if not re-run).

## Pipeline-engineering observations (delta vs feature 1)

1. **Cap-outs dropped from 7 to ~3** with a small brownfield feature. Supports the
   hypothesis that feature-1's cap storm was scope-size, not agent defect — but
   testing and documentation still capped on a SMALL feature, so the caps are tight
   even at this size. Documentation capped ~30 tool-uses in on a trivial incremental
   update; its budget looks mis-sized regardless of scope.

2. **Feature-1 lessons applied via prompt DID work** — evidence that agent-definition
   fixes would stick: (a) security agent told "temp output to .pipeline/ or OS temp"
   → no repo-tree leak this run; (b) testing agent told "mark delegated criteria
   explicitly" → it did (AC16/AC17 mapped to shared tests with reasons, no silent
   counting); (c) testing agent given the k6-via-Docker recipe upfront → real perf
   measurement first try, no punt-and-retry round-trip. All three are currently
   orchestrator-prompt knowledge; they belong in the agent definitions / skills so
   they don't depend on the orchestrator remembering.

3. **THE HEADLINE: gates GREEN, review caught a CONFIRMED silent-data-loss bug.**
   All 5 /code-review finder angles independently converged on
   `src/repositories/events_repo.py:153` — the `window_start` coarse filter drops
   rows when app-clock and DB-clock straddle an hour boundary (window_start is floored
   app receive-time; event_time is DB now()). Why every gate missed it:
   - **planning** itself introduced the flaw and claimed it "provably implied" — the
     plan's correctness argument was wrong, not missing;
   - **plan-audit** verifies claims are PRESENT and traced, not that they are TRUE —
     structural audit, not semantic;
   - **testing** seeds writes and reads with the same aligned clock, so the two-clock
     divergence is structurally untestable by the suite as designed;
   - **security** scans for vulnerability classes, not query-correctness.
   Lesson for the audit session: the /code-review pre-step is load-bearing for
   correctness, not just hygiene. Consider (a) moving a scoped correctness review
   earlier (post-implementation, pre-loop), and/or (b) a plan-audit check that
   "provably X" claims name the invariant AND its enforcement point — this one's
   assumed invariant (window_start == floor(event_time)) was enforced nowhere.

4. **Marker lifecycle friction, second occurrence.** The stale feature-1
   `plan-approved`/`diff-approved` markers could not be deleted by the orchestrator
   (guard denies Bash rm too). The bootstrap doc says the orchestrator removes stale
   markers before a new feature; reality: the human must. Either the guard should
   allow orchestrator DELETION (not creation) of markers, or the docs and
   pipeline-orchestration skill should say "human removes them" — currently a
   documented step the orchestrator cannot perform. (Extends feature-1 retro item 9.)

5. **Feature attribution in run-log fixed by process change:** creating the feature
   branch BEFORE planning (this run) gives clean per-feature log attribution
   (feature-1's lines flipped from "main" to the branch mid-run). Cheap orchestration
   rule worth codifying in the skill: branch first, then plan.

6. **Honesty patterns held under less supervision:** testing disclosed its perf run
   was at a 5,000-event partition vs the plan's ~100k ceiling instead of claiming the
   ceiling; mutation testing honestly skipped again (mutmut needs WSL — recurring
   Windows gap worth a decision: install WSL, pick a Windows-compatible tool, or
   drop the check on win32).

7. **Plan-audit's independent fact-checking earned its keep** (verified index
   composition, RLS wiring, schema regexes against the real tree), and its 0-material
   verdict was consistent with implementation completing in a single pass.

## The 10 deferred review findings (verified; human chose ship-as-is)

Ranked; first three are the correctness set. Full failure scenarios in the PR body.

1. `src/repositories/events_repo.py:153` — window_start coarse filter silently drops
   rows near hour boundaries (two-clock divergence). CONFIRMED by 5/5 angles.
   Violates AC2/AC3; listing can disagree with usage rollup. Fix: drop the two
   predicates or widen bounds ±1h.
2. `src/repositories/events_repo.py:155` — OFFSET pagination over a live window
   (to ≤ now+1h allowed) duplicates/skips rows under concurrent ingest; AC2's test
   uses static data so it passes vacuously. Mitigation: cap to ≤ now (verified: no
   legitimate future event_time exists); narrows but doesn't close the to==now race.
3. `src/services/events_list_service.py:48` — has_more=true on the last permitted
   page advertises a next page the offset cap 422s (offset 10,000 allowed, 10,100
   rejected). Verified arithmetic.
4. `src/api/schemas/events_list.py:33` — populate_by_name=True silently accepts
   undocumented from_ts/to_ts wire params (empirically verified) despite
   extra='forbid'; OpenAPI documents only from/to.
5. `src/services/README.md:14` + `src/repositories/README.md:33,39` — docs updated by
   this diff name functions that don't exist (window_start_utc, create_or_replay_event).
   Grep-confirmed. Documentation agent wrote plausible-but-wrong API names.
6. `src/services/events_list_service.py:32` — MAX_OFFSET enforced in the schema
   against a throwaway computation; service recomputes the executed offset — cap and
   execution tied only by duplicated arithmetic.
7. `tests/integration/test_events_list_perf.py:46` — ~120 lines duplicated from the
   feature-1 perf test; k6 read scenario still named 'ingest' on both JS and Python
   sides (hidden string coupling).
8. `tests/integration/test_events_list_endpoint.py:77` — raw-SQL seeding block
   repeated 6×; belongs in a conftest fixture.
9. `src/repositories/events_repo.py:101` — triple 1:1 row representation with manual
   isoformat(); response timestamps typed str so OpenAPI loses format: date-time.
10. `src/api/routes/events.py:26` — auth+throttle dependency now consumed by a third
    handler via two byte-identical private copies; new docstring claims "defined once
    (DRY)" while the twin exists. (Rule-of-three reached; hoist to src/auth.)

Note for the audit session: finding 5 is a **documentation-agent** defect (invented
API names in a README it was updating) — a pipeline-quality signal, not just an app
bug. Findings 7/8 are **testing-agent** duplication habits — the agent copy-pastes
rather than extending shared fixtures; a test-conventions rule ("extend conftest, not
copy") would likely fix both classes.

## Artifact map (feature 2)

- `.pipeline/plan.md`, `acceptance.md` (18 criteria), `plan-audit.md` — planning set
  (also archived under `docs/decisions/feature/events-listing/`)
- `.pipeline/security-report.md` / `security-status.json` — diff-scoped clean scan
- `.pipeline/test-results.json` (142/142, 90.73% lines, per-criterion by_id map,
  perf block with honest scenario), `test-quality.json` (quality_ok:false, mutmut skip)
- `.pipeline/pr-description.md`, `review-manifest.json` (hash dd09cb2e…), `surface-delta.md`
- `.pipeline/run-log.jsonl` (feature/events-listing lines), `run-summary.json`,
  `loop-state.json`
- Feature-1 baseline for comparison: `run-retrospective.md`

## Deployment addendum

(To be appended after deployment/merge completes.)
