# Pipeline revision — implementation plan

**Execution counterpart to [`max-pipeline-improvements.md`](max-pipeline-improvements.md).**
That document holds the *why* (audit, verdicts, tradeoffs); this one holds the *how / when / in
what order* (PRs, files, sequence, verification, status). The plan cites the advisory's section
numbers for rationale and never re-argues it; the advisory never lists files or PR ordering.

**Status legend:** ☐ not started · ◐ in progress · ☑ done · ⏸ deferred

> **DELIVERED (2026-06-30) — all three ship-PRs merged to `main`.** PR A → #2, PR B → #3,
> PR C → #4 (design PR 1–6 all shipped). Remaining: run `scripts/install-global.sh` to publish
> to `~/.claude/` (local activation), and the ⏸ deferred workstreams below. Follow-up polish
> (MCP-name caveats, sanity-role debugging scope, these status markers) landed in the PR D cleanup.

**Invariants preserved across every PR:** fresh-context agents, file-based `.pipeline/*` handoff,
deterministic fail-closed shell-hook gates, portable user-level install + per-project bootstrap,
and every human checkpoint.

**Deferred workstreams (documented in memory — NOT in this plan):**
- ⏸ **Front-end** (design-spec / design-review / a11y / Figma) → `memory/deferred-frontend-workstream.md`
- ⏸ **Production / post-merge debugger** (Sentry / observability / triage) → `memory/deferred-production-debugger-workstream.md`

**Open decision gating PR 2:** confirm **implementation = `sonnet/high`** (the limit-aware default; recommended).
**Settled (2026-06-29):** **security = `sonnet/high`** (not Opus) — the model only triages/verifies over a scoped diff while deterministic scanners do the detection, the stage re-fires every remediation cycle, and Sonnet's dedicated weekly pool spares the all-models cap. Opus stays confined to **planning** and **debugging** (low-volume, highest-reasoning).

---

## Cross-cutting rules (apply to every pipeline PR)

- **Mirror project-skill edits:** `global-project-skills/*` → `.agents/skills/*`. *(The `.codex/agents` Codex mirror was deleted 2026-06-29 — staying Anthropic-only; agent edits no longer need a Codex mirror.)*
- **Keep specs in sync:** `docs/agentic-pipeline-plan.md` + `docs/system_architecture.md`.
- **After agent `skills:` changes:** re-run `scripts/list-skills.sh --annotate`.
- **After any change:** re-run `scripts/install-global.sh` (publishes to `~/.claude/`); restart Claude Code/IDE to load.
- **Agents stay file-based (never packaged as a plugin):** plugin subagents silently ignore `hooks:` and `mcpServers:` (per the sub-agents docs), which would disable every Stop-hook telemetry/gate. Keep them as user/project agents in `~/.claude/agents/`.
- **Each PR is independently shippable and reversible**, ordered smallest-risk-first.

---

## PR 1 — Advisory doc corrections · doc-only, zero pipeline risk · ☑

**Goal:** make `max-pipeline-improvements.md` factually correct and forward-looking before any code change.

- **P0 corrections:** telemetry is *wired* on all 8 agents (notes auto-derived; combined coverage / tier-counts / strategy surfaced) — the gap is *reading* it, not wiring; among **hooks**, only `post-deploy-check.sh` is `[UNIMPLEMENTED]` (the other `[UNIMPLEMENTED]` item is `docs/pipeline-refinement-loops.md`'s planning-quality loop, which PR 3 marks implemented). Add the `log-run.sh` model-arg coupling. Fix exec-#1 "bug" → "inert" (effort on Haiku 4.5 is gated out by the harness; it also errors at the raw-API level — either way it buys nothing).
- **P1 limit-aware §3.1:** add the Max 20x cap-structure preamble + decision rule; revise the table (see PR 2); drop `xhigh` from any Sonnet stage; fix "top-of-range."
- **New recommendation sections** referencing the PRs below; **mark front-end and production-debugger DEFERRED** (point to the memory entries); have §4 phased-rollout point to this file.
- **Soften** the three unverified MCP names; reword "only cost grounds."

**Verification:** doc reads consistently; every claim traces to a verified finding. **Token impact:** none.

---

## PR 2 — Model/effort retune + telemetry arg fix · pure config · ☑

**Goal:** cheapest, fastest quality lift; lands the limit-aware allocation. Rationale: advisory §3.1.

**Frontmatter:**

| Agent | Change |
|---|---|
| planning | keep `opus`; effort `high` → `xhigh` |
| plan-audit | `haiku` → `sonnet`, effort `medium` (now real) |
| implementation | keep `sonnet`; effort `medium` → `high` |
| debugging | `sonnet` → `opus`, effort `high` → `xhigh` |
| security | `haiku` → `sonnet`, effort `medium` → `high` (Sonnet, not Opus: scanners are deterministic, the model only triages/verifies over a scoped diff, **the stage re-fires every remediation cycle** so cumulative volume is high, and Sonnet's dedicated weekly pool spares the all-models cap) |
| testing | `haiku` → `sonnet`, effort `medium` (now real) |
| documentation | keep `haiku/low`; remove inert `effort:` |
| deployment | `sonnet` → `haiku`; remove inert `effort:` |

**`global-hooks/log-run.sh`:** update the hardcoded arg-2 model literal in each Stop-hook wiring to match; **recommended:** auto-derive the model so it can never desync again. (Note: unlike `notes`, the model is not in any `.pipeline/*` artifact or the hook env — derive it by parsing the invoking agent's frontmatter, e.g. `grep '^model:' "$HOME/.claude/agents/$STAGE.md"`, since `$STAGE` matches the agent filename for all 8.)

**Verification:** run one feature; confirm `run-log.jsonl` records the correct model per stage.
**Token impact:** **~1.7× (range ~1.6–1.9×), unmeasured until real-run telemetry.** The advisory's "~2–2.5×" assumed implementation→Opus, which this plan rejects. The large/high-volume stages stay Sonnet: implementation (same price tier, only `medium→high` effort) and **security** (which re-fires every remediation cycle — keeping it off Opus matters precisely because it isn't one-shot). Opus is confined to **planning** and **debugging** — both **low-volume** stages, so their cap impact is small even at Opus rates, while their reasoning value is highest. On the subscription-limit lens: Opus draws only the shared all-models weekly cap (no fallback if a pinned-Opus stage hits the wall), so confining Opus to low-volume stages keeps that scarce cap from being the bottleneck; Sonnet stages additionally tap the separate, more generous Sonnet weekly pool. **Risk:** low (revert = git revert). **Depends on:** implementation-model decision.

---

## PR 3 — Plan-stage workflow: opus → plan-audit (sonnet) → opus revision + completeness check · ☑

**Goal:** give Opus's biased self-audit unbiased external feedback before the human, and make plan-audit a structural completeness check.

**Flow:** `planning (opus, self-audit) → plan-audit (sonnet) → [only on MATERIAL flags] planning (opus, ONE revision reading .pipeline/plan-audit.md) → human checkpoint`. Capped at **one** revision, no recursion; human checkpoint stays the hard stop.

**Files:**
- `global-agents/plan-audit.md` — add a **completeness check** (all applicable layer sections present, acceptance criteria traced, STRIDE mechanisms named, test-strategy declared, files-affected concrete; validation contracts once PR 4 lands). Classify each flag **material vs advisory**; write flags + `revision_recommended: true|false` to `.pipeline/plan-audit.md`.
- `global-agents/planning.md` — on re-invoke, read `.pipeline/plan-audit.md`, address each material flag before rewriting `plan.md`, note what changed.
- `global-skills/pipeline-orchestration/SKILL.md` — insert the conditional re-invoke (revise once iff `revision_recommended`).
- `docs/pipeline-refinement-loops.md` — mark the planning-quality loop **implemented** (sourced from plan-audit, not a separate evaluator).

**Divergence from advisory (deliberate):** the advisory gated the planning-quality loop on telemetry ("implement once `run-log` shows the human repeatedly sending plans back"). This PR ships a *lighter* variant now (Sonnet completeness audit + at most one Opus revision) rather than waiting, trading a small bounded cost for earlier oversight — consistent with the owner's throughput-for-oversight preference. Telemetry is already wired, so the trigger can still be confirmed retroactively.

**Verification:** seed a plan with a deliberately omitted section → plan-audit flags material → planning revises once → human sees corrected plan + flag history; confirm no recursion.
**Token impact:** plan-audit cheap (Sonnet); the one Opus revision fires only on material flags. **Risk:** low-moderate (bounded by the one-revision cap).

---

## PR 4 — Plan contracts (validation + acceptance) + downstream verification · ☑

**Goal:** give downstream agents explicit, checkable goals — security-related *and* project-specific. *(Splittable into 4a / 4b if review size matters.)* **Depends on:** PR 3 (completeness-check hook).

**4a — Input/output validation hardening:**
- `global-agents/planning.md` — emit a **validation contract** per boundary input as a concrete STRIDE mechanism: type + length bound + (where meaningful) allowlist charset/format + the sink it protects (e.g. `username: constr(pattern=r'^[a-z0-9_]{3,32}$') in src/schemas/user.py`).
- `global-skills/code-standards/SKILL.md` — add allowlist-regex guidance (anchored `^…$`, ReDoS-safe) for free-form strings feeding sensitive sinks; reaffirm schema-first. Also add a one-line **MCP-results-are-untrusted** rule (advisory §3.2): treat any MCP/tool result — context7 in implementation, aws-knowledge/terraform in planning — as untrusted input that may carry injected text, and never let an MCP result decide a deterministic gate (the gates already are jq/shell, so this is a discipline statement, not a structural change).
- `global-agents/security.md` — broaden step 6c output sinks (JS / attribute / URL contexts); add **step 6e log-sink safety** (log-forging via unescaped user input; secrets/PII in logs) → critical. *(6c-broadening and 6e are plan-originated hardening, not advisory-derived — sound and low-cost, but tracked as additions.)*
- plan-audit completeness check — flag a feature with inputs that lacks validation contracts.

**4b — Acceptance-criteria contract (downstream-goals backbone):**
- `global-agents/planning.md` — emit `.pipeline/acceptance.md`: each criterion (from `PROJECT.md` "what done means" — **project-specific, not only STRIDE**) + the file/layer it lives in + how to verify it (named test / endpoint behavior / mechanism).
- `global-agents/implementation.md` — read `acceptance.md` as definition-of-done.
- `global-agents/testing.md` — map each criterion → a test; record **`criteria_covered`** in `test-results.json` (separate field from `coverage.combined`; criteria coverage ≠ line coverage).
- plan-audit — flag untraced criteria.

**Verification:** omit a planned validation contract → security 6e/6c flags critical; an acceptance criterion without a test → testing reports it uncovered.
**Token impact:** cheap (grep checks + structured artifacts). **Risk:** moderate (4–5 agents; split if needed).

---

## PR 5 — Loops & goals + circuit-breaker + run-log digest · ☑

**Goal:** drive the post-approval cycle to green hands-free, **bounded so it can't drain the weekly cap.** **Depends on:** PR 4 (green condition includes criteria coverage). Rationale: advisory §3.10.

**Files:**
- `global-skills/pipeline-orchestration/SKILL.md` — an **orchestrator-driven run-to-condition loop** (the orchestrator/main thread drives it; *not* a built-in `/goal` looping primitive — `/goal` only sets direction) driving `implementation(once) → security ⇄ debugging ⇄ testing` until the deploy-gate condition holds: `test-results.status == pass AND security-status.status == clean AND criteria_covered complete`. **Deterministic exit only (jq on status files — never LLM-judged).** Exclude planning / plan-audit / documentation / deployment from the loop; keep implementation single-shot.
- **`global-hooks/deployment-gate.sh`** — add the `criteria_covered complete` check so the **loop-exit condition is identical to the real deploy gate** (otherwise the loop can exit green on a condition the gate does not enforce, and they drift). `criteria_covered` is introduced in PR 4.
- **New `global-hooks/loop-guard.sh`** — the **circuit-breaker**: abort + escalate to human at max full cycles / wall-clock / retries. Its counters bound the **whole feature** and must be **independent of the per-cycle counters `record-clean.sh` resets** — otherwise a transiently-clean cycle resets the budget and grants fresh retries. Cap-out = terminal human-stop; human checkpoints are hard stops the loop cannot auto-clear.
- **New `scripts/run-log-digest.sh`** — zero-LLM summary of `run-log.jsonl`: per-stage model/status/retries, `coverage.combined` trend, `tests_by_type`, `test_strategy`, and an **inverted-pyramid flag** (large `combined − unit` gap).

**Verification:** force a persistent test failure → loop retries to the cap, then **escalates to a human**, never loops forever; documentation/deployment never run mid-loop.
**Token impact:** bounded — implementation runs once; only small stages repeat under the cap. **Risk:** moderate — **the circuit-breaker ships *with* the loop in this PR, never before it.**

---

## PR 6 — Debugging agent upgrades (pre-merge only) · ☑

**Goal:** make the pre-merge debugger reliable. `opus/xhigh` lands in PR 2; this is behavior. Rationale: advisory §3.5.

**Prerequisite — tool gap (must resolve first):** `debugging` currently has `tools: Read, Edit, Bash, Grep` — **no `Write`**. `Edit` cannot create new files, so authoring a *new* regression test or a *new* `.pipeline/debug-notes.md` is infeasible as-is. Pick one:
- **(a, recommended)** add `Write` to `debugging.md` `tools:` and the matching `settings.json` allow-list — keeps the reproduction test with the agent that found the bug; **or**
- **(b)** debugging writes only the *failing reproduction* (the testing agent, which already re-runs after remediation, owns suite validation and authors the kept regression test); `debug-notes.md` is then produced via an `Edit`-able pre-seeded file or a `Bash` heredoc.

**Ownership note:** debugging authoring a test overlaps the testing agent's ownership of the suite. Scope it: debugging proves the fix with a failing→passing reproduction; **testing owns suite validation on the post-remediation re-run** (already in the orchestration debug-loop).

**Files:** `global-agents/debugging.md` + `global-skills/debugging-escalation-protocol/SKILL.md`
- **Reproduce-first:** deterministically reproduce the failure (run failing test/smoke, capture exact error + stack) before fixing.
- **Regression test** that fails before / passes after the fix, following the plan's `test_strategy` shape (subject to the tool-gap resolution above).
- **Flaky discrimination:** re-run the failing test N times (5–10) before declaring fixed.
- **Remove temporary debug probes** before finishing.
- **Hypothesis log** → `.pipeline/debug-notes.md` (root cause + evidence + what was tried).
- **`git bisect` / diff localization** for regressions.

**Verification:** inject a flaky test → agent re-runs N times, doesn't declare "fixed" on one clean pass; probes removed; `debug-notes.md` written.
**Token impact:** on-failure only → small absolute cost. **Risk:** low.

---

## Roadmap — robustness items (originally not in the 6 PRs; app/infra-heavy or hard) · ☑ shipped 2026-06-30 (PR E)

**Shipped as PR E (2026-06-30):** all seven items below, wired as **conditional, trigger-gated
conventions that no-op unless a feature warrants them** — not mandatory gates on every feature.
Enforcement adds **no new gate hook**: deterministic security findings (migration down-path,
Trivy critical CVE, secret exposure) fold into the security gate's `critical_count`, and any
project-specific guarantee that should block (a perf budget, an idempotency contract) is declared
by planning as an **acceptance criterion** and rides the existing `criteria_covered` deploy gate.

| Item | Home (as shipped) | Status |
|---|---|---|
| Migration reversibility / zero-downtime test | `testing.md` step 5c (up→down→up on scratch DB) + `test-conventions` | ☑ |
| Property-based / fuzz testing | `testing.md` step 5d + `test-conventions` (Hypothesis / fast-check) | ☑ |
| Load / perf testing + budgets | `planning.md` (budget as acceptance criterion) + `testing.md` step 5f (k6 / Locust) | ☑ |
| Concurrency / idempotency testing | `testing.md` step 5e (parallel-request harness + idempotency-key assertions) | ☑ |
| Runtime secrets management | new on-demand `secrets-management` skill (Secrets Manager / SSM facade) | ☑ |
| Container image scanning (Trivy) | new `trivy-scan.sh` + `security.md` step 4b; closes the `containerization-conventions` wiring gap | ☑ |
| IaC scale primitives (auto-scale / multi-AZ / health-check) | `iac-conventions` + `baseline.md` production-scale defaults | ☑ |

(Production observability / Sentry lives in the deferred production-debugger workstream — still out of scope.)

---

## PR summary

| PR | Theme | Risk | Depends on | Status |
|---|---|---|---|---|
| 1 | Advisory doc corrections | none | — | ☑ |
| 2 | Model retune + telemetry arg | low | impl-model decision | ☑ |
| 3 | Plan-stage workflow (opus → audit → opus) | low-mod | — | ☑ |
| 4 | Plan contracts (validation + acceptance) | mod | 3 | ☑ |
| 5 | Loops + circuit-breaker + digest | mod | 4 | ☑ |
| 6 | Debugging upgrades | low | 2 | ☑ |

**Token efficiency:** the retune dominates but lands **~1.7×** for this config (range ~1.6–1.9×, unmeasured until telemetry). Implementation and security — the high-volume / re-firing stages — stay Sonnet; **Opus is confined to planning + debugging, both low-volume**, so the spend lands where it is both cheap on the cap and decisive on quality (the advisory's "~2–2.5×" assumed implementation→Opus, which this plan rejects). On the limit lens, Opus draws only the shared all-models weekly cap with no fallback, so keeping it off the high-volume stages is what prevents that cap from gating a feature mid-run. Loops add *bounded* overhead on small stages only; the circuit-breaker (PR 5) is the non-negotiable cap backstop. The single biggest efficiency risk is an unbounded loop — which is why PR 5 ships the breaker with the loop.

---

## Execution plan — ship as 3 PRs (grouped by risk class)

The six PRs above are the *design units*. For delivery they collapse into **three sequential PRs**, grouped so the one high-variance change (the autonomous loop) ships last, isolated, with its breaker. Build order is strictly **PR A → PR B → PR C**; each depends on the prior.

| Ship PR | Bundles | Theme | Risk | Depends on | Status |
|---|---|---|---|---|---|
| **A** | PR 1 + PR 2 | Instrument + retune (doc + pure config) | ~none (instant `git revert`) | model decisions (settled) | ☑ |
| **B** | PR 3 + PR 4 + PR 6 | Smarter agents + contracts (deterministic, checkpoint-protected behavior) | moderate | A | ☑ |
| **C** | PR 5 | Autonomous loop + circuit-breaker + digest | high (tail-risk) | B | ☑ |

### PR A — Instrument + retune  (= design PR 1 + PR 2) · ☑
- **Why bundled:** doc-only + pure config, no behavior change. PR 1 corrects the advisory that PR 2 implements — the config-and-its-rationale pair.
- **Build order inside:** PR 1 (advisory doc) → PR 2 (frontmatter retune + `log-run.sh` arg fix).
- **Gate before merge:** implementation = `sonnet/high` and security = `sonnet/high` both settled (✓). Opus only on planning + debugging.
- **Verify:** run one feature; `run-log.jsonl` records the correct model per stage; revert is a clean `git revert`.

### PR B — Smarter agents + contracts  (= design PR 3 + PR 4 + PR 6) · ☑
- **Why bundled:** all *deterministic, human-checkpoint-protected* behavior/contract work, **no autonomous spend**. PR 3↔4 are coupled (4 plugs into 3's completeness hook; 3 forward-references 4). PR 6 is independent low-risk behavior that only soft-depends on PR A's `opus/xhigh`.
- **Build order inside (dependency-ordered, verify each before the next):** PR 3 (plan-stage workflow + completeness hook) → PR 4 (validation + acceptance contracts that plug into it) → PR 6 (debugging upgrades).
- **Gate before merge:** **resolve PR 6's `Write` tool-gap first** (option a or b). This is the heaviest review surface — if it feels too big, peel out PR 4b (acceptance) using PR 4's built-in split.
- **Verify:** each sub-PR's own verification step (omitted-section plan → revision once; missing validation contract → security flags critical; untraced criterion → testing reports uncovered; flaky test → debugging re-runs N times).

### PR C — Autonomous loop + breaker  (= design PR 5) · ☑
- **Why alone + last:** the single high-variance change — kept isolated so a looping/spend bug is bisectable, and **the circuit-breaker ships in the same PR as the loop, never before it.**
- **Build order inside:** `loop-guard.sh` (breaker) and the loop logic land together; `deployment-gate.sh` gains the `criteria_covered` check (loop-exit ≡ deploy gate); `run-log-digest.sh` is additive.
- **Gate before merge:** PR B merged (loop's green condition needs `criteria_covered` from PR 4); breaker counters independent of `record-clean.sh` resets.
- **Verify:** force a persistent test failure → loop retries to the cap, then escalates to a human, never loops forever; documentation/deployment never run mid-loop.

> **What this trades:** finer bisectability *within* PR B (a contract bug vs a workflow bug share a commit). **What it keeps:** the only invariant that's dangerous to lose — the loop isolated in PR C with its breaker. The original 6-PR detail above remains the authoritative spec for *what* each change is; this section is the *delivery sequence*.
