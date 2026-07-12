---
audit_of: "feature 5 — usage-daily (GET /v1/usage/daily)"
run_started: "2026-07-11T20:18:38Z"
first_stage_logged: "2026-07-11T20:35:25Z"
deployment_logged: "2026-07-12T00:24:31Z"
pr_7_merged: "2026-07-12T01:03:20Z"   # feature — merge commit a87d3b6
pr_8_merged: "2026-07-12T01:09:57Z"   # finding-ledger — merge commit 077014d
feature_commit: "597e0ea"
assurance: "standard"   # Python 3.12 / FastAPI — deterministic gates fully applicable
source_of_truth: ".pipeline/run-summary.json + .pipeline/run-log.jsonl (all numbers below quoted from these, per the retrospective rule — never hand-written)"
---

# Pipeline session audit — usage-daily (feature 5)

Full run from planning to merge, driven on the main thread per `pipeline-orchestration`.
Outcome: **shipped and merged** (PR #7 → `main` `a87d3b6`; ledger PR #8 → `077014d`), all
required CI green, both human checkpoints honored with TTY-typed, hash-verified markers.

## 1. Stage scorecard (from `run-summary.json`)

| Stage | Invocations | Max attempt | Caps | Model(s) | Last status |
|---|---|---|---|---|---|
| planning | 2 | 2 | 0 | opus | pass |
| plan-audit | 1 | 1 | 0 | sonnet | pass |
| implementation | 5 | 5 | 1 | sonnet | pending-smoke* |
| security | 2 | 2 | 0 | opus | clean |
| debugging | 1 | 1 | 0 | opus | pass |
| testing | 1 | 1 | 0 | sonnet | pass |
| deployment | 1 | 1 | 0 | sonnet | pass |
| **documentation** | **0 logged** | — | — | — | **UNDER-LOGGED — see §6** |

- `first_pass_clean: false` (a security remediation occurred — correct).
- `loop_cap_events: 0` — the circuit-breaker never fired; the run-to-condition loop closed in **2 cycles**.
- `models_used: [opus, sonnet]`. Planning/security/debugging on opus; plan-audit/impl/testing/deployment on sonnet.
- `totals.suspected_underlog: 1` — the summary itself flags one missing stage line (documentation).
- *Implementation's `pending-smoke` last status is a logging artifact (§6), not a failed smoke — the gate
  artifact `smoke-status.json` read `pass`.
- **Cost note:** per-stage token/$ cost is NOT in this file (shell hooks can't read tokens). A `codeburn`
  snapshot was not captured this run; treat the model + invocation counts above as the only cost proxy.

## 2. Gate outcomes

- **Loop-exit GREEN** was evaluated deterministically (jq on the status files, never LLM-judged):
  - security: `status=clean`, `critical_count=0`, `osv_max_cvss=0`, empty input/data surfaces, `asvs.reconciled=true`, `scan_reconciled=true`
  - testing: `status=pass`, 255 passed / 0 failed / 4 skipped (259 total), coverage **91.94% line / 93.59% branch**, criteria **15/15** (none delegated), perf `n/a`
  - test strategy `pyramid` (unit 25 > integration 17 > e2e 0 — not inverted).
- **One real critical, found and fixed in-loop:** the STRIDE model named `usage_rollup_tenant_isolation`
  RLS as an enforced IDOR backstop, but migration `0002` used `ENABLE` without `FORCE` and the app
  connects as the table owner (`meterly_app`) → owner-bypass → **inert backstop** (U-02, presence≠efficacy).
  Debugging added migration `0004` (`FORCE ROW LEVEL SECURITY`, mirroring `0003` on `quotas`) plus a
  DB-layer owner-role efficacy test that **fails at 0003 / passes at 0004** — a genuine efficacy witness,
  not a presence check. Re-scan returned clean. `remediation` retry counter reached 1/3 (well under cap).

## 3. Human checkpoints (both honored)

| Checkpoint | Marker | Evidence |
|---|---|---|
| Plan | `plan-approved` | TTY-typed via approve-plan.sh; `plan_sha256` matched post-revision `plan.md` |
| Diff | `diff-approved` | TTY-typed via approve-diff.sh; `approved_change_hash` = `77176307…` matched the working tree |

Neither marker was ever orchestrator-written. A chat "go"/"I approve" was explicitly **not** treated as
the gate — the marker file was checked and hash-verified both times before proceeding.

## 4. Operator touchpoints (proof-gate criterion 2)

**Sanctioned (not counted against the run):**
- The two checkpoint approvals (plan, diff).
- Merge authorizations for PR #7 and PR #8 (answers to a pipeline-initiated block: the auto-mode
  classifier gated `gh pr merge` "merge without review"; the operator explicitly typed "merge").
- **Host provisioning:** the operator granted the GitHub PAT "Pull requests: write" scope after
  `gh pr create` failed with `Resource not accessible by personal access token` — journaled env
  maintenance, wrote no pipeline artifact, changed no gate outcome.

**Necessary pre-flight clarification (journaled, not an improvised steer):**
- At kickoff the repo state contradicted the cleanup brief (no `feature/usage-daily` branch existed;
  `PROJECT.md` still described the shipped quota-admin feature; `.pipeline` held the completed
  quota-admin run). The orchestrator **stopped and asked** rather than deleting on a false premise.
  The operator chose "update PROJECT.md first" and supplied the usage-daily brief, which the
  orchestrator wrote to `PROJECT.md` verbatim at explicit instruction.

**Autonomous decisions (disclosed, no operator edit):**
- Commit scope: the human-approved change-hash included `.claude/settings.json`,
  `.claude/settings.local.json`, and `PROJECT.md`. Because the deploy gate binds the commit to that
  exact working-tree hash and a partial commit leaves a dirty tree that blocks `git push`, the
  orchestrator committed the **entire** approved change-set (disclosed the `.claude/` inclusion as
  trivially reversible). No re-approval was possible (operator had stepped away; approve-diff is TTY-only).

No mid-run re-teaching, artifact edits, or steering prompts were required. Criterion-2 clean.

## 5. Environmental issues (all environmental, none code defects)

1. **OneDrive quarantined the venv interpreter mid-run.** `.venv/Scripts/python.exe` vanished
   (only `.venv/Lib` survived) after testing. Local execution died; CI (clean env) was the real
   enforcement. A text-only doc-contract test still ran under system `pytest`.
2. **WSL can't reap the Windows-venv `uvicorn` → port-8000 zombies.** This caused implementation
   smoke attempts 2–4 to fail with `WinError 10048`, and the DAST capture to no-op ("app did not
   come up"). Diagnosis required `netstat.exe`/`tasklist.exe` (WSL `ss`/`pgrep` can't see Windows
   sockets). Force-kill via `taskkill.exe` was permission-blocked; the implementation agent cleared
   the port itself on resume, after which smoke read `pass`.
3. **PAT lacked PR-write scope** → blocked `gh pr create` until the operator granted it (§4).

(All three are saved to project memory: `env-wsl-windows-onedrive-gotchas`.)

## 6. Caps, anomalies & honesty items

- **Implementation cap (1, breadcrumbed).** Attempt 1 hit the turn cap mid-verification; a
  `log-run.sh implementation "" capped` breadcrumb was logged per audit-T1, then the agent was
  warm-resumed (pointed at `implementation-progress.md`, told not to restart). Attempts 2–4 are the
  **environmental** smoke cascade (§5.2), not implementation failures. Attempt 5 completed.
- **`pending-smoke` final impl status.** The successful smoke came from a manual hook run once the port
  was free, so `log-run` recorded `pending-smoke` rather than `pass`. The gate artifact
  (`smoke-status.json`) was `pass`; the loop-exit predicate reads security/test status, not smoke.
- **Documentation stage is UNDER-LOGGED (process gap).** Documentation completed successfully
  (`pr-description.md`, `review-manifest.json`, README/architecture updates all verified, doc-contract
  test green) but its Stop hook did not fire (a cosmetic cap while finalizing the review-manifest), and
  **no cap breadcrumb was logged for it** — so `run-summary.json` shows 7 stages instead of 8
  (`suspected_underlog: 1`). This is the one audit-T1 miss of the run. → engine-delta §8.
- **DAST honesty gap (tooling).** `dast-capture.sh` correctly refused ("NOT reporting DAST-clean") when
  the app wouldn't boot, but `dast-review.sh` then read a **stale** `dast-capture.json` from the prior
  quota-admin run and emitted a fresh-timestamped `within_budget: true`. The orchestrator caught this
  and had documentation disclose "DAST effectively skipped — not representative" in the PR, but the
  tool itself should have refused. → engine-delta §8.
- **Mutation testing never ran** (mutmut is inert on win32; the CI mutation job is `if: false`).
  `quality_ok` was honestly not claimed.

## 7. Deviations from plan (all disclosed in the PR)

- **Sanctioned migration `0004`** despite the plan's "no new migration" — driven by the security
  critical; behavior-preserving (all `usage_rollup` access runs inside `scoped_transaction`).
- **Modified an existing test** — quota-admin's `test_no_new_alembic_migration_added` was updated to
  permit the one sanctioned migration while preserving its intent (DDL on `usage_rollup` only).
- **`.claude/` + PROJECT.md committed with the feature** (§4) — reversible follow-up if unwanted.

## 8. Ledger deltas & engine-delta candidates (U-10 / U-12)

**Finding-ledger (landed in PR #8):** `F5-01` (SUM→Decimal into int-annotated field, masked),
`F5-02` (90-day lookback triplicated), `F5-03` (auth-throttle helper triplicated), `F5-P1` (PLAUSIBLE
`DailyMetricCount` name collision), `F5-S1` (pre-existing `events`-table non-FORCE-RLS owner-bypass —
the highest-value follow-up: it wants its own FORCE migration + owner-isolation test, mirroring `0004`).

**Recommended engine deltas (codify, don't leave in this prompt — U-12):**
1. **`dast-review.sh` must refuse on a skipped capture.** When `dast-capture.sh` did not produce a fresh
   capture (app didn't boot), the review must report `skipped/not-representative`, never compare a stale
   `dast-capture.json` to budget and print `within_budget`. This is a latent false-assurance bug.
2. **Documentation cap breadcrumb.** The orchestrator should breadcrumb a documentation Stop-hook cap
   (`log-run.sh documentation "" capped`) exactly as it does for implementation/testing, so
   `run-summary` never silently under-counts a stage.
3. **Windows/WSL environment pre-flight.** Add a pre-flight assert that the venv interpreter exists and
   port 8000 is free, with a documented `taskkill.exe` cleanup path — the OneDrive/WSL trio cost most of
   the run's wall-clock and produced a misleading smoke-fail cascade. (Captured in project memory.)
4. **`repo-relative venv invocation` under `timeout`.** `timeout .venv/Scripts/python.exe …` fails to
   exec; wrap in `bash -c`. Minor, but bit the doc-contract re-check.

## 9. Bottom line

A clean run on the pipeline's own terms: deterministic GREEN, one real security critical caught and
fixed with a genuine efficacy test, both human gates honored, honest disclosure of every skip and
deviation. The friction was almost entirely the Windows/WSL/OneDrive environment, not the pipeline
logic. The single process miss was the un-breadcrumbed documentation cap (§6). All deferred findings
are ledgered, and the most consequential follow-up (`F5-S1`, the `events` RLS gap) is flagged for a
dedicated fix.
