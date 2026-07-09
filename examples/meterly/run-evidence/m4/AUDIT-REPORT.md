# M4 from-disk audit — proof run 1 of 2–3 (Meterly per-customer metric quotas)

Audited 2026-07-09 by a fresh session, from disk only, per `docs/m4-proof-run-plan.md`.
Every number below is quoted from `run-log.jsonl`, `run-summary.json`, the stage artifacts in
this directory, the live throwaway `.pipeline/` tree, or the preserved transcripts — never from
journal/handoff prose (B7 rule). Journal and handoff were treated as testimony and re-verified.

**Run state at audit:** pipeline stopped at the M5 human diff-review checkpoint (journal Entry 12
is the latest entry; no `diff-approved`, no deployment, no PR). Criteria 4–6 are therefore
**provisional**; criteria 1–3 are final for this run.

---

## 0. Corrections to the record (testimony vs disk)

1. **The cap-out tax is 37.5%, not 35.7%.** `run-summary.json` was generated at
   `2026-07-09T03:34:32Z` — *before* documentation ran. It reports `log_lines: 14, capped_lines: 5`.
   The actual `run-log.jsonl` has **16 lines, 6 capped** (lines 3, 4 implementation; 7 security;
   9 testing; 11 debugging; 15 documentation) → **6/16 = 37.5%**. Entry 11/12 and the handoff
   quote the stale 35.7%. Either number fails the <10% threshold; the point is the snapshot
   discipline (F-M4-8).
2. **Entry 9's verification of the "stray dashboard files" claim was itself wrong.** The journal
   says "no such files exist on disk (verified: zero matches in tests/)". Disk says otherwise:
   `tests/integration/__pycache__/test_dashboard_endpoint.cpython-312-pytest-8.3.4.pyc` and
   `test_dashboard_perf_k6_load.cpython-312-pytest-8.3.4.pyc` exist right now in the throwaway,
   and `src/api/routes/__pycache__/dashboard.cpython-312.pyc` appears in a file listing inside the
   implementation transcript. See §2(c).
3. **The handoff's "33 subagent transcripts preserved" is overstated: 14 of the 34 `.output`
   files are 0 bytes**, including planning, plan-audit, debugging #1 (U-03 pilot), the cycle-3
   security re-scan, and the cycle-3 testing re-run. See §2(a) and criterion 5.
4. **`suspected_underlog: 1` identified:** it is run-log line 5 — implementation attempt 3,
   `status:"unknown"` (the F-M4-3 hook race). `run-summary.sh` counts lines with
   `status=="unknown" or model=="unknown"`.

---

## 1. Proof-gate scorecard (criterion → threshold → measured → verdict)

| # | Criterion | Threshold | Measured (from disk) | Verdict |
|---|---|---|---|---|
| 1 | Cap-out tax (`capped_lines / log_lines`) | < 10% | **6/16 = 37.5%** (run-log.jsonl lines 3,4,7,9,11,15; stale run-summary said 5/14 = 35.7%) | **MISS** |
| 2 | Improvised interventions beyond the 2 checkpoints | 0 | **0 improvised.** Adjudication: interview answers (Entry 2) = operator pre-step the run plan itself prescribes; Entry-3 relocation + option selection = pre-kickoff setup (pipeline not started; logged as F-M4-1 anyway); plan-checkpoint "go" = sanctioned checkpoint 1; the AC20 budget decision (Entries 10–11) = a **pipeline-initiated escalation** under the debugging-escalation protocol, journaled verbatim, answered by option-selection with no re-teaching — ruled *sanctioned*, not improvised. Strict-letter reading ("any other intervention") would count it; noted, does not change the run verdict (criterion 1 already resets). | **PASS** (adjudicated) |
| 3 | Security catches efficacy-class defects, or /code-review confirms zero escapes | ≥ 1 | **Both clauses satisfied.** Security caught the FORCE-RLS owner-bypass in-diff (security-report.md #3: app role owns `quotas` ⇒ non-FORCE RLS inert — the exact R1-1 DB-privilege class, i.e. the U-02 efficacy question working in-stage), fixed via `ALTER TABLE quotas FORCE ROW LEVEL SECURITY`. /code-review pre-step: 8 findings, **0 new CONFIRMED correctness bugs**. | **PASS** |
| 4 | Report-claim reconstructability | every claim artifact-backed | "Executed" scan claims carry scan-log stamps + sha256 (`security-status.json` scan_artifacts semgrep `c7c0c34c…`, osv `9f84c116…`; 5 scan-log lines; 3 archived per-attempt reports in `.pipeline/archive/`). "Covered" claims: by_id complete, 21/22 + AC22 delegated-with-reason. Perf claims backed by raw sample counts (7441 quota / 7467 baseline). Blemish: testing's environmental "stray dashboard files" sentence (§2c) is a non-artifact-backed *environment* claim, outside the criterion's executed/covered/verified letter. | **PASS (provisional** — re-adjudicate after deployment + 6b re-stamp) |
| 5 | Evidence preservation — full run reconstructable after teardown | yes | **MISS at teardown, CURED post-hoc (2026-07-09 recovery pass):** 14/34 transcript files were 0 bytes because the preservation step grepped the parent session JSONL instead of copying the per-agent store (`<session>/subagents/agent-<id>.jsonl`). All 13 `a…` transcripts recovered from that store (33/34 now non-empty; planning 488 KB, plan-audit 169 KB); `b01lex8rm` has no source anywhere (unrecoverable, impact nil — every stage + finder otherwise accounted for); the `b79on0wti`≡`bl2q7axu7` duplicate is identical **at the platform source** (`tool-results/`), so nothing was lost there. The criterion still counts as a process miss for this run — the gap existed until an auditor hunted the session store — but the evidence set is now complete. run-summary staleness (§0.1) stands. | **MISS (cured post-hoc**; fix 1.4 makes it deterministic) |
| 6 | Ledger — every escape has a row + action | yes | 13 M4 rows written by this audit (`docs/finding-ledger.md` §"M4 deltas"): 8 /code-review findings + 5 telemetry/process escapes, each with an action. | **PASS (provisional** — final check post-deployment) |

**Verdict: RESET.** Criterion 1 is a hard miss at ~4× the threshold; criterion 5 is a miss as the
evidence stands today. Per the run plan: M4 does not count toward the 2–3 consecutive runs; the
fix list (§7) lands first, then M4′.

---

## 2. The three open transcript questions

**(a) Did planning actually read `.pipeline/repomix-pack.xml`? — RESOLVED (2026-07-09 recovery
pass): NO, and the root cause is pack sizing, not agent behavior.** Planning's transcript
(recovered from the session store, 488 KB) shows: the prompt named the pack path; planning
issued `Read(.pipeline/repomix-pack.xml)`; the read failed as oversized and planning said
verbatim *"The repomix pack is too large to read whole. Let me explore the actual source tree
directly"*, then fell back to 30 targeted file Reads (a sensible fallback). The TA/B-1 pre-step
produced a 149k-token pack for a consumer that cannot ingest it — F-M4-6 upgrades from
"unevidenced" to **confirmed not-consumed, pack-sizing defect** (fix: compress/scope the pack to
fit, or have planning read it in slices; see fix plan 3.4).

**(b) Did security invoke `ast-grep`? — RESOLVED: NO.** `scan-log.jsonl` has exactly 5 lines
(semgrep ×4, osv ×1), no ast-grep. No `"command":"…ast-grep…"` tool call exists in any non-empty
transcript (security attempt-1 transcript is 467 KB and substantive). Every "ast-grep" string in
the transcripts is a directory listing or semgrep scanning the `ast-grep-rules` SKILL.md. The one
agent-invoked B-tool of the TA overhaul went unexercised on its first live run (F-M4-5).

**(c) The cand-4 "fabricated" claim — RESOLVED, and downgraded from "fabricated" to
"inherited-and-unverified".** Chain of evidence:
- Stale **bytecode** from run 3's Phase D dashboard work survived the Entry-3 conversion:
  `tests/integration/__pycache__/test_dashboard_{endpoint,perf_k6_load}.cpython-312-pytest-8.3.4.pyc`
  (on disk now) and `src/api/routes/__pycache__/dashboard.cpython-312.pyc` (listed in a tool
  result inside the implementation transcript). The conversion purged the dashboard *source*
  tree but missed `__pycache__` directories.
- The phrase originates in **implementation's** progress file (T3 note: "112 passed (tests/ minus
  k6 perf + unrelated dashboard tests)") — testing read that file (tool result visible in its
  transcript at 02:09:00Z) and repeated the claim as "stray leftovers from a different branch's
  working tree, correctly excluded" without verifying.
- The filter was a no-op: the transcript's collect-only output shows the deselected tests under
  `-k "not dashboard and not perf_k6"` were the **3 perf_k6 tests**; zero collectible test
  matches "dashboard" (pytest does not collect .pyc).
- So: not a whole-cloth fabrication — a real-but-mischaracterized artifact, propagated across two
  agents' reports unverified, and then mis-"verified" as nonexistent in journal Entry 9 (which
  checked source files and git status but not `__pycache__`). Three distinct defects: incomplete
  conversion cleanup, unverified claim propagation, and a faulty journal verification (F-M4-4).

---

## 3. Per-stage scorecard (1–5; 3 = acceptable, 5 = passes senior human review as-is)

| Stage | Grade | Evidence sentence |
|---|---|---|
| requirements-elicitation (first live run) | **5** | All four deliberately-unstated ambiguities surfaced plus a real brief self-contradiction (one-migration vs scope column) caught unprompted; `requirements.md` verified at 14 resolved / 1 open / 8 out-of-scope with the one Open item honestly left for planning. |
| planning | **4** | One uncapped pass produced the perf-budgeted AC, the data classification (`security-status.json` data_surface.classified: 4), and the DAST-readiness AC unprompted (the U-07/watched-derivation surfaces all appeared); deductions: `tasks.md` fired on the thin slice (F-M4-2) and repomix consumption left no evidence (F-M4-6). |
| plan-audit | **4** | 2 advisory / 0 material flags with sha256-verified frontmatter and a correct `revision_recommended: false`; both advisories proved prescient (the deadlock-test gap reappeared in test-quality.json; Open Q3 did need the human) — structural remit executed cleanly, though the lock-design claim that later produced the EvalPlanQual bug is semantically outside its scope. |
| implementation | **4** | The A-2 test-first trail is real (red→green per task in `implementation-progress.md`) and its T5 concurrency pass caught and fixed the run's deepest bug — the EvalPlanQual stale-join admit-all (20/20 201s vs cap 10), re-verified empirically 3× — before any gate saw it; deductions: 2 cap-outs, plus the k6 fork and dead-flexibility knob (/code-review #3–4) showing U-21/YAGNI didn't bind. |
| U-03 pilot | **2** (catch-vs-cost) | Three finder agents plus one debugging cycle (~54k tokens) yielded one PLAUSIBLE latent hardening (READ COMMITTED isolation pin + regression test) while the exact target-class bug had already died in-stage via A-2; 1 REFUTED-as-designed, 1 dropped below precision. |
| security | **4** | The FORCE-RLS owner-bypass catch (report #3) is a genuine efficacy-class win — the R1-1 escape class caught in-stage this time — with clean evidence discipline (scan_reconciled: true, sha256-stamped artifacts, 3 archived per-attempt reports, ASVS reconciled 14 reqs); deductions: 1 cap-out and ast-grep, its one B-tool, never invoked. |
| testing | **4** | The adversarial charter produced a textbook backstop proof (NOBYPASSRLS role, api_key_id predicate removed entirely) and the stage was honest twice under pressure (AC20 reported FAIL at 3362 ms; mutmut recorded `quality_ok: false` rather than fabricating); deductions: the unverified dashboard claim propagated into its report, 1 cap-out, branch coverage 58.3% far below line coverage. *Hand-break-3-tests micro-check: SKIPPED — the working tree sits at the un-deployed diff checkpoint and mutating it would invalidate `reviewed_change_hash 63cc7107…`; run it post-merge in M5.* |
| documentation | **3** | It found and corrected a stale `--key_id` CLI claim on its own (transcript-verified against the real argparse definition) and the pr-description surfaces all five required disclosures; deductions: capped at sonnet@25 (the U-06 answer), routes/+schemas/ READMEs missing (/code-review #6), and the U-13 tally unpersisted (F-M4-9). |
| deployment gate | **n/a** | Not yet run (diff checkpoint pending); delegated-criteria arithmetic ungraded — grade at the post-deployment addendum. |

**Average of graded rows: 3.75** (30/8). First run with a filled per-stage scorecard; runs 1–3
were audited qualitatively, so no cross-run grade comparison exists yet.

---

## 4. Cross-run table (runs 1–3 from `run-evidence/m3-final-pipeline/`, M4 from this directory)

| Metric | Run 1 — ingest (greenfield) | Run 2 — events listing | Run 3 — dashboard (design-source) | M4 — quotas (proof run) |
|---|---|---|---|---|
| Log lines / caps (tax) | 20 / 7 (35%) | 8 / 2 (25%)¹ | 12 / 4 (33%)¹ | **16 / 6 (37.5%)²** |
| Wall clock (first→last log line) | 4 h 09 m (incl. deploy) | 1 h 07 m (to doc) | 3 h 36 m (to doc) | 10 h 06 m (to doc)³ |
| Loop cycles | 3/5 | 1/5 | 1/5 | 3/5 |
| Remediations | 2 | 0 | 0 | 2 (isolation pin; AC20) |
| Tests / coverage (lines/branches) | 83 / 89.82 / 58.77 | 142 / 90.73 / 61.48 | 161 / 92 / 67 | 128 / 89.9 / 58.3⁴ |
| Post-gate review findings | 10 deferred | 10 (11 ledger rows) | 13 ledger rows (1 CONFIRMED prod-breaking) | 8 (**0 new CONFIRMED correctness**) |
| Deepest-bug catcher | /code-review | /code-review | /code-review | **A-2 test-first, in-stage** |
| Human touchpoints in-run | manual resume every stage (op-reported ⚠) | not quotable | not quotable | 3 (2 checkpoints + 1 sanctioned escalation); **0 manual resumes** (all warm) |

¹ Feature-attributed lines from the M3 aggregate log (`.feature` field); run-1 caps include 6
lines misattributed to `main` (the known feature-identity distortion). Aggregate M3: 40 lines /
13 caps.
² Excludes deployment (pending). Pre-documentation it was 5/14 = 35.7% — fails either way.
³ Weak comparator: includes operator-away gaps (e.g. 20:08→01:35 with a warm resume running in
background).
⁴ M4's base is the committed corpus at `faabe9d` (feature 1 only) — runs 2–3 built on uncommitted
extras never pushed, so suite sizes aren't directly comparable.

Cross-run signal worth naming: **the caps did not improve** (35% → 25% → 33% → 37.5%) despite the
M3 fixes — what improved is the *cost per cap* (warm resumes: security finished in 12 tool uses /
233 s, testing in 35 / 568 s, vs run 1's cache-cold restarts). The criterion measures cap
frequency, not resume cost; see decision 4 and fix list #1.

---

## 5. The four explicit decisions

1. **U-03 correctness-review pilot: SUBSUME into A-2.** The pilot's designed prey — a data-path
   read feeding state-changing logic at a window boundary — was caught *earlier* by A-2's
   test-first concurrency pass inside implementation (the EvalPlanQual bug, Entry 6 /
   implementation transcript). The pilot's net add across 3 finder agents + 1 debugging cycle
   (~54k tokens) was one latent-hardening pin. Keep the pilot's data-path/state-change checklist
   as named prompts inside A-2's adversarial charter; drop the standalone post-smoke stage. (This
   also answers the TA-audit coordination flag: A-2 and U-03 were duplicating; A-2 won on
   evidence.)
2. **U-06 documentation model: the cap PERSISTS on sonnet@25** (run-log line 15,
   `status:"capped"`). The shipped protocol's answer is revert to haiku@35 — but note the M3
   baseline: haiku@35 *also* capped once per feature (3 caps / 6 invocations across runs 1–3), so
   the revert restores an equally-capping, cheaper, lower-quality model (sonnet caught the stale
   `--key_id` claim this run). Audit recommendation: the binding variable is **turns, not model**
   — make M5's single documentation variable **sonnet@35** and keep haiku@35 as the cost
   fallback. Operator decides at the retrospective.
3. **U-13 doc-identifier check: DO NOT promote yet — evidence insufficient, instrument first.**
   The warn-only tally is unreconstructable: `check-doc-identifiers.sh` writes warnings to stderr
   only, nothing persisted them, and the documentation transcript contains no hook output. From
   disk we have exactly one true-positive-class event (the doc agent's own `--key_id` catch) and
   zero recorded hook warnings. Fix F-M4-9 (persist the tally to `.pipeline/doc-identifiers.json`),
   run M4′ warn-only, decide on a real tally.
4. **Proof gate run 1 of 2–3: RESET** (criterion 1 hard miss; criterion 5 miss as evidence
   stands). Not a wasted run — the run itself was the healthiest yet on quality surfaces (0 new
   CONFIRMED correctness escapes, deepest bug dead in-stage, honest escalation) — but the
   scorecard is the scorecard. Fix list below, then M4′.

---

## 6. Machinery verification (the run plan's §5–6 measurement surfaces)

| Surface | Result |
|---|---|
| repomix pack produced + consumed | Produced ✓ (live `.pipeline/repomix-pack.xml`); consumed **unresolved** (empty planning transcript, F-M4-6) |
| ast-grep invoked by security | **No** ✗ (F-M4-5) |
| tasks.md size trigger on a thin slice | **Fired** ✗ — planning's own 22-AC output crossed the ≥15 threshold (F-M4-2, calibration) |
| Warm-resume C-2 on cap-out | **Worked** ✓ — same-agent resumes, progress file consumed, no re-derivation (security 12 tools/233 s; testing 35/568 s; doc 22/834 s) |
| U-14 skip disclosure / DAST L1 | DAST L1 ran, `target_reached: true`, within budget ✓ (alert counts reconcile by instance: 3 medium = CSP 1 + SRI 2; 4 low; 5 info). design-review: not wired — declared not-applicable via `Design source: none` in PROJECT.md (no separate skip artifact; acceptable, noted) |
| U-16 telemetry | ✓ capped lines 3/4/9/15 carry no stale coverage/tests artifacts; `skipped` field present in test-results.json (count 0, empty list) |
| SK delta (YAGNI class shrink) | **Not clean** ✗ — /code-review #4 dead-flexibility knob is the R2-9/R2-10 class post-enrichment |
| U-21 rule-of-two (no 4th k6 fork) | **Breached** ✗ — /code-review #3: fixture ~90-line copy-paste + JS near-duplicate |
| U-04/P2-1 micro-test | **Settled** ✓ — bare human `touch .pipeline/plan-approved` succeeded; the marker guard binds subagents, not the human TTY (Entry 5, marker present on disk at approval) |
| U-09 scan evidence | ✓ 5 stamped scan-log lines, sha256s in security-status.json, 3 archived per-attempt reports |

---

## 7. Fix list for M4′ (ordered)

1. **Cap policy (criterion 1, the reset driver).** Two options to the human at the retrospective:
   (a) resize turn budgets to observed demand — implementation 60→90, documentation 25→35–40,
   security 30→50, testing 50→60 — accepting cost for one-attempt completion; and/or (b) re-derive
   the metric: `capped_lines/log_lines` was set when caps meant cache-cold restarts; with C-2 warm
   resumes the same number now measures a much cheaper event. Do **not** silently re-define the
   metric — it's a proof-gate criterion; changing it is a human decision that resets nothing by
   itself.
2. **Transcript preservation (criterion 5):** re-export the 14 empty transcripts from the
   operator session JSONL now (they may age out), and make the preservation step assert non-empty
   bytes per INDEX row (F-M4-7).
3. **run-summary re-stamp on every snapshot** + post-deployment 6b re-stamp (F-M4-8).
4. **log-run/smoke-check race:** log-run must not read `smoke-status.json` older than the stage
   stop it is logging (or re-order/retry) — kills the `status:"unknown"` class (F-M4-3).
5. **Conversion/bootstrap hygiene:** purge `__pycache__` (and equivalent build caches) during
   repo conversion; kickoff pre-step asserts session cwd == the state.json repo (F-M4-1, F-M4-4).
6. **Persist U-13 output** to `.pipeline/doc-identifiers.json` (F-M4-9).
7. **ast-grep wiring:** give security a deterministic prompt-step (or hook pre-step) that runs
   the ast-grep-rules pack and stamps scan-log, rather than hoping the agent elects to (F-M4-5).
8. **tasks.md trigger recalibration:** count implementation-facing work units, not planning's own
   AC granularity — or raise the AC threshold; a thin slice self-triggering decomposition defeats
   the calibration intent (F-M4-2).
9. **U-21/YAGNI enforcement:** the conventions alone didn't bind; add the planted-defect evals
   (U-23) for the dead-knob class and consider a duplication lint scoped to `tests/integration/k6/`
   (F-M4-10).

## 7b. Re-audit deltas (deep dive, 2026-07-09, same session as the audit)

A second pass against the engine source and the non-empty transcripts refined five findings:

1. **F-M4-2 downgraded to a calibration *observation*.** Both trigger legs genuinely crossed
   (22 ACs ≥ 15; ~26 estimated files ≥ 25, per `planning.md:336`) — the trigger obeyed its spec;
   it was the *run plan's expectation* ("a thin feature should NOT trigger it") that was
   miscalibrated. And tasks.md proved **load-bearing**: both warm resumes navigated by T1–T6 +
   the progress file. Keep the file-count leg; recalibrate or drop only the AC leg (it measures
   planning's own authoring granularity).
2. **F-M4-3 root cause corrected: parallel Stop-hook execution.** implementation.md lists
   smoke-check before log-run under `Stop:`, but same-event hooks run **concurrently** —
   frontmatter order is not sequencing. That's how log-run read `unknown` 5 s before
   smoke-check's stamp. The fix is a freshness wait (or one sequential wrapper script), not
   hook re-ordering.
3. **F-M4-5 root cause corrected: definition defect, not agent negligence.** `security.md:53`
   labels ast-grep an "*optional adjunct*" with no trigger condition — skipping it was
   spec-compliant. It also has no U-09 wrapper, so even a run would leave no scan-log stamp.
4. **F-M4-7 refined twice.** First pass: `b79on0wti.output` ≡ `bl2q7axu7.output` byte-identical,
   34 files vs the INDEX's 33. Recovery pass (2026-07-09): the duplicate is identical **at the
   platform source** (`<session>/tool-results/` stores the same content under both IDs) — no
   finder output was lost; and the 14 empties happened because preservation grepped the parent
   session JSONL instead of copying `<session>/subagents/agent-<id>.jsonl`. All 13 recoverable
   transcripts recovered (33/34 non-empty); `b01lex8rm` has no source anywhere (unrecoverable,
   impact nil). Fix 1.4's copy source is now specified: `subagents/` + `tool-results/`, with
   non-empty + integrity asserts.
5. **Turn-demand data mined for the cap fixes** (journal tool-counts anchored to maxTurns at
   cap): security total demand ≈ 38–45 turns vs cap 30; testing ≈ 70–75 vs 50; documentation
   ≈ 37–40 vs 25 (so the U-06 protocol's haiku@35 — and even sonnet@35 — would likely *still*
   cap; the trial should be @40); debugging ≈ 35 vs 30; implementation ≈ 130+ turns / ~250 tool
   uses vs 60 — no realistic single-attempt budget fits it, which points to per-task invocation
   against tasks.md rather than a bigger cap.

Fix plan: `docs/m4-prime-fix-plan.md`.

## 8. What remains provisional

Deployment → PR → 6b run-summary re-stamp → final `.pipeline` snapshot have not happened. After
they do: re-verify criterion 1 arithmetic on the re-stamped summary (deployment adds lines — if
deployment caps, the tax worsens), finalize criteria 4–6, grade the deployment-gate row, and
append the addendum here. The RESET verdict cannot be upgraded by those steps (criterion 1 is
already final for this run); it could only get worse, which changes nothing procedurally.

---

## 9. Post-deployment addendum (2026-07-09, orchestrating session per operator instruction)

Deployment, the 6b re-stamp, and the final evidence snapshot have now happened; PR #2 merged
(merge commit `43da3203feb…` @ 17:08:24Z). Finalizations, each re-verified from disk:

**Criterion 1 (final arithmetic):** run-log.jsonl now 17 lines / 6 capped = **35.3%**
(deployment added one clean line; `wc -l` + `grep -c '"capped"'` on the snapshot copy).
Deployment did not cap, so the tax improved marginally vs the audit's 37.5% pre-deployment
count and remains ~3.5× the threshold. **MISS — final; RESET verdict unchanged.**

**Criterion 4 (report-claim reconstructability): PASS — final.** Deployment's claims are
artifact-backed end to end: commit `bdcb326` exists (47 files, matching its report), PR #2
exists and merged, `diff-approved.approved_change_hash 63cc7107…` equals
`review-manifest.reviewed_change_hash` (currency held through the checkpoint), the commit
contains zero `.pipeline/` paths (`git show --name-only | grep -c '^\.pipeline'` = 0), and the
run-log deployment line (`status:"pass", attempt:1, files_changed:47`) agrees with the gate
outcome. The §1 blemish (testing's environment sentence) stays noted; it is outside the
executed/covered/verified letter and already carries ledger row M4-tel3.

**Criterion 5 (evidence preservation): MISS (cured) — final.** The final snapshot exercised the
NEW `scripts/preserve-transcripts.sh` end-to-end: 23 transcripts copied from the per-agent
store + `MANIFEST.sha256`, non-empty asserted, dual-ID byte-identical pairs flagged **at
source** (same class §2/Entry 14 documented — nothing lost). The re-stamped run-summary.json
was snapshotted in the same pass (M4-tel2's fix behavior followed). The miss stands for the
run — the gap existed until the audit hunted the session store — but the evidence set is
complete and the fix is now demonstrated, not just coded.

**Criterion 6 (ledger): PASS — final.** 13 rows verified present with actions; deployment
surfaced no new escape, so no new row is owed.

**Deployment-gate row (per-stage scorecard): 5.** One invocation, one attempt, zero caps
(run-log line 17); the gate's conjuncts were verified against the artifacts before any git
action (transcript `ae83c90624f8adb58.output`); delegated-criteria arithmetic handled correctly
(21 covered + AC22 delegated:security against `criteria_total: 22` / `delegated_criteria:
[AC22]` frontmatter); single hygienic commit — no `.pipeline`, no secrets (the two "password"
hits are the RLS-backstop test's throwaway role and a k6 env reference), PR body from
pr-description.md. **Per-stage average becomes 35/9 = 3.89.**

**Bottom line unchanged:** RESET on criterion 1 (35.3% final) with criterion 5's process miss
cured; criteria 2/3/4/6 PASS; the fix tracks are implemented and eval-green — M4′ proceeds.
