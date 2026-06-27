---
name: pipeline-orchestration
description: Stage order, the .pipeline/* interlock-file contracts, gate semantics, and the fresh-context handoff rule for whoever drives the multi-agent SDLC pipeline.
---

# Pipeline orchestration

Invoke this at session start when you (the human / main thread) are driving the
pipeline. You are the orchestrator — you call each subagent via the `Agent` tool.
**Subagents never call each other**, and each starts with **fresh context**: it
sees only its system prompt + the prompt string you pass. All cross-stage state
travels through `.pipeline/*` files. Pass everything a stage needs via its prompt
string and those files — never assume it can see the conversation.

## Stage sequence

```
1. Agent(planning, "Plan <feature>. Write .pipeline/plan.md incl. STRIDE threat model.")
1b. Agent(plan-audit, "Audit .pipeline/plan.md. Write .pipeline/plan-audit.md.")  # automatic, before the human
     -> review plan.md + plan-audit.md, then: touch .pipeline/plan-approved       # human checkpoint
2. Agent(implementation, "Implement .pipeline/plan.md.")
     -> smoke-check.sh (+ infra-validate.sh) fire on Stop
     -> if smoke fails: Agent(debugging, "<error>") up to max_retries, then re-smoke
3. Agent(security,  "Scan per diff-scoping-conventions. Write security-report.md + security-status.json.")
4. Agent(testing,   "Add missing tests, run suite. Write test-results.json (incl. tested_change_hash).")
     -> record-clean.sh fires on Stop (resets retry counters iff both gates clean)
     -> if security issues-found OR any test fails:
          Agent(debugging, "<finding>") up to max_retries, then re-run BOTH security + testing
5. Agent(documentation, "Update docs for the diff. Write pr-description.md + review-manifest.json.")  # only when both gates clean
     -> REVIEW POINT: read code, tests, docs, pr-description before deploying
6. Agent(deployment, "Commit the reviewed change and open a PR on GitHub.")
     -> deployment-gate.sh (PreToolUse) blocks the commit unless all four gates pass
```

## Telemetry — logged automatically on every stage

`log-run.sh` is wired as a **`Stop` hook on all eight agents**, so one line is
appended to `.pipeline/run-log.jsonl` automatically when each agent finishes — the
orchestrator does **not** call it. The hook signature is:

```
$HOME/.claude/hooks/log-run.sh <stage> <model> [status] [retries] [notes]
#   status: auto-derived from the stage's artifact when omitted
#           implementation→smoke-status.json, security→security-status.json,
#           testing→test-results.json, debugging→state.json (retry cap);
#           other stages default to "pass" (= ran to completion)
```

`feature` is auto-derived from the git branch; `model`, `files_changed`, and (for
testing/security) coverage and finding counts are captured too. From this log you
derive cost-proxy per stage (model + files_changed), first-pass gate rate (features
reaching documentation with `retries==0`), and debug-retry/escalation rate.

**Caveat:** a `Stop` hook does **not** fire if an agent hits its `maxTurns` cap —
the session ends first — so a capped-out stage is silently absent from the log.
A missing stage line is itself a signal (suspect a cap-out). `duration_s` and
`tokens` are not available to shell hooks; use timestamp deltas between lines as a
duration proxy.

## Bootstrap (once per project)

Run `bash ~/.claude/pipeline-templates/bootstrap-project.sh` from inside the
target repo root (flags `--start`, `--health`, `--test`, `--build` are optional
and pre-wire the smoke check). Before each new feature, remove any stale
`.pipeline/plan-approved` marker.

## Interlock-file contract

| File | Writer | Readers |
|---|---|---|
| `plan.md` | planning | plan-audit, human, implementation, testing, documentation |
| `plan-audit.md` | plan-audit | human (advisory — read at the checkpoint; non-gating) |
| `plan-approved` | human | implementation (refuses to start without it) |
| `security-report.md` / `security-status.json` | security | documentation (md), gate hooks (json) |
| `test-results.json` | testing | record-clean.sh, deployment-gate.sh, documentation |
| `pr-description.md` | documentation | deployment, gate |
| `review-manifest.json` | documentation | deployment-gate.sh (currency anchor) |
| `state.json` | bootstrap / security / debugging | debugging, record-clean.sh |
| `smoke-status.json` | smoke-check.sh | log-run.sh (implementation status) |
| `run-log.jsonl` | each agent's `log-run.sh` Stop hook | you (metrics) |

## Gate semantics

- **Planning → plan-audit → human checkpoint:** `plan-audit` runs automatically
  after planning and writes `plan-audit.md` (ambiguity, dependency-reality, and
  version-policy flags). It is **advisory, not a gate** — it never blocks; the
  human reads it alongside `plan.md` before approving.
- **Planning → implementation:** `plan-approved` marker (human).
- **Smoke / infra:** deterministic hooks; exit 2 routes to sanity debugging.
- **Security → testing:** serial by default (token cost over wall-clock).
- **Both clean → documentation:** don't invoke docs until `security-status.json`
  is `clean` and `test-results.json` is `pass`.
- **Documentation → deployment:** the `PreToolUse` gate enforces tests pass,
  security clean, `pr-description.md` exists, and currency vs `reviewed_change_hash`.

## Debug-loop routing

Sanity (smoke fail) and remediation (security critical or test fail) are the same
agent, different counters. **Remediation always re-runs both gates**, never just
the one that failed. Cap at `max_retries`; on cap-out or an unpatchable finding,
debugging escalates to planning (a flagged human stop, not auto re-entry).
