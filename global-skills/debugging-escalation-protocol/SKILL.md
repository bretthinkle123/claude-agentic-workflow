---
name: debugging-escalation-protocol
description: Retry caps, the sanity-vs-remediation role split, cap-out reporting, and when to escalate to planning versus patch in place for the debugging agent.
---

# Debugging escalation protocol

You fix specific, reported problems — never redesign the implementation's
approach. There are two roles, one debugging agent definition.

## The two roles

- **Sanity role** — triggered when the **smoke check fails** (the code doesn't
  build/run). Loop back to the smoke check until it passes. Uses the
  `sanity` retry counter.
- **Remediation role** — triggered when **security reports a critical finding**
  (`status: issues-found`) or **a test fails**. After your fix, re-run **both**
  security and testing (a fix can break either). Uses the `remediation` counter.

A bare warning never triggers remediation — only `critical_count > 0` or a
failing test does.

## Retry caps (two independent mechanisms)

1. **Attempt cap** — `max_retries: 3` per role, tracked in `.pipeline/state.json`.
   Before each fix: read `state.json`, check `debug_retry_count.<role>` against
   `max_retries`. If the cap is reached, **stop and escalate** (see below). After
   each fix, increment the counter for the current role.
2. **Per-invocation ceiling** — `maxTurns: 15`, set in the agent frontmatter,
   bounds turns within a single run.

`state.json` is initialized at bootstrap and recreated by security if missing.
If it is somehow still absent, treat the counts as zero and `max_retries` as 3 —
never fail on its absence.

Both counters reset to zero on a clean gate pass (via `record-clean.sh`), so the
next feature starts with a fresh budget.

## `maxTurns` caveat

A `Stop`/`SubagentStop` hook **may not fire** if the agent hits `maxTurns`
(the session ends first). So **report cap-outs and escalations from inside the
agent** — never rely on a trailing hook to surface them.

## Escalate vs patch

Patch in place when the fix is a localized correction to a specific finding.

**Escalate to planning** (a flagged stop for human review, not automated
re-entry) when either:
- the chosen approach itself can't satisfy the requirement (unpatchable as a
  patch — a redesign is needed), **or**
- the retry cap is hit without resolution.

Do not attempt a redesign yourself, and do not loop indefinitely. Testing and
security never escalate to planning directly — they only ever report to you.
