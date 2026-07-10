# M4″ run — independent audit (feature quota-admin)

Audited 2026-07-10 by a separate session from the orchestrator's. Input: `.pipeline/m4pp-audit-input.md`
(treated as the auditee's self-report). Every claim below was checked against primary evidence:
`run-summary.json` (final 07:10:04Z + the 4c snapshot preserved in `docs/decisions/feature/quota-admin/`),
`run-log.jsonl` (11 lines), `loop-state.json`, `scan-log.jsonl`, `security-status.json`,
`test-results.json`, `test-quality.json`, `debug-notes.md`, `plan-audit.md`, `requirements.md`,
`diff-approved`/`review-manifest.json`, the transcripts MANIFEST (25 files), and GitHub live state
(PRs #4/#5, CI runs 29068770309 / 29071101754 / 29071326693, main's branch protection, commit graph
including `git show --cc a56c573`).

---

## (a) Adjudications

### §4 item 5 — orchestrator ran `gh api PATCH … required_approving_review_count=0`

**Verdict: SANCTIONED escalation answer — with a scope correction the self-report missed.**

The operator's touch was in-channel: an AskUserQuestion option-selection ("Drop count to 0
(Recommended)"), journaled, no re-teaching content — that satisfies criterion 2. The orchestrator
executing it is more than env provisioning, but it was explicitly operator-selected and surfaced
as open item A10 with a revert condition.

**Correction:** the self-report's timeline places the drop in the "05:24–07:09" window tied to
PR #4's merge. GitHub shows **PR #5 merged 2026-07-10T05:24:12Z with zero reviews**
(`gh pr view 5 --json reviews` → `"reviews":[]`; same for PR #4), and a sole-maintainer repo with
count ≥ 1 cannot merge its own PR at all. The PATCH therefore **preceded PR #5's merge** and
unblocked *both* merges — including the ungated PR #5 (see item 7) — not just PR #4. The
self-report understates the policy change's blast radius.

Codified going forward (pipeline-orchestration 6c): standing repo-policy changes only on an
explicit journaled operator selection, recorded with a revert condition; prefer operator-executed;
if orchestrator-executed, the exact command + before/after state goes in the journal.

### §4 item 6 — orchestrator resolved the PR #4 merge conflict and pushed `a56c573`

**Verdict: SANCTIONED IN SUBSTANCE (pure integration, evidence-verified) — and yes, the
diff-approved currency contract needed the post-merge-integration clause. Now added.**

Evidence, stronger than the self-report's own claim:
- `git show a56c573 --cc` output is **empty** — no path in the merge result differs from both
  parents, i.e. the hand-resolution introduced **zero novel bytes**.
- The resolved `.gitignore` is **byte-identical to the main parent `0d00cd5`**
  (`git diff 0d00cd5 a56c573 -- .gitignore` → empty), and main's version was a strict superset of
  the feature side (feature added `.terraform/`; main had it plus `.coverage.*` and
  `.terraform.lock.hcl`). "Union-resolved" is accurate in effect.
- All src/tests drift between approved `fe8abbe` and merged `a56c573`
  (`usage_repo.py` nosemgrep comments, the perf-marker test change) is exactly PR #5's content
  arriving via the main parent — nothing else.

So the tree that merged ≠ the tree the human approved byte-for-byte, but the delta is entirely
main's already-merged, CI-green content. The act was outside any stage contract (that's why it's
in the gray zone), but it is not an intervention in substance. The contract gap is real and is
now closed: pipeline-orchestration 6c's POST-INTEGRATION CURRENCY clause — no re-approval iff
(a) `git show --cc <merge>` is empty AND (b) the recomputed feature-side change hash over
`git diff <new-merge-base>...HEAD` matches the approved scope; otherwise back to the 5b checkpoint.

### §4 item 7 — CI-fix commit `a04b93b` by the debugging agent, no deployment-gate

**Verdict: IMPROVISED INTERVENTION — correctly escalated and benign in outcome, but the material
process hole of this run.**

PR #5 changed **app source** (`scripts/seed_api_key.py`, `src/repositories/usage_repo.py`), tests,
workflows, and infra — 14+ files — with: no deployment-gate, no diff-approved, no security/testing
stage pass over its diff, and (per item 5) **zero human GitHub review**. The compensating controls
were real: operator authorization via the escalation channel, all required CI contexts green on the
actual merge ref (run 29071101754), per-fix evidence in `debug-notes.md`, and per-ID-justified
committed waiver files reviewable in the PR. Outcome verified fine. But "the gate story for
non-feature commits is currently: nothing" is exactly right, and it worked because this operator
and this remediation were careful — that's luck plus CI, not process. Now modeled: 6c requires
non-feature commits to get the same human anchor the feature got (`approve-diff.sh` on the ci-fix
diff, or an explicit journaled operator waiver naming what was skipped) before their PR merges.

### A2 — elicitation and orchestration collapsed into one session

**Verdict: CONFIRMED deviation, LOW actual contamination.** All 8 answers were "Recommended"
options the skill itself generated, and `requirements.md` (9 resolved / 0 open / 6 out-of-scope)
captures the full content — nothing existed in the interview that didn't land in the sanctioned
artifact. Structurally, stage agents spawn with fresh contexts, so the contamination surface is
the orchestrator's own framing (escalation phrasing, checkpoint summaries), not stage inputs.
Delta applied: requirements-elicitation now ends with an explicit fresh-session handoff
instruction, and an in-session kickoff must be journaled as a deviation.

### A3 — /code-review verification batched 16 candidates into 2 verifiers

**Verdict: NON-COMPLIANT with the skill as written; ACCEPTED and codified with conditions.**
Verdicts were per-candidate and well-evidenced (14 CONFIRMED / 2 PLAUSIBLE), and one-verifier-per-
candidate is a pure cost multiplier at this candidate count. /code-review is a built-in skill (not
engine-owned), so the rule lives in pipeline-orchestration 5b: batching allowed above 8 candidates,
≤ 8 candidates per verifier, per-candidate verdicts with own evidence quotes, interacting
candidates share a verifier, and the batching is disclosed to the human.

### Criterion-2 bottom line

Touchpoints 1–4 sanctioned as claimed. Item 5 sanctioned (corrected scope). Item 6 sanctioned in
substance (verified pure integration; contract gap now closed). Item 7 is a genuine **improvised
intervention** — so M4″ is **not a fully clean run**: it is a clean loop (cycle 1 GREEN, zero debug
retries, verified) followed by an out-of-band remediation that the engine had no procedure for.
The remediation was disciplined and evidence-preserving; the deficiency was structural (A5), and
the fix is the merge phase, not a process violation finding against the orchestrator.

---

## (b) Self-report claims: confirmed vs corrected

**Confirmed against primary evidence:**
- Machine summary §2 exactly matches `run-summary.json` and `run-log.jsonl` (11 lines, 2 capped
  debugging lines on `ci-fix/required-checks-green`, stages/models/attempts as listed).
- The attribution nuance is real: the preserved 4c snapshot (`docs/decisions/feature/quota-admin/
  run-summary.json`, 03:50:19Z) shows `first_pass_clean: true`, 5 stages, 0 caps; the final
  07:10:04Z stamp flips to `false` solely from the post-deployment debugging lines. **Ruling on
  the question posed:** keep the stable per-feature key for cost attribution, but `first_pass_clean`
  is a *loop-window* metric — remediation lines (distinguishable by branch) must not overwrite it.
  Codified in 6c; `run-summary.sh` segmentation is a proposed script change (see (d)).
- Loop: `loop-state.json` cycles 1/5, completed 03:50:18Z. GREEN-on-cycle-1 confirmed.
- `diff-approved` hash `ed2f406b…` matches `review-manifest.json`; approved 04:16:52Z. Confirmed.
- PR #4 merged 07:09:44Z (`3fb8d11`), PR #5 merged 05:24:12Z (`0d00cd5`); CI 29068770309 red on
  `fe8abbe`, 29071101754 green on `a04b93b`, 29071326693 green on `a56c573`. All confirmed live.
- Branch protection: 7 required contexts, `strict: true`, `enforce_admins: true`,
  `required_approving_review_count: 0`. Confirmed.
- A9's substance, at source: `scan-log.jsonl` has **no checkov execution stamp at all**, yet
  `security-status.json` records `checkov_findings: 0`; `debug-notes.md` documents the CI OSV
  exit-127 (v2 image removed `--lockfile-scan-mode`) masking the pytest CVE, and Checkov's
  first-ever run surfacing 48 failed checks. Also noted beyond the self-report: every
  `scan-log.jsonl` row has **empty `output_path`/`output_sha256`**, and trivy-fs ran (stamped,
  exit 0) but was omitted from `scan_artifacts` — the liveness gap is wider than the two named
  incidents.
- A7: no `docs/finding-ledger.md` existed app-side. Confirmed (now bootstrapped, PR #6).
- Transcripts: 25 files + MANIFEST present; the duplicate-flagged files verified at source as
  trivial git-diff watcher snapshots (~40KB each).

**Corrected:**
1. **Review-count timing/scope (material):** the drop to 0 preceded PR #5's merge and unblocked
   both PRs, including the ungated one. Self-report ties it to PR #4's merge window. (Item 5.)
2. **"5 byte-identical pairs" (minor):** actually 5 files in two identity groups — one pair
   (`b2cj76cib`/`bfze1ltse`, the `.gitignore` diff snapshot) and one triple
   (`bioyzbhq1`/`blarvz8eq`/`bo1og11u4`, the README diff snapshot). Substance (trivial watcher
   outputs) holds.
3. **"marker landed 01:25 local" (trivial):** `plan-approved` mtime is 21:25 local / 01:25 UTC —
   the timeline mislabels UTC as local.
4. **Not flattered but incomplete:** §2's "checkov_findings: 0 / trivy_findings: 0" in
   security-status.json presents as clean counts; per A9's own logic these are unproven-liveness
   zeros (checkov: no execution; trivy: ran but unreconciled). The self-report flags A9 for CI but
   not for its own local status file.

No fabricated or inflated claims found. The self-report's honesty posture (deviations disclosed,
attribution nuance volunteered) is corroborated by the evidence.

---

## (c) Ledger rows written (audit job 3 / A7)

`docs/finding-ledger.md` bootstrapped in this repo on branch `audit/m4pp-finding-ledger` —
**PR #6** (docs-only; constraint honored: nothing landed directly on main). 18 rows: F4-01…F4-14
(the deferred verifier-CONFIRMED findings), F4-P1/P2 (PLAUSIBLE, accepted-watch), F4-S1/S2
(security warnings). Actions, one each:

| Row | Finding (short) | Action |
|---|---|---|
| F4-01 | GET ignores unknown query params (escaped 5 stages) | **new deterministic check** — planning must emit a no-params contract for param-less endpoints; testing asserts unknown-param 422 per route |
| F4-02 | AC19 fail-closed test vacuous | **new planted eval defect** (U-23) — plant a pre-SQL-raise vacuous test; testing agent must flag it |
| F4-03 | AC16 redaction test vacuous | **new deterministic check** — falsifiability probe: show each security-property assert CAN fail; record in test-quality.json |
| F4-04 | Migration-count time bomb (`len == 3`) | **new deterministic check** — ast-grep rule vs exact-count asserts over migration listings |
| F4-05 | Unbounded list SELECT (no cap of any kind) | **new efficacy question** (U-02) — unpaginated collection ⇒ explicit expected-max + at-excess behavior or accepted-risk note |
| F4-06…F4-14 | CORS pin, stale docstring, 8 duplication/hygiene/consistency findings | **accepted** with per-row reasons (latent-no-exposure, doc-only, refactor-backlog, next-touch) |
| F4-P1/P2 | PLAUSIBLE pair | **accepted: watch / refactor-backlog** |
| F4-S1 | pytest CVE 6.8 (waived, ignoreUntil 2026-10-09) | **accepted: waived-dev-only-below-floor** — hard review date |
| F4-S2 | Tier-1 throttle IP-keying behind ALB | **accepted: pre-existing-backlog** |

The two called-out escape classes both got teeth: the five-stage GET-params escape becomes a
deterministic planning+testing contract (F4-01), and the vacuous-test class gets both a planted
eval defect (F4-02) and the falsifiability-probe check (F4-03) — mutation testing would also catch
the class but stays unavailable on win32 (mutmut refuses natively; `test-quality.json` records the
honest `quality_ok: false`).

---

## (d) Engine deltas — made vs proposed vs rejected

**Made (live `~/.claude` copies, per U-12 — see port-back note in (e)):**

| Anomaly | File | Delta (one line) |
|---|---|---|
| A9 | `~/.claude/agents/security.md` | Scanner-liveness rule: required-scanner set derived from diff triggers; a count of 0 requires an execution stamp + non-empty artifact; not-run tools record `null`, never 0; missing required scanner = critical |
| A4 | `~/.claude/agents/testing.md` | `pre_existing_failures[]` field + contract: `pass` with `failed>0` legal only when every failure is listed with out-of-diff AND reproduces-at-base evidence |
| A6 | `~/.claude/skills/debugging-escalation-protocol/SKILL.md` | F-M4-11 extended to remediation: ≥8 files or ≥3 independent root causes ⇒ per-root-cause segments (M4″'s single-shot capped twice, ~260k tokens) |
| A2 | `~/.claude/skills/requirements-elicitation/SKILL.md` | Fresh-session handoff after requirements.md; in-session kickoff = journaled deviation |
| A3 | `~/.claude/skills/pipeline-orchestration/SKILL.md` (5b) | Batched verification codified: >8 candidates, ≤8 per verifier, per-candidate verdicts+evidence, interacting candidates co-batched, disclosed |
| A5 + items 5/6/7 | `~/.claude/skills/pipeline-orchestration/SKILL.md` (new 6c) | Merge phase: watch → classify (pre-existing = fails on merge-base run) → route (diff-caused → debugging on feature branch; pre-existing → operator-escalated `ci-fix/` side-run with own log key, decomposition, and human anchor) → post-integration currency clause → standing-policy-change rule |

**A5 structural answer: YES — merge phase modeled** (the 6c delta above is the spec):
stage contract = deployment ends at "PR opened"; 6c owns PR-checks-to-merged. Interlock:
run-log lines from remediation carry their own branch key and are excluded from loop-quality
metrics; recommend a `.pipeline/merge-status.json` `{pr, merged_sha, checks:[{context, conclusion,
classification}], currency: {cc_empty, change_hash_match}}` once the script work lands (proposed
below). Gate semantics: feature closeout (6b re-stamp / retrospective) requires the PR merged and
currency verified. Who fixes what: diff-caused = the feature run's debugging budget, on the feature
branch; pre-existing = never the feature's budget — an operator-authorized `ci-fix/` side-run
gated like a feature (human diff anchor before merge).

**Proposed (script/workflow changes — need engine-repo commits, not doc edits; not made by this audit):**
1. `run-summary.sh`: segment remediation lines by branch so `first_pass_clean` stays a loop-window
   metric; add a `post_deploy_remediation` block. (§2 attribution ruling.)
2. Scan wrappers + `reconcile-scans.sh`: stamp real `output_path`/`output_sha256` in
   `scan-log.jsonl` (currently empty on every row) and fail reconciliation on an empty artifact
   for any stamped tool. (A9, deterministic half.)
3. `pipeline-ci.yml` template: make containers-iac's Trivy and Checkov independent steps
   (`if: always()` or split jobs) with a per-step result artifact required for job green — a
   scanner step that never ran must fail the job, not vanish. (A9, CI half — the exact failure
   that hid 48 Checkov findings for two features.)
4. `approve-plan.sh`: TTY-only plan-side twin of `approve-diff.sh` so "answered but not touched"
   (A1's 2h checkpoint race) cannot happen; watcher behavior stays as documented fallback.
5. `bootstrap-project.sh`: seed `docs/finding-ledger.md` (A7) so the U-10 convention exists
   app-side from feature 1.

**Rejected / no delta:**
- A1 beyond the helper script: the orchestrator behaved correctly (refused to proceed, polled) —
  no doc-side rule needed; rejected as already-correct behavior.
- A8 (codeburn never run): operator-out-of-band by design; duration-proxy costing accepted for
  this retrospective. No engine delta.
- A10: an operator open item, not an engine delta (below).

---

## (e) Open items for the operator

1. **Restore `required_approving_review_count` to ≥1** on main the day a second maintainer
   exists (currently 0; verified live). The revert condition is now also journaled in ledger
   row context and 6c's policy rule.
2. **pytest CVE waiver review date 2026-10-09** (`osv-scanner.toml` `ignoreUntil`) — bump to
   pytest 9.x or consciously re-waive. Ledger row F4-S1.
3. **IaC-hardening follow-up pass** — convert the `.checkov.yaml`/`.trivyignore` accepted-risk
   deferrals (cross-region DR, WAF/CloudFront logging, CMK log groups, secret rotation, enhanced
   monitoring) into fixes. Ledger context in `debug-notes.md` §4.
4. **Merge PR #6** (finding-ledger bootstrap, docs-only) after review.
5. **Port the six live `~/.claude` deltas back into the engine repo** (`global-agents/security.md`,
   `global-agents/testing.md`, `global-skills/{debugging-escalation-protocol,
   requirements-elicitation,pipeline-orchestration}/SKILL.md`) — they were made on the published
   copies per U-12; the engine repo working tree is mid-branch (`feat/regulated-data-skills`,
   whose security.md already diverges), so the next publish would clobber them unless committed.
6. **Land the five proposed script deltas** in (d) — items 2 and 3 (scanner liveness enforcement)
   are the highest-value: they are the deterministic check A9 asks for, distinguishing
   "scanner ran, zero findings" from "scanner never ran" at both the local stage and CI.
7. **A8**: if codeburn costing matters for the M-series comparison, run it during the run — the
   retrospective can only duration-proxy this one.
