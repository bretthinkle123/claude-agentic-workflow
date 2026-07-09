# M4′ from-disk audit — proof-gate run 1 of 2–3 retry (Meterly usage CSV export)

Audited 2026-07-09 by a fresh session, from disk only, per `docs/m4-prime-run-plan.md`.
Numbers quoted from `run-log.jsonl` / `run-summary.json` / stage artifacts / transcripts /
the GitHub Actions API — never from journal or handoff prose (B7). Run state: complete
end-to-end (PR #3 merged `ef3fb3f`), so **all six criteria are final** — the first fully
adjudicable run.

---

## 1. Proof-gate scorecard

| # | Criterion | Threshold | Measured (from disk) | Verdict |
|---|---|---|---|---|
| 1 | Cap-out tax | < 10% | **3/14 = 21.4%** (run-log lines 4–5 implementation attempts 1–2, line 9 debugging; summary re-stamp matches the log exactly — the F-M4-8 staleness class did not recur). vs M4's final 35.3% (17/6). | **MISS** |
| 2 | Improvised interventions | 0 | **0 improvised (adjudicated).** (a) plan-approved touch + (b) diff approval = the two checkpoints; (c) AC16 escalation (Entries 6–7) = pipeline-initiated, journaled verbatim, option-selection — **sanctioned mechanically** under the codified 2.3 definition (no judgment call this time, which is the definition doing its job); (d) restart waiver (Entry 2) = pre-kickoff operator setup, before the pipeline started; (e) **mid-run ast-grep install (Entry 6) — adjudicated NOT an intervention, but it exposes a 2.3 boundary gap**: the codified letter ("anything operator-initiated mid-run counts") doesn't distinguish *steering* from *host provisioning*. The install wrote no pipeline artifact, instructed no agent, and changed no gate outcome (ast-grep is advisory; the disclosed-skip path was already compliant). Ruled environment maintenance; F-M4′-5 tightens the wording for M5. | **PASS** (adjudicated; definition gap logged) |
| 3 | Security catches efficacy-class defects, or /code-review confirms zero escapes | ≥ 1 | **PASS with a structural observation.** The planted CSV-injection vector never reached security as a *defect* — elicitation surfaced it, planning designed the sink escape, implementation built it, security **verified-effective** (report's verified-controls table) and ast-grep's structural pass corroborated. The defense-in-depth layers starved the catch opportunity — that is success, not failure. Second clause also satisfied: /code-review found 0 CONFIRMED core-logic bugs. Caveat named honestly: CI later falsified "zero escapes" for **environment-portability and doc-drift classes** (§4) — neither is the data-path efficacy class this criterion targets; both get ledger rows (criterion 6). | **PASS** |
| 4 | Report-claim reconstructability | every claim artifact-backed | 9 scan-log stamps (semgrep ×4, osv ×1, **ast-grep ×4**) + `scan-reconciliation.json`; repomix receipt sha `67eadd30…` **matches the pack on disk** (verified byte-for-byte); perf claims carry raw 10-sample lists (locally AND in the CI log); by_id 21/22 + AC18 delegated; `skipped: 4` recorded. One blemish: Entry 6's "cycle-1 ast-grep invoked, exit 2" has **no scan-log stamp** — the wrapper exits before stamping when the binary is missing, so a disclosed skip is structurally unstampable (F-M4′-4, wrapper defect, not report dishonesty). | **PASS** |
| 5 | Evidence preservation | full run reconstructable | **First clean end-to-end preservation: 40/40 transcripts non-empty + MANIFEST.sha256** (the F-M4-7 fix working). Two non-loss blemishes: **23 of the 40 files are M4-era carryover** — the standing-session waiver means the session store is cumulative and preserve-transcripts has no run filter (provenance mixing, F-M4′-7); and the script silently no-ops when run from the wrong CWD (Entry 9). Nothing lost; everything this audit needed was on disk. | **PASS** (with findings) |
| 6 | Ledger — every escape a row + action | yes | M4P-1…8 written at run close (verified present). This audit adds **M4P-9…15** for the post-merge CI cluster (§4) — after which every known escape has a row. | **PASS** (rows added by this audit) |

**Verdict: RESET — criterion 1 only.** 21.4% vs <10%. Five of six criteria now hold, and
the cap tax fell 35.3% → 21.4% with security/testing/documentation/deployment all 0-cap.
The remaining cap source is one structural decision (§6.2): the single-shot implementation
budget on 10–24-file slices, plus one debugging cap.

---

## 2. Watchlist verdicts (each M4′ fix under live test)

| Fix | Verdict |
|---|---|
| repomix pack-sizing + consumption receipt (F-M4-6) | **✓ CLOSED.** 167k full pack → re-scoped to 54 files / 26,820 tokens; receipt in plan.md frontmatter; sha verified against disk by this audit; planning used 17 tool uses vs M4's 37. |
| No tasks.md on a thin slice (F-M4-2) | **✓ per contract** — ~14 estimated files < 25, none emitted. But the contract itself is now the finding (F-M4′-1): the 10–24-file band has no decomposition and doesn't fit single-shot. |
| ast-grep required-when-applicable (F-M4-5) | **✓ CLOSED with a gap.** Agent behavior fixed: invoked the wrapper unprompted, disclosed the missing binary, ran fully post-install (4 scan-log stamps, structural SQL pass in the report). Gap: exit-2 skip leaves no stamp (F-M4′-4); host prerequisite was an operator provisioning miss. |
| Budgets — 0 caps expected (F-M4-11) | **✗ MISSED**: implementation ×2 (single-shot), debugging ×1. Security 45 ✓ (813 s, 0 caps), testing 75 ✓ (×2 runs 0 caps), documentation 40 ✓ (**U-06 flipped — M4's chronic capper finished uncapped in 646 s**), deployment ✓ (166 s). |
| Telemetry (F-M4-3/8) | **✓ CLOSED.** 0 unknown/pending-smoke lines; attempt-3 line stamped 1 s after smoke-status with correct status; summary == log at every snapshot; suspected_underlog 0. |
| U-13 tally persisted (F-M4-9) | **✓ artifact exists** — and answers the question: 24 unresolved across 11 files, **FP-dominated** (`async def` tokenized as `asyncdef…`; design-record *copies* of plan.md swept; frontmatter keys flagged). See decision §6.1. |
| preserve-transcripts (F-M4-7) | **✓ worked** (40/40 non-empty, manifest); provenance-mixing + CWD gaps logged (F-M4′-7). |

---

## 3. Per-stage scorecard (1–5; 3 = acceptable, 5 = senior-review-ready)

| Stage | Grade | Evidence sentence |
|---|---|---|
| requirements-elicitation | **5** | All six plants surfaced in 12 questions (12 resolved / 1 open / 5 out-of-scope verified) and the CSV-injection plant was converted into an explicit requirement — the interview neutralized the trap before any code existed. |
| planning | **4** | Receipt-verified pack consumption at 17 tool uses, correct no-tasks.md call, unprompted flag of the pre-existing RLS gap, and a clean one-pass revision — deduction: the chunk-per-row streaming design carried a 10-second perf defect no one modeled (Open Q1's 500 ms was proposed without a data point). |
| plan-audit | **5** | Two real material flags (the retired-trigger citation in the plan text; the missing fail-closed COUNT-error AC) with sha-stamped frontmatter, and both fixes landed in one revision — precise, in-remit, nothing missed. |
| implementation | **3** | Delivered a clean feature with two honest disclosures (httpx buffering; the 9.8 s AC16 data point) — deductions: 2 caps against a 0-cap expectation, the A-2 progress file didn't exist at cap 1 (contract bound only after the resume demanded it), and the shipped chunk-per-row hot path was the perf defect. |
| security | **4** | Clean two-pass discipline (FP triage, verified-effective CSV sink, carryovers tracked, ast-grep run + disclosed-skip before it) — no new efficacy catch, but the run offered none (plant neutralized upstream); deduction: its triaged-FP knowledge never became the committed ignore files CI needs (M4P-13's escaped-because). |
| testing | **4** | Independently re-measured AC16 at 25,210 ms (falsifying implementation's optimistic 9.8 s), routed the honest FAIL, executed ledger M4-1's coverage-floor action, 91/66 coverage — deduction: its hard 3,000 ms CI-side timing assert was env-fragile by construction (M4P-1, confirmed in CI at 5,612 ms). |
| debugging | **5** | Empirical root cause that *overturned* implementation's disclosure (4×middleware chunk re-pump, not CSV encoding), a 7–17× fix inside the approved design with a fails-before/passes-after regression test, and a by-the-book sanctioned escalation — the 1 cap is a budget finding, not a quality one. |
| documentation | **3** | Uncapped at 646 s (U-06 flipped) and corrected five pre-existing invented identifiers with source verification — but its own edit dropped the "Bearer" auth-scheme mention from system_architecture.md and broke `test_dast_context_documented` post-gate (CI caught it; F-M4′-8c). |
| deployment gate | **5** | Single 0-cap pass in 166 s; every conjunct verified; hygienic commit `bcf16bb`; diff-approved hash == review-manifest == commit (currency held end-to-end). |

**Average: 4.22** (38/9) vs M4's 3.89.

---

## 4. The post-merge CI cluster (first-order finding, F-M4′-8)

**The Layer-2 CI merge gate has NEVER been green on this repo — 5 of 5 `pipeline-ci` runs
are failures** (runs on feature/usage-metering-ingest, feature/metric-quotas + its merge,
feature/usage-export + its merge; conclusions from the GitHub API). Both PRs merged with
the gate red — no branch protection enforces it (the ci-conventions branch-protection
checklist was never applied). Job-level decomposition of PR #3's branch run (`29049680147`),
with PR #2 (`29035734753`) as comparison:

| Job | PR #3 | PR #2 | Root cause (from the job logs) |
|---|---|---|---|
| build-and-test | FAIL (5 failed / 177 passed / 3 skipped) | FAIL | Three distinct failures, below |
| secrets | FAIL | FAIL | 2 gitleaks generic-api-key hits = the test-fixture FPs local security triaged; **no `.gitleaksignore` committed** — the designed CI waiver channel was never populated |
| sast | FAIL (2 findings) | pass | Full-tree Semgrep re-finds the 2 sites local security verified as FPs (they entered the tree in PR #3); **no `.semgrepignore`** |
| deps | FAIL (exit 127) | FAIL | Job pulls `ghcr.io/google/osv-scanner:latest` — **unpinned** — and upstream removed `--lockfile-scan-mode`; the template's own "pin image DIGESTS on first CI run" instruction was never executed |
| containers-iac | FAIL | FAIL | Trivy fs flags pre-existing `infra/` Terraform (run-1 tree) — full-tree scope vs the PR's diff; **no `.trivyignore`** |
| codeql | FAIL | FAIL | Matrix runs with **literal `<CODEQL_LANGUAGE>/<CODEQL_BUILD_MODE>` placeholders** — the template ships this job ENABLED (no `if: false` gate, unlike mutation), and the 1.7 placeholder guard's token list doesn't cover `CODEQL_*` (and the throwaway's workflow predates the guard anyway) |
| asvs-markers, store-compliance | pass | pass | — |

**build-and-test's three failures:**
1. **Seed-script portability (3 tests):** `scripts/seed_api_key.py` → `ModuleNotFoundError:
   No module named 'src'` when spawned as a subprocess on the CI runner — local venv resolves
   `src` from cwd; CI's install doesn't. A real environment-portability escape all local
   layers missed (M4P-9).
2. **AC16 timing flake — M4P-1's prediction CONFIRMED:** p95 5,612 ms vs the 3,000 ms assert
   on the 2-vCPU runner under `--cov` (10-sample list in the log). Locally 1,643 ms. The
   prediction row now has its data point (M4P-10 upgrades the action).
3. **Doc-drift break:** `test_dast_context_documented` asserts "Bearer" appears in
   system_architecture.md; documentation's rewrite dropped it — **after testing's last green
   run** (testing 20:32 → documentation 20:40). Nothing re-validates tests after the
   documentation stage; the deploy gate hashes the tree but never re-runs the suite (M4P-11 —
   a genuine stage-order gap, first observed because CI finally exercised the merge commit).

The run plan called CI "the merge gate"; in operation it is an unplugged smoke detector:
scanners re-run with different scope and no waiver channel, one job can never run as
bootstrapped, one job broke on an unpinned upstream, and nothing stops a red merge.

---

## 5. Cross-run table

| Metric | R1 ingest | R2 listing | R3 dashboard | M4 quotas | **M4′ export** |
|---|---|---|---|---|---|
| Log lines / caps (tax) | 20 / 7 (35%) | 8 / 2 (25%) | 12 / 4 (33%) | 17 / 6 (35.3% final) | **14 / 3 (21.4%)** |
| 0-cap stages | few | most | some | sec-rescan, test-rerun | **security, testing ×2, documentation, deployment, planning ×2, plan-audit** |
| Loop cycles / remediations | 3/5 / 2 | 1/5 / 0 | 1/5 / 0 | 3/5 / 2 | 3/5 / 1 |
| Tests / coverage (lines/branches) | 83 / 89.8 / 58.8 | 142 / 90.7 / 61.5 | 161 / 92 / 67 | 128 / 89.9 / 58.3 | **180 / 91 / 66** |
| Post-gate review findings | 10 | 10 | 13 (1 prod-breaking) | 8 (0 confirmed) | 8 (0 core-logic) |
| Deepest-bug catcher | /code-review | /code-review | /code-review | A-2 in-stage | **debugging (root-cause overturned implementation's theory)** |
| Escapes past all local layers | — (CI red, unread) | — | — | — | **3, caught by CI** (portability, timing-env, doc-drift) |
| Per-stage average | not graded | not graded | not graded | 3.89 | **4.22** |

Trend worth naming: the *authoring* half improves every run (caps down, grades up, honest
escalations working, zero core-logic escapes twice running). The newly exposed frontier is
the *delivery* half — CI has been red since run 1 and only now became audit material because
M4′ actually collected it.

---

## 6. Explicit decisions

1. **U-13: DO NOT promote — fix the checker first.** The persisted tally (the F-M4-9 fix
   working) shows 24 unresolved / 11 files, dominated by parser defects: `async def` glued to
   `asyncdef…` in signature comparison, design-record *copies* under `docs/decisions/` swept
   as if they were fresh docs, YAML frontmatter keys treated as code identifiers. ~0 true
   positives this run (documentation separately fixed 5 real stale identifiers by itself).
   Fix the tokenizer + exclude `docs/decisions/` copies + frontmatter, re-tally on M4″.
2. **Implementation single-shot budget: make decomposition the default.** Two consecutive
   runs, implementation is the only structural capper (M4 ×2, M4′ ×2) — and M4′ proves the
   ≥25-file trigger leaves the common 10–24-file band uncovered (14 est. files → single-shot
   → ~210 tool uses vs a 60-turn budget). Recommendation: planning emits tasks.md at
   **≥ 8 estimated files** (micro-changes below that stay single-shot), so per-task segments
   — which produced 0-cap segment behavior everywhere they applied — carry the load. Also
   raise debugging 40 → 50 (capped mid-fix on an optimize-class session both runs).
3. **Proof gate: RESET** — criterion 1 alone. The count stays at zero; fixes land, then M4″.
   Directionally: 5/6 criteria now hold and the tax halved; one structural decision (above)
   plausibly zeroes the cap tax at M4″.

## 7. Fix list for M4″ (ordered)

> **STATUS (2026-07-09): items 1–7 IMPLEMENTED engine-side** (eval suite green; see the
> fix commit). Remaining operator-side: 2(g) branch protection on the throwaway (apply the
> ci-conventions checklist), the meterly app fix for the seed-script import (M4P-9's
> app-scope half — next feature run), and re-running `install-global.sh` + restart before
> M4″. 2.3's provisioning clause now lives durably in the orchestration SKILL
> ("Operator touchpoints"), not just run-plan text.

1. **Decomposition default** (decision 6.2): planning trigger ≥ 8 est. files; debugging → 50.
2. **CI gate rescue (the M4P-9…15 cluster):** (a) security stage MUST commit tool-native
   ignore entries (`.gitleaksignore`/`.semgrepignore`/`.trivyignore`) for every FP it triages
   — the designed waiver channel, never populated; (b) pin the osv-scanner image digest +
   fix the removed flag; (c) gate codeql behind `if: false` like mutation + add `CODEQL_*`
   to the placeholder guard tokens; (d) exclude timing asserts from the CI coverage
   invocation (perf marker skipped in CI; local + load-campaign own timing); (e) fix
   seed-script `src` import portability (app fix + CI INSTALL_CMD contract note); (f)
   post-documentation doc-contract re-check (cheap: re-run doc-asserting tests before the
   diff checkpoint); (g) operator: apply the ci-conventions branch-protection checklist so
   a red gate blocks the merge.
3. **ast-grep wrapper stamps the disclosed skip** (exit-2 path writes a scan-log line with
   `exit_code: 2`, so skips are provable, F-M4′-4).
4. **preserve-transcripts run-scoping** (filter by agent-file mtime ≥ run start, or record
   per-file mtimes in the manifest) + fail loudly on wrong-CWD instead of silent no-op.
5. **U-13 checker parser fixes** (decision 6.1).
6. **2.3 wording**: add the host-provisioning clause (journaled environment maintenance that
   writes no pipeline artifact and answers no pipeline question ≠ intervention).
7. **A-2 progress-file at cap:** the trail must exist *before* the first cap, not after the
   resume demands it — make the progress-file append part of each red→green unit's contract
   (it already is on paper; add it to the implementation eval corpus).
