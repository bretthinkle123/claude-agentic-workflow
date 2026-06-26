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
     -> review plan.md, then: touch .pipeline/plan-approved        # human checkpoint
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

## Telemetry — log every stage boundary

After each stage returns, append one line to `.pipeline/run-log.jsonl` with the
deterministic helper (zero-LLM):

```
.claude/hooks/log-run.sh <feature> <stage> <status> [retries] [notes]
#   status: pass|fail|clean|issues-found|blocked|escalated
```

This is the only telemetry the pipeline keeps. From it you derive token cost per
feature, first-pass gate rate (features reaching documentation with `retries==0`),
and debug-retry/escalation rate. Skipping it = flying blind on whether the pipeline
is improving. Log on every stage, including failures and escalations.

## Bootstrap (once per project)

`mkdir -p .pipeline`, initialize `state.json`
(`{"debug_retry_count":{"sanity":0,"remediation":0},"max_retries":3}`), add
`.pipeline/` to `.gitignore`, and remove a stale `plan-approved` before a new
feature.

## Interlock-file contract

| File | Writer | Readers |
|---|---|---|
| `plan.md` | planning | human, implementation, testing, documentation |
| `plan-approved` | human | implementation (refuses to start without it) |
| `security-report.md` / `security-status.json` | security | documentation (md), gate hooks (json) |
| `test-results.json` | testing | record-clean.sh, deployment-gate.sh, documentation |
| `pr-description.md` | documentation | deployment, gate |
| `review-manifest.json` | documentation | deployment-gate.sh (currency anchor) |
| `state.json` | bootstrap / security / debugging | debugging, record-clean.sh |
| `run-log.jsonl` | orchestrator (per stage) | you (metrics) |

## Gate semantics

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
