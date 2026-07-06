# Plan — read-only production triage agent (PR O kickoff design)

> **Status: KICKOFF DESIGN — the new-pipeline-surface half of PR O.** This is the dedicated design
> `docs/delivery-operations-plan.md` requires before the triage agent is built, with the PR-K-level
> threat model a new agent surface deserves. The *other* half of PR O — the observability wiring
> itself (Sentry SDK, OTel→CloudWatch, SLO burn-rate alarms, synthetics, dSYM/source-map upload) —
> is per-project scaffolding with no open design question and ships alongside per
> `delivery-operations-plan.md`; this doc covers only the agent.

## What it is (and the one sentence that bounds it)

**A read-only incident summarizer whose output is an input to the normal pipeline — never an
actor.** Operator-invoked, it pulls ONE incident's evidence from Sentry, writes
`.pipeline/incident-brief.md`, and stops. A fix happens only if the human feeds that brief into a
normal pipeline run (planning → plan-approval → … → diff-approval → PR). It cannot deploy, cannot
write code, cannot approve anything — by *tool absence*, not by instruction.

## Agent definition

- **`global-agents/triage.md`** — model `opus` (root-cause reasoning across noisy telemetry is the
  same class of work the debugging agent runs on opus), `maxTurns` 15.
- **Tools: `Read, Grep, Glob, Write, mcp__sentry` (read-only scopes only).** No `Bash`, no `Edit`.
  `Write` is required for the brief; the marker guard already denies every approval marker to
  agents, and no Bash means no gh/git/aws surface at all.
- **Trigger: operator-invoked only** (`claude --agent triage "SENTRY-1234"`). *Rejected:*
  auto-trigger on alert — an attacker who can generate errors could then schedule agent runs;
  invocation stays a human decision.
- **Sentry MCP wired with a read-only token** (issue/event read scopes; no write, no admin). The
  token lives in the operator's MCP config, never in the repo.

## Output contract — `.pipeline/incident-brief.md`

1. **Incident facts** (copied, attributed): issue id/link, first/last seen, frequency, release SHA
   (ties back to PR M's provenance), affected routes/users-count.
2. **Evidence**: the stack trace, breadcrumbs, and tags **quoted verbatim in fenced blocks** —
   provenance-marked as untrusted (see threat model).
3. **Reasoned hypothesis**: suspected module/path in the repo (it has `Read/Grep` over the code),
   confidence, and what evidence would confirm it.
4. **Suggested next step**: a draft feature-request paragraph the human may paste into a pipeline
   run. Explicitly labeled *suggestion* — the brief never claims authority.
5. **Provenance + injection report** (required section, mirrors design-spec): every
   instruction-shaped string found in error messages/breadcrumbs/user-agent/tags is quoted and
   marked **NOT ACTED ON**.

## Threat model (the reason this doc exists)

Production telemetry is **attacker-influenceable input**: anyone who can hit the app can put
arbitrary strings into error messages, URLs, user-agents, breadcrumbs — a prompt-injection carrier
pointed at whoever reads the incident, the same class as the design-bundle channel (DS) and treated
identically.

| STRIDE | Threat | Mechanism |
|---|---|---|
| Elevation | Injected breadcrumb tells the agent to "fix this by running…" | **No Bash/Edit tools** — nothing to elevate into; instructions can only end up quoted in the brief |
| Tampering | Brief nudges the human toward a malicious "fix" | Untrusted-data-not-instructions rule + the injection report make instruction-shaped content visible and inert; the fix still crosses plan-approval + diff-approval |
| Tampering | Agent forges an approval marker via `Write` | `guard-approval-markers.sh` + settings deny already cover markers for all agents; triage.md is added to both lists |
| Info disclosure | Brief republishes secrets/PII captured in telemetry | Redaction rule: the brief carries stack frames + error *types*; payload values are elided (`[REDACTED — see Sentry]`), pointing to Sentry instead of copying |
| Info disclosure | MCP token over-scoped | Read-only scopes, stated in the skill's setup checklist; token never in-repo |
| DoS | Unbounded event pulls burn tokens | One incident per invocation, `maxTurns` 15, evidence capped to the top N frames/breadcrumbs |
| Spoofing/Repudiation | Which incident, which run? | Brief header records issue id + pull timestamp + agent name; the run-log line covers the rest |

**Residual (stated):** the human reading the brief is the remaining injection target — the report
makes injected text *visible*, it cannot make a human skeptical. Accepted; identical to the DS
residual, and every downstream action still passes the existing human checkpoints.

## What it deliberately is NOT

- Not an auto-fixer, not an auto-deployer, not on-call. It re-enters the pipeline at planning like
  any feature request, with every gate intact.
- Not a Sentry dashboard replacement — one incident per run, on demand.
- Not the debugging agent: debugging fixes pre-merge failures inside a run; triage summarizes
  post-deploy incidents into a *new* run's input. They stay separate agents (different tools,
  different trust posture), though triage's brief will often become debugging's context later.

## Build slices

1. **O-T1** — `triage.md` + marker-guard/settings additions + a `triage-conventions` skill section
   (brief schema, redaction rule, MCP setup checklist).
2. **O-T2** — harness: a `triage` static check (agent parses; tool list contains no Bash/Edit;
   marker guard covers it) + a fixture brief validated for required sections.
3. **O-T3** — dogfood on a real Sentry project (ledgerly/red-team app) once PR O's wiring ships.
