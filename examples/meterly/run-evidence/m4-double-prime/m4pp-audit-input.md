# M4″ run — audit input

Prepared 2026-07-10 by the orchestrator session, for an independent audit session.
Everything numeric below is quoted from `.pipeline/run-summary.json` (stamped 2026-07-10T07:10:04Z,
after deployment + merge) and `.pipeline/run-log.jsonl` — not hand-written. Where the orchestrator
deviated from the published skills, that is stated as a deviation, not smoothed over. The auditor's
jobs: (1) adjudicate each operator touchpoint against proof-gate criterion 2, (2) verify claims
against the evidence pointers, (3) turn the anomalies into engine deltas (definitions/skills/hooks),
not prompt lore.

## 1. Run identity

- Feature: **quota-admin** — `GET /v1/quotas` (admin-scoped tenant list) + `DELETE /v1/quotas?customer_id=&metric=`.
- Branch `feature/quota-admin`; feature commit `fe8abbe`; integration merge `a56c573`; merged to main in **PR #4** (2026-07-10T07:09:44Z) — merge commit `3fb8d11`.
- Unblocking side-run: branch `ci-fix/required-checks-green`, commit `a04b93b`, **PR #5** (merged 2026-07-10T05:24:12Z, merge `0d00cd5`).
- Firsts: first run with `requirements-elicitation` pre-planning; first merge under branch protection; first run where post-deployment CI state forced an out-of-band remediation.
- Kickoff: operator Step 3 = `/requirements-elicitation` (answer minimally, recommended options); Step 4 = verbatim "Run the pipeline from planning for the feature in PROJECT.md."

## 2. Machine summary (quoted from run-summary.json)

- `first_pass_clean: false`, `totals: {log_lines: 11, capped_lines: 2, loop_cap_events: 0, suspected_underlog: 0}`, `assurance: standard`.
- Stages: planning 2× opus (rev pass) · plan-audit 1× sonnet · implementation 1× sonnet (13 files, smoke pass) · security 1× opus (clean; 1 fixed, 0 critical / 2 warnings) · testing 1× sonnet (pass; 217 tests, 216 passed / 1 failed pre-existing; coverage 88.15 lines / 66.67 branches; 6 unit / 20 integration / 0 e2e; strategy pyramid) · documentation 1× sonnet · deployment 1× sonnet · **debugging 3× opus (2 capped + 1 pass), all on branch `ci-fix/required-checks-green`**.
- ⚠ Attribution nuance for the auditor: the security⇄testing loop itself exited GREEN on cycle 1 with zero debug retries (the 4c snapshot said `first_pass_clean: true`, stages=5). The final `false` and both capped lines come entirely from the post-deployment CI-fix work, which log-run attributed to feature `quota-admin` via the state.json slug even though it ran on the ci-fix branch. Decide whether that attribution is correct-by-design (stable per-feature key, the U-16b intent) or whether out-of-band remediation needs its own log key so it doesn't overwrite loop-quality metrics.

## 3. Timeline (UTC, from run-log + markers)

| When | Event |
|---|---|
| 07-09 22:53 | Per-feature reset (run-started stamped by the restarted engine; branch + state.json slug already set pre-kickoff) |
| 07-09 ~23:00 | Requirements elicitation: 8 questions, 2 AskUserQuestion rounds, all "Recommended" selected → requirements.md (9 resolved / 0 open / 6 out-of-scope) |
| 23:08 / 23:12 / 23:18 | planning → plan-audit (1 material flag: missing safe-error AC) → planning revision (AC19 added; 18→19 criteria) |
| 07-10 ~01:16 | Plan checkpoint ANOMALY: operator selected "Approved — marker touched" but `plan-approved` was absent; background watcher polled ~2h; marker landed 01:25 local (see §5) |
| 01:53 | implementation single-shot done, smoke pass |
| 01:54 | loop-guard reset + tick (cycle 1/5) |
| 02:39 | security clean; GREEN predicate jq-verified on main thread |
| 03:49 | testing pass; GREEN predicate jq-verified → loop exits cycle 1 |
| 03:51 | loop-guard done; run-summary 4c snapshot; design-review skipped (no ui.env, disclosed); DAST ran (within budget, 0 high) |
| 03:57 | documentation done; 5a doc-contract re-check green (1 test) |
| ~04:00–04:10 | /code-review: 8 finder agents + 2 verifier agents → 16 survived (14 CONFIRMED / 2 PLAUSIBLE), 10 reported |
| 04:16 | diff-approved via approve-diff.sh (hash matched review-manifest) |
| 04:19 | deployment: commit fe8abbe passed deployment-gate; PR #4 opened |
| ~04:25 | CI red on PR #4 (sast, codeql, deps, containers-iac) — all verified pre-existing on main @ ef3fb3f → ESCALATION to operator (2 questions, both "Recommended" selected) |
| 04:26–05:24 | Out-of-band remediation (debugging agent, 3 segments, 2 caps w/ breadcrumbs + warm resumes): all required contexts green in real CI on PR #5; merged |
| 05:24–07:09 | review count → 0 (operator-authorized); main merged into feature branch (1 trivial .gitignore conflict, union-resolved by orchestrator); PR #4 checks all green; PR #4 merged |
| 07:10 | 6b run-summary re-stamp; transcripts preserved (25 files + MANIFEST; 5 byte-identical pairs flagged — small bash watcher outputs, verify at source) |

## 4. Operator touchpoints (criterion-2 journal — adjudicate each)

Sanctioned candidates:
1. **Elicitation answers** (2 AskUserQuestion rounds, 8 answers, all "Recommended") — operator-run skill, pre-pipeline by definition (TA/A-1).
2. **plan-approved** human touch (with the §5 anomaly).
3. **diff-approved** via approve-diff.sh, 04:16:52Z, hash `ed2f406b…`.
4. **Escalation answers** (option-selection, journaled): Q1 "Separate CI-fix PR first (Recommended)"; Q2 "Drop count to 0 (Recommended)". Pipeline-initiated, no re-teaching content.

Gray-zone items the auditor must classify:
5. **Orchestrator ran `gh api PATCH …required_approving_review_count=0`** — operator-selected, but it is a standing repo-policy change executed by the orchestrator, not env provisioning. Sanctioned escalation answer or intervention?
6. **Orchestrator resolved the PR #4 merge conflict and pushed `a56c573`** after diff-approved — an artifact-affecting act on the main thread. Content: pure integration (union of one .gitignore line; arch doc auto-merged); the approved feature commit is intact beneath it; deployment-gate anchored fe8abbe which was already pushed. But the tree that merged ≠ the tree the human approved byte-for-byte. Does the diff-approved currency contract need a post-merge-integration clause?
7. **CI-fix commit `a04b93b` was made by the debugging agent, not deployment, with NO deployment-gate** — operator-authorized out-of-band, but it is a commit+push+PR by a non-deployment agent. The gate story for non-feature commits is currently: nothing.

## 5. Anomalies & deviations (honest list)

- **A1 — Checkpoint race:** the operator answered "Approved — marker touched" while `plan-approved` did not exist; it appeared ~2h later (session gap). The orchestrator correctly refused to proceed and polled. Engine delta candidate: a plan-side helper like approve-diff.sh (TTY-only, writes the marker) so "answered but not touched" cannot happen; or make the marker-wait watcher the documented standard.
- **A2 — Sessions collapsed:** operator asked for Step 3 and Step 4 in *separate sessions*; both ran in one session (an orchestrator cannot mint a new top-level session). Elicitation context therefore preceded orchestration in the same context window. Assess contamination risk (the elicitation content also lives in requirements.md, which is the sanctioned channel).
- **A3 — /code-review verify deviation:** skill says one verifier per candidate; the orchestrator batched 16 candidates into 2 verifier agents (cost call). Verdicts looked well-evidenced. Either codify batched verification or flag as non-compliant.
- **A4 — testing `status: pass` with a failing suite test:** the pre-existing perf test failure was excluded as out-of-diff (diff-scoping) and disclosed in notes/PR. The gate predicate consumed `pass`. Auditor: is "pass with disclosed pre-existing failure" the intended contract, or does it need an explicit `pre_existing_failures[]` field so the gate (and CI expectations) are structured rather than prose?
- **A5 — CI-green is not a pipeline stage:** the run's actual blocking condition after deployment was GitHub CI + branch protection, and everything from 04:25 to 07:09 was improvised under an escalation. It worked, but the loop-exit ≡ gate invariant does not extend to the merge. Engine delta candidate: a modeled post-deployment "merge phase" (watch checks → classify failure as diff-caused vs pre-existing → route accordingly → merge on green), so the next red PR is procedure, not improvisation.
- **A6 — Two debugging caps on one remediation:** the CI-fix task was feature-sized (14 files, 6 root causes) and single-shot; it capped twice (breadcrumbs + warm resumes worked as designed, ~260k subagent tokens total). The M4 per-task-segment lesson (F-M4-11) currently applies only to implementation. Candidate: extend task decomposition to large remediation prompts.
- **A7 — U-10 ledger not executed:** no `docs/finding-ledger.md` exists in this repo; deferred findings were recorded in orchestrator memory (feature 1–3 precedent). The `static.sh` assertion lives in the engine repo, so nothing failed — but the convention is unimplemented app-side. Candidate: bootstrap-project.sh seeds the ledger file.
- **A8 — codeburn snapshots: none taken** (TA/B-6 is operator-out-of-band; operator never ran it). Retrospective cost column will be duration-proxy only.
- **A9 — OSV exit 127 had been masking a real CVE** (pytest 6.8, dev-only, waived with review date 2026-10-09) and **Checkov had never run** (Trivy failed first; true surface 27 Trivy + 48 Checkov, not the remembered "12 AWS-0104"). Both are *scanner-liveness* failures: a broken scanner step reads as "no findings" until someone fixes the step. Candidate: a deterministic scanner-liveness check (each scan job must emit a parseable result artifact, empty ≠ absent).
- **A10 — review-count now 0 on main** — standing policy change; restore when a second maintainer exists.

## 6. Findings inventory (for ledger/backlog adjudication)

- **/code-review (all deferred by human at diff approval; 14 CONFIRMED, 2 PLAUSIBLE).** Top: (1) `GET /v1/quotas` silently ignores unknown query params, against the API-wide `extra='forbid'` convention — escaped planning's validation-contract table, implementation, security, testing, and both plan audits; caught only by the late review net. Escape-class question for the auditor: should planning's validation-contract rule require an explicit "no-params" contract for param-less endpoints (deterministically checkable)? (2) AC19 fail-closed test is vacuous (monkeypatch raises pre-SQL; rollback never exercised) and (3) AC16 redaction assert is vacuous (seed log already contains the sentinel) — a "prove the assertion can fail" adversarial check or a planted-eval defect would catch this class; mutation testing would too but mutmut is inert on win32 (`test-quality.json` `quality_ok:false`). (4) migration-count time-bomb test (`len == 3`). (5) unbounded list query (unpaginated was operator-pinned; the absence of ANY cap was not). Full list: memory `feature4_quota_admin_shipped.md`; verdicts in the /code-review section of the session transcript.
- **Security warnings (2, non-blocking):** pytest CVE 6.8 (now formally waived in `osv-scanner.toml` via PR #5); Tier-1 throttle IP-keying behind ALB (pre-existing, backlog).
- **PR #5 accepted-risk waivers** (`.trivyignore`, `.checkov.yaml`, `.gitleaks.toml`, `osv-scanner.toml`) — each per-ID justified; a reviewer can veto any. Recommended follow-up: dedicated IaC-hardening pass to convert deferrals into fixes.

## 7. Evidence pointers

- Machine records: `.pipeline/run-summary.json`, `.pipeline/run-log.jsonl`, `.pipeline/loop-state.json` (status completed, cycles 1/5).
- Artifacts: `requirements.md`, `plan.md` (+ Revision notes), `plan-audit.md`, `acceptance.md` (19 criteria, AC18 delegated), `security-report.md`/`security-status.json`, `test-results.json`, `test-quality.json`, `dast-review.json` (0 high, within budget), `pr-description.md`, `review-manifest.json`, `diff-approved`, `surface-delta.md`, `debug-notes.md` (CI-fix root causes), `implementation-progress.md`. Durable copies: `docs/decisions/feature/quota-admin/`.
- Transcripts: `.pipeline/transcripts-quota-admin/` (25 files, `MANIFEST.sha256`; 5 byte-identical pairs flagged — believed to be trivial watcher outputs, verify).
- GitHub: PR #4, PR #5; CI runs 29068770309 (red, pre-fix), 29071101754 (PR #5 green), 29071326693 (PR #4 green post-update); main protection now `required_approving_review_count: 0`.

## 8. Suggested audit order

1. Adjudicate §4 items 5–7 (the criterion-2 gray zone) — they define whether this counts as a clean run with sanctioned touchpoints or a run with interventions.
2. Decide the A5 merge-phase question — it is the largest structural gap this run exposed.
3. Convert §6's escape classes into ledger actions (efficacy question / planted defect / deterministic check / accepted).
4. Sweep A1–A10 for engine deltas worth codifying the same week (U-12: definitions, not prompts).
