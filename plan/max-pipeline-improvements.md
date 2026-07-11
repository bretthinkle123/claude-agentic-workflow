# Max 20x pipeline upgrade — advisory

**Status: advisory only.** This document changes no pipeline file. It audits the live
pipeline (the `global-*` source dirs, the hooks, the scaffold scripts, and the four
companion docs) and recommends how to spend the runway now that the budget moved from
Pro ($20) to **Max 20x ($200)**. Token efficiency still matters, but it has moved from a
*constraint* to a *tuning knob* — the framing throughout is "how best to spend the
runway," not "can I afford it."

**Model facts** were re-verified against the `claude-api` skill, not memory. The pipeline
agent aliases resolve to: `opus` → `claude-opus-4-8` ($5 / $25 per 1M in/out),
`sonnet` → `claude-sonnet-4-6` ($3 / $15), `haiku` → `claude-haiku-4-5` ($1 / $5).
`claude-fable-5` is intentionally **not** part of this pipeline — it isn't available to you for
development, and nothing here recommends it. **Subagent frontmatter capabilities were verified
against the current official Claude Code docs** (`code.claude.com/docs/en/sub-agents`): `model`,
`effort`, `maxTurns`, `hooks`, `skills`, and `mcpServers` are all real, supported per-agent
fields, so every recommendation below is actionable rather than aspirational. The `effort` field
accepts `low | medium | high | xhigh | max`, and the docs note **"available levels depend on the
model"** — so **`xhigh` is a valid setting (the documented coding/agentic sweet spot — between `high` and `max`, not the ceiling — and
the Claude Code default)**, while **Haiku 4.5 exposes no effort levels at all**, making an
`effort:` line on a Haiku agent inert (flagged below).

**Invariants honored:** every existing human checkpoint is kept (and several *additional*
ones are proposed, since you trade throughput for oversight and learning); file-based
`.pipeline/*` handoff, fresh-context blank agents, deterministic fail-closed shell-hook
gates, and the portable user-level install + per-project bootstrap all stay. Where the Max
runway genuinely reverses a decision that was made under token pressure, that is called out
explicitly.

---

> **⚑ SETTLED DECISIONS (2026-06-29) — these supersede the recommendations below wherever they differ.**
> The execution plan ([`pipeline-revision-plan.md`](pipeline-revision-plan.md)) is now authoritative for *what was decided*; this advisory remains the *why*. Net deltas from the recommendations in this document:
> - **Telemetry is WIRED, not `[UNIMPLEMENTED]`.** `log-run.sh` runs as a `Stop` hook on all 9 agents (the 8 core stages + the conditional design-spec stage; status / notes / coverage / tier-counts auto-derived; the model now auto-derives from each agent's frontmatter so it can't desync). The remaining gap is *reading* the log (a digest), not wiring it. Treat every "`run-log.jsonl` is `[UNIMPLEMENTED]`" line below as stale.
> - **Implementation stays `sonnet/high`** (not `opus/xhigh`). **Security was `sonnet/high`, now OVERRIDDEN to `opus/high`** after a STRIDE delta / attack-surface reconciliation step (6f) added independent reasoning to the stage — Opus for stronger bug-finding, knowingly accepting the higher all-models-cap draw (security is still the highest-volume re-firing stage). Opus now covers **planning, debugging, and security**; Sonnet keeps plan-audit, implementation, testing. The 1.7× retune estimate below predates this override and now runs slightly higher.
> - **`effort` on Haiku is inert** (harness-gated; errors at the raw-API level) — removed from the Haiku agents, not "a bug."
> - **`xhigh` sits between `high` and `max`** (not "top-of-range"; `max` is higher) and is **not applied to any Sonnet stage**.
> - **The `.codex` Codex mirror was deleted** — Anthropic-only environment; agent edits are single-source in `global-agents/`.
> - **Front-end** (design / a11y / Figma) and the **production / post-merge debugger** (Sentry / observability) are **DEFERRED** to dedicated later workstreams (`memory/deferred-frontend-workstream.md`, `memory/deferred-production-debugger-workstream.md`) — not in the current revision.

---

## Table of contents

1. [Executive summary](#1-executive-summary)
2. [Current-state assessment](#2-current-state-assessment)
3. [Recommendations by dimension](#3-recommendations-by-dimension)
   - [3.1 Per-agent model & effort](#31-per-agent-model--effort)
   - [3.2 MCP servers](#32-mcp-servers)
   - [3.3 Skills](#33-skills)
   - [3.4 The mobile platform gap (first-class)](#34-the-mobile-platform-gap-first-class)
   - [3.5 Pipeline stages / agents](#35-pipeline-stages--agents)
   - [3.6 Hooks](#36-hooks)
   - [3.7 Front-end quality](#37-front-end-quality-specifically)
   - [3.8 Backend scalability](#38-backend-scalability-specifically)
   - [3.9 What you're missing or forgetting](#39-what-youre-missing-or-forgetting)
4. [Prioritized, phased rollout](#4-prioritized-phased-rollout)
5. [Open decisions for you](#5-open-decisions-for-you)
6. [Things you may be forgetting (candid)](#6-things-you-may-be-forgetting-candid)

---

## 1. Executive summary

The five highest-leverage changes, in order:

1. **Raise the brains on the reasoning stages, and remove the inert Haiku-effort lines.**
   Implementation runs on **Sonnet/medium** while security and testing run on **Haiku**
   today — the stages that most determine whether output is "production-grade" are the ones
   on the weaker models. Raise effort where it is real and confine Opus to the low-volume,
   highest-reasoning stages: **planning → `opus` / `xhigh`** and **debugging → `opus` /
   `xhigh`**, while **implementation** and **security** stay **`sonnet`** with raised effort
   (`high`) — see the settled decisions above for why the high-volume / re-firing stages stay
   off Opus. Separately, four agents (plan-audit, security, testing, documentation) set
   `effort:` on **Haiku, which exposes no effort levels** — so those lines are **inert** (not a
   bug: harness-gated, and they error at the raw-API level) and buy nothing today; remove them.
   This is pure frontmatter; it is the cheapest, fastest quality win and should land first.

2. **Pick the mobile path now, and make it React Native + Expo (managed / EAS).**
   The stores need native or cross-platform mobile; the pipeline produces Python-backend +
   **JS web** front-ends. Cross-platform on **React Native + Expo** is the right call for
   *your* situation specifically — you develop on **Windows** (native iOS cannot be built or
   signed without macOS; **EAS Build compiles iOS in Expo's cloud**, so the whole iOS path
   works from Windows), it **reuses your JavaScript**, and the **AI/LLM tooling ships
   first-class JS/TS SDKs** (the Anthropic SDK and friends). This is the single largest
   capability gap and
   the rest of the mobile cascade (build hooks, tests, signing, store compliance) hangs off
   this one decision.

3. **Add a front-end/design quality layer — the pipeline has none.** There is no
   design-system skill, no component conventions, no visual-regression testing, and no
   accessibility budget anywhere in the repo; `code-standards` is backend-leaning. For
   "high-quality UI you can publish," add a `design-system-conventions` skill, wire the
   **official Figma Dev Mode MCP** (design-to-code) opt-in, and add a **design-review**
   step + **accessibility** gate. This is what separates "it works" from "it looks
   professional."

4. **Add an app-store pre-submission compliance gate (fail-closed, deterministic).** Both
   stores reject on privacy manifests, data-safety / privacy-nutrition labels, required-reason
   API declarations, and (Apple) in-app account deletion. A new `store-compliance-gate.sh`
   in the existing fail-closed pattern is the mobile analog of `deployment-gate.sh` and is a
   natural, cheap addition.

5. **Wire the telemetry you already designed, so you can prove the upgrades paid off.**
   `run-log.jsonl` / `log-run.sh` are **now wired** (Stop hook on all 8 agents; model auto-derived) — the gap is *reading* the log, not wiring. With Max you can afford to *run and
   measure*; without the log you're upgrading models blind. Wiring this first turns every
   later recommendation into a measurable A/B instead of a guess. It also revives the
   **planning quality loop** (Haiku-evaluator → Opus-revision), whose only documented
   objection was cost on a $20 plan — an objection the Max runway removes.

A theme across all five: the pipeline made a series of *correct* austerity decisions under a
$20 budget. Max doesn't make those decisions wrong retroactively — it changes which ones are
still worth keeping. The cuts driven by **architecture** (Sentry out of the *pre-merge* loop;
GitHub MCP replaced by `gh`) stay cut. The cuts driven by **token price** (cheap models on
reasoning stages; Playwright/Figma MCP; the planning loop) are the ones to revisit.

---

## 2. Current-state assessment

### What the pipeline does well (keep all of it)

- **The fail-closed gate design is genuinely good.** `deployment-gate.sh` has no
  state-file guard on purpose, so outside a bootstrapped project its interlock files are
  absent and it fails *closed*. `jq`-presence is checked before every status read. The
  currency check (`reviewed_change_hash` recomputed by the same `compute-change-hash.sh`
  the documentation agent used) means the bytes committed are exactly the bytes reviewed.
  This is the structural backbone and nothing here should change — every new gate proposed
  below copies this pattern.
- **The fresh-context, file-handoff, blank-subagent architecture** keeps each stage's
  context lean and auditable. Worth preserving exactly.
- **Portable install + per-project bootstrap** (`install-global.sh` → `~/.claude/`,
  `bootstrap-project.sh` per repo) with a collision guard and an install manifest is clean
  and idempotent. Mobile additions slot into the same publish/bootstrap flow.
- **MCP discipline is exemplary** — project-scoped `.mcp.json`, nothing default-on,
  per-agent `tools:` allow-lists that cost zero schema tokens until a project opts in. This
  is *exactly* the mechanism that makes the heavier mobile/Figma MCP servers safe to add:
  they cost nothing on a backend-only project.
- **The plan is a learning document by design** (what/why/how inline, STRIDE with concrete
  mechanisms the security agent later verifies). The plan-audit agent (anti-slopsquatting +
  version cooldown) is a strong, cheap addition. Keep these.
- **Deployment scope is correctly narrow** (commit + push + PR; CI handles the rest).

### The token-efficiency tradeoffs — and which ones Max reverses

| Tradeoff made under $20 | Why it was right then | Under Max 20x |
|---|---|---|
| Implementation on **Sonnet/medium**, security & testing & docs on **Haiku** | Cheapest models that "work"; Opus reserved for planning only | **Reverse for implementation, debugging, security, testing.** These are the production-quality stages. (§3.1) |
| `effort:` set on Haiku agents | Looked like depth control | **Inert on Haiku** (no effort levels exposed) — neither budget-related nor working. Fix regardless of budget. (§3.1) |
| **Playwright MCP cut** (a11y snapshots 2k–10k tok/step) | A real budget hazard on standing test authoring | **Partially reverse:** keep it out of *standing test authoring* (a deterministic runner is better at any budget), but a *verification/debug* agent driving a simulator is now affordable. (§3.2, §3.4) |
| **Figma MCP not considered** | Net-new capability, not a token *saving* | **Reverse:** for UI-heavy / mobile work the design-to-code capability now justifies the schema cost. (§3.2, §3.7) |
| **Sentry MCP cut** | Out of the *pre-merge* loop (no prod issues in scope) | **Stays cut for an architectural reason, not budget** — but wire the Sentry *SDK in code* (crash/error capture) and optionally give the *debugging* agent Sentry MCP when triaging prod. (§3.8, §3.9) |
| **Firebase / GitHub MCP cut** | `gh` CLI replaces GitHub; `auth-patterns` skill covers Firebase code | **Mostly stay cut** — these were value/architecture calls, not pure budget. Marginal to revisit. (§3.2) |
| **Planning quality loop UNIMPLEMENTED** | "On $20, a revision loop ≈ a fresh planning pass" (its own doc) | **Reverse the cost objection:** on Max the loop is negligible. PR 3 implements a lighter plan-audit-sourced variant now. (§3.5) |
| **`run-log.jsonl` / telemetry — NOW WIRED (2026-06-29)** | Not needed for a first run | **Done** — Stop hook on all 8 agents; remaining gap is a digest that reads it. (§3.9) |

### The capability gaps (independent of budget)

These are *missing capabilities*, not austerity choices — Max funds building them but money
was never the blocker:

- **No mobile anything.** Stack is Python + JS-web + AWS. No native/cross-platform target,
  no `xcodebuild`/`gradle`, no XCTest/Espresso/Maestro, no TestFlight/Play, no signing, no
  store-compliance gate. (The deployment-*targets* doc sketches Fastlane + Gradle Play
  Publisher *post-merge*, but nothing mobile lives **inside** the pipeline.) — §3.4
- **No front-end quality layer.** No design system, component conventions, visual
  regression, or accessibility budget. — §3.7
- **No load/perf testing, no error tracking wired, no feature flags, no SLO/alerting
  automation.** `ddia-patterns` and `logging-conventions` are good *decision guides* but
  stop at the plan; nothing exercises scale. — §3.8, §3.9

---

## 3. Recommendations by dimension

### 3.1 Per-agent model & effort

**Current wiring (verified in `global-agents/*.md` frontmatter):**

| Agent | Model | Effort | maxTurns | Note |
|---|---|---|---|---|
| planning | `opus` | high | 20 | Reasoning-heavy; correctly on Opus |
| plan-audit | `haiku` | medium | 15 | Deterministic registry checks; **effort no-op on Haiku** |
| implementation | `sonnet` | medium | 25 | **The production-quality stage, on the mid model** |
| debugging | `sonnet` | high | 15 | Root-cause analysis; fires only on failure |
| security | `haiku` | medium | 20 | STRIDE verify + manual IDOR/RLS/validation, **on the weakest model + effort no-op** |
| testing | `haiku` | medium | 10 | Test *authoring* quality, **on the weakest model + effort no-op** |
| documentation | `haiku` | low | 10 | Low-reasoning; correctly cheap |
| deployment | `sonnet` | low | 8 | Git/gh mechanics; could even be Haiku |

**The inert-effort setting on Haiku (fix regardless of budget).** The official Claude Code
subagent docs define `effort:` with values `low | medium | high | xhigh | max` and note
**"available levels depend on the model."** Haiku 4.5 exposes none (the Claude API likewise
rejects effort on Haiku 4.5), so the `effort:` line on **plan-audit, security, testing,
documentation** has no effect — it isn't buying the depth it implies. **Implication:** effort
is a real lever only on a stage running **Sonnet 4.6 or the Opus 4.x family**. That is an
independent reason — beyond raw capability — to move the *reasoning-heavy* Haiku stages up.

**Recommended wiring under Max** *(original analysis — **partly superseded by the SETTLED DECISIONS banner at the top of this doc**: implementation ships `sonnet/high`; **security ships `opus/high`** (overridden from sonnet — 6f); **deployment ships `sonnet`** (moved back from haiku for its pre-commit inspection); net retune now runs somewhat above the ≈1.7× estimated here. The table is kept as the capability-first reasoning; the settled + later-overridden allocation wins wherever they differ):*

| Agent | → Model / Effort | Why | Stage-cost multiplier* | Impl. effort | Risk |
|---|---|---|---|---|---|
| planning | `opus` / **xhigh** | Highest-leverage stage; `xhigh` is the coding/agentic sweet spot and gives planning room to think through architecture + STRIDE | ~1.2–1.5× (same price tier, more output) | trivial (frontmatter) | Low — more thorough plans, slightly longer |
| plan-audit | `haiku` (drop `effort:`) **or** `sonnet`/low | Registry/version checks are deterministic; keep cheap. If ambiguity-detection quality matters, Sonnet/low. Either way remove the no-op effort line | ~1× (or 3× if → Sonnet) | trivial | Low |
| **implementation** | **`opus` / high→xhigh** | The single biggest production-quality lever. Opus 4.8 is materially better at first-shot correct implementations and fewer wrong-API cycles | **~2–3×** (price 1.67× + xhigh volume) | trivial | Low capability risk; this is *the* place to spend runway |
| **debugging** | **`opus` / xhigh** | Opus 4.8 is notably stronger at real bug-finding and at correctly identifying *intermittent* flakes instead of "fixed after one clean run." Fires only on failure, so absolute cost is small | ~1.7× of a stage that runs rarely | trivial | Low |
| **security** | **`opus` / high** (or `sonnet`/high as a middle option) | The scanners (Semgrep/OSV/Checkov) are model-independent, but **triage, remediation, STRIDE-mechanism verification, and the manual IDOR/RLS/validation invariants are reasoning** — currently on the weakest model with an inert effort setting. For a production app shipped to stores, this is a security-critical upgrade | ~5× of a modest-volume stage (Haiku→Opus price) | trivial | Low. Opus 4.8 is the right ceiling; you pay Opus rates only on the triage/remediation reasoning, not the deterministic scans |
| **testing** | **`sonnet` / medium** (or `opus` for critical paths) | Haiku writes shallow tests; Sonnet derives meaningful edge cases, integration boundaries, and E2E flows. Effort *works* on Sonnet, so `medium` becomes real | ~3× of a short stage | trivial | Low — better coverage, slightly more test code to review |
| documentation | **keep `haiku` / low** (remove no-op effort or accept it's stripped) | Low-reasoning; the prompt's "keep cheap on docs/deploy" guidance is correct | 1× | trivial | Low |
| deployment | **keep `sonnet` / low** (Haiku is defensible) | Git/gh mechanics + commit-message synthesis + branch-slug logic. Cheap either way | 1× (or 0.5× → Haiku) | trivial | Low |

\* *Stage-cost multiplier is relative to that stage's current cost. Absolute token volume
differs wildly by stage: planning and implementation are the large stages; security,
testing, docs, deployment are small. A 5× on the short security stage is cheap in absolute
terms, and on Max 20x the headroom is large. Net effect of the full table on a typical
feature run is roughly **2–2.5× total tokens** — squarely affordable on Max, and the spend
lands where production quality is actually decided.*

**Two additional notes:**

- **`xhigh` is valid here, and omitting `effort:` inherits the session level.** Per the
  subagent docs the `effort:` field "Overrides the session effort level. Default: inherits
  from session" — so the explicit per-agent values above are about *determinism*: pinning each
  stage's depth regardless of what the interactive session's effort happens to be set to.
- **Measure before standardizing.** Wire `run-log.jsonl` (§3.9) *first*, then make these
  changes, then read the per-stage token/quality deltas. The point of Max is that you can
  afford to run the experiment instead of theorizing it.

---

### 3.2 MCP servers

The project-scoped `.mcp.json` model is the right container for everything here: a server
costs **zero schema tokens** until a project's `.mcp.json` opts in and an agent's `tools:`
references it. That makes even the heavy servers safe to add — a backend-only API project
loads none of them.

**Re-verdict on the previously-cut servers, separating *budget* cuts from *architecture* cuts:**

| Server | Original reason to cut | Under Max | Verdict |
|---|---|---|---|
| **GitHub MCP** | `gh` CLI already opens PRs; no schema cost | Unchanged — architecture, not budget | **Stay cut.** Revisit only if you want structured CI-status objects in the deployment agent |
| **Sentry MCP** | Pipeline fixes *local* failures pre-merge; no prod issues in the loop | Unchanged — architecture, not budget | **Stay cut as a pipeline-loop server.** Instead, wire the Sentry **SDK in code** (§3.8) and optionally hand the *debugging* agent Sentry MCP when you're triaging a prod incident outside the standard loop |
| **Firebase MCP** | 30+ tool schemas; `auth-patterns` covers the code | Budget objection weakens; capability objection (skill covers it) stands | **Marginal.** Opt-in only on a project where you're interactively managing Firebase resources, scoped to the auth toolset |
| **Playwright MCP** | a11y snapshots 2k–10k tok/step — budget hazard for standing test authoring | The *standing-authoring* objection holds at any budget; the *verification/debug* use is now affordable | **Partially reverse** — see "new servers" below; same logic applies to mobile-control servers |

**New servers to add (all project-scoped, opt-in, for UI / mobile projects only):**

| Server | Wire to (agent `tools:`) | What it buys | Token profile | Which projects earn it |
|---|---|---|---|---|
| **Figma Dev Mode MCP** (official, `figma`) | a new **design-review** agent (read) + **implementation** (mobile/web UI mode) | Streams component names, layout constraints, spacing/type tokens, the layer tree — *design-informed* code generation instead of eyeballing a screenshot. Config 2026 added Motion/animation export | Moderate — structured metadata, not raw images. Far cheaper than a screenshot loop | Any UI-bearing project where you maintain Figma files |
| **Maestro MCP** (`maestro`) | **debugging** / a new **ui-verify** agent (opt-in) | Cross-platform mobile E2E: the *same* YAML flow drives iOS simulator **and** Android emulator. **The test *run* is deterministic in the runner — zero model cost** | Heavy *only when live-driving* (screenshots per step). Reserve MCP for debugging one failing flow; author flows from code | Mobile projects |
| **iOS Simulator MCP** (`ios-simulator-mcp`, joshuayoes) — *or* **`claude-in-mobile`** (ADB + simctl + Android) | **ui-verify** / **debugging** (opt-in, **macOS-only** for the iOS half) | Tap / type / swipe / screenshot / record / accessibility-inspect the simulator for live UI verification and a11y checks | Heavy (screenshots / a11y snapshots per step) — **same budget hazard as Playwright**; keep it to verification/debug, never standing authoring | Mobile projects, and (iOS) only on a Mac/cloud-Mac |
| **context7** (already wired to implementation) | — | Already correct; even more valuable now — RN/Expo/native APIs move fast and context7 kills wrong-API write/fail/rewrite cycles | Low (targeted snippets) | Already opt-in |

> **Name-verification caveat (unverified server names).** Of the servers above, only
> **Figma Dev Mode MCP** (first-party) and **context7** (already wired) are confirmed. The
> mobile-control names — **Maestro MCP**, **`ios-simulator-mcp`** (joshuayoes), and
> **`claude-in-mobile`** — are cited from memory as *candidates*, not verified picks: confirm
> the exact package/server still exists, is the one you mean, and is maintained **before
> wiring it** (the same anti-slopsquatting discipline `plan-audit` applies to dependencies).
> If a name doesn't resolve, the capability (mobile E2E / simulator control) is the
> requirement — find the current server that provides it rather than trusting the name here.

**Discipline to preserve:** pin versions/digests in `.mcp.json`; keep the heavy
simulator/Maestro/Playwright servers **off** standing test authoring (the deterministic
runner is better at any budget — this is the existing pipeline reasoning and it still
holds); treat all MCP *results* as untrusted (a fetched Figma node or a screenshot can
carry injected text) and never let an MCP result decide a deterministic gate. The
`templates/mcp.json` skeleton should grow a commented "mobile/UI block" (figma + maestro +
ios-simulator) that a mobile project uncomments.

> *Tighter option (verified in the subagent docs):* the heaviest servers can instead be
> declared **inline in the verification subagent's frontmatter** (`mcpServers:`), which the
> docs note "keep[s] an MCP server out of the main conversation entirely and avoid[s] its tool
> descriptions consuming context there." That's even more token-disciplined than project
> `.mcp.json`, at the cost of the uniform project-scoped opt-in model the pipeline currently
> uses. Either works; pick one and be consistent.

---

### 3.3 Skills

**Deepen existing skills now that the line-count budget is looser:**

| Skill | Deepen with | Used by |
|---|---|---|
| `code-standards` | A front-end section: React/React-Native component structure, hooks rules, state-management conventions (server-state vs client-state), and the "no business logic in components" rule. Today it's backend-leaning | implementation |
| `auth-patterns` | A **mobile addendum**: on-device token storage via **`expo-secure-store`** (Keychain/Keystore) — never `AsyncStorage` for tokens; biometric unlock; the OAuth **redirect / deep-link** round-trip; Duo MFA on mobile (push or deep-link). The `mfa_verified` claim contract is unchanged | planning, implementation |
| `logging-conventions` | A **client/mobile telemetry** section: Sentry breadcrumbs + crash capture, no-PII rules on device, offline event buffering. Backend section is already strong | planning, implementation |
| `ddia-patterns` | A "scale-out playbook" appendix: read replicas, cache tiers, queue-backed writes, idempotency keys — concrete patterns to reach for when the plan crosses a scale threshold, not just the conceptual trade-offs | planning |
| `iac-conventions` | Auto-scaling / multi-AZ / health-check / observability-infra baseline (today it's the security baseline + state/OIDC). Production-scale defaults | planning, implementation, security |

**New skills required (priority-ordered; the mobile ones are the gap):**

| New skill | Covers | Used by | Priority |
|---|---|---|---|
| `mobile-stack-conventions` | RN + Expo + TypeScript project layout, Expo Router navigation, state (Zustand + React Query), env/config, EAS project config. The "ONE documented mobile path," analogous to the existing AWS/Python/JS default | planning, implementation | **P1** |
| `mobile-release-conventions` | EAS Build / Submit, code signing & credentials (`eas credentials`), entitlements/capabilities, versioning + build numbers, TestFlight + Play **internal** tracks, OTA (EAS Update) rules and the "you cannot OTA a native change" boundary | deployment, compliance | **P2** |
| `app-store-compliance` | Privacy manifest (`PrivacyInfo.xcprivacy`), App Store privacy "nutrition labels" + Play data-safety form, required-reason API declarations, ATT, content rating, export compliance, **Apple's in-app account-deletion mandate**, a review-guideline checklist | compliance gate | **P2** |
| `mobile-accessibility` | VoiceOver/TalkBack labels & roles (`accessibilityLabel`/`accessibilityRole`), Dynamic Type / font scaling, **44×44pt (iOS) / 48×48dp (Android)** tap targets, contrast, focus order | a11y step, testing | **P2** |
| `design-system-conventions` | Design tokens, spacing/type scale, the chosen component kit (NativeWind / Tamagui for RN; shadcn/Radix for web), visual-regression conventions, the "propose N directions before building" pattern | design-review, implementation | **P2** |
| `performance-conventions` | Load testing (k6 / Locust), backend perf budgets (p95 latency, N+1 detection), mobile startup/bundle-size budgets, profiling entry points | perf-review, testing | **P3** |
| `api-edge-conventions` | **DRAFTED** (`global-skills/api-edge-conventions/SKILL.md`). Request-lifecycle hardening: rate limiting/throttling, CORS, security-header set, the error-envelope facade, idempotency keys, outbound timeouts/retries. The implementation counterpart to STRIDE's DoS/Tampering threats; defers auth to `auth-patterns` and logging to `logging-conventions`. Wiring TODO: add its trigger to the *on-demand skills* prose paragraph in the `planning` + `implementation` agent **bodies** (NOT `skills:` frontmatter — that preloads; both already have the `Skill` tool), then `list-skills.sh --annotate` + `install-global.sh` + restart | planning, implementation | **P2** |

Note the existing **`containerization-conventions`** gap recorded in memory (no
implementation/security wiring for authoring Dockerfiles/manifests or image scanning) — the
Max runway makes closing it cheap; fold image scanning (Trivy) into the security agent when
an image is built.

---

### 3.4 The mobile platform gap (first-class)

This is the headline capability gap. The stores require native or cross-platform mobile;
the pipeline produces a Python backend + **JS web** front-end + AWS. Everything below hangs
off one decision.

#### The decision: cross-platform (React Native + Expo) — recommended

**Recommendation: React Native + Expo, managed workflow with EAS.** Reasoning, in order of
weight for *your* situation:

1. **You're on Windows 11 (decisive).** Native iOS (Swift/SwiftUI) **cannot be built,
   tested, or code-signed without macOS + Xcode** — there is no Windows path. Even Flutter's
   iOS archive needs a Mac. **EAS Build compiles and signs iOS in Expo's cloud**, and EAS
   Submit uploads to App Store Connect — so the *entire* iOS path runs from your Windows
   machine with no Mac. For a solo Windows developer this single fact is close to decisive.
2. **Reuses your JavaScript.** The pipeline's front-end default is JS; RN is JS/TS. One
   language across web, mobile, and your tooling. `code-standards`, your mental model, and
   most of your skills port directly.
3. **The AI/LLM tooling ships first-class JS/TS SDKs.** The Anthropic SDK, the Vercel AI SDK,
   and the broader agent ecosystem all have first-class TypeScript support. A Claude-centric
   builder stays in one language (JS/TS across backend tooling, web, and mobile) instead of
   straddling Dart; RN keeps you there.
4. **One codebase → both stores.** Half the build/test/sign/deploy surface of two native
   codebases. OTA JS updates (EAS Update) ship fixes without a review cycle.

**Accepted trade-offs:** lower performance ceiling than native for graphics-heavy / game /
custom-animation work; occasional native-module bridging. For the app shape your stack
implies — auth + forms + data + API, "professional/production-grade" but not a 120fps game
— RN is comfortably sufficient.

**When to choose differently (documented, not default):**

- **Flutter** if the product *is* pixel-perfect design + custom animation across platforms
  and you'll accept a non-JS language (Dart) plus a cloud-Mac CI (Codemagic/EAS-equivalent).
  It leads on UI consistency and graphics; it loses your JS reuse and the AI-ecosystem fit.
- **Native (Swift/SwiftUI + Kotlin/Compose)** if you need deep platform integration
  (widgets, App Clips, complex background processing, Live Activities) or a long-horizon team
  with platform specialists. Higher ceiling, **two** codebases, and a hard macOS dependency
  for the iOS half — the wrong default for a solo Windows developer, the right call for a
  graphics/platform-deep product.

#### The full cascade (what changes downstream)

| Layer | RN + Expo (recommended) | Native equivalent (alternatives doc) | Pipeline change |
|---|---|---|---|
| **Default stack** | Add a documented "mobile path": RN + Expo + TS, Expo Router, Zustand + React Query | Swift/SwiftUI; Kotlin/Compose | New `mobile-stack-conventions` skill; planning gains a mobile-aware default (§3.3) |
| **Build hooks** | Local smoke = `tsc --noEmit` + `expo export` (Metro bundles cleanly) + `expo-doctor`; **full native compile is cloud (EAS) / CI**, not a per-stop check | `xcodebuild` (macOS-only → CI gate) / `./gradlew assembleDebug` | `smoke-check.sh` gains a mobile mode (§3.6). Native compile is **CI-only** because it can't run on your Windows box |
| **Unit / component tests** | **Jest + React Native Testing Library** | XCTest (iOS) / JUnit+Robolectric (Android) | testing agent mobile mode |
| **E2E / UI tests** | **Maestro** (cross-platform YAML flows; deterministic runner = zero model cost) | XCUITest (iOS) / Espresso (Android) | testing agent authors Maestro flows from code; Maestro MCP only for live debug (§3.2) |
| **Deployment / store delivery** | **EAS Build → EAS Submit** → TestFlight (iOS) + Play **internal** track; cloud iOS build from Windows | Fastlane (`gym` + `upload_to_app_store`) / Gradle Play Publisher | The deployment-*targets* doc already has Fastlane + Gradle sections; **add an EAS-first path** (it removes the Mac requirement). Pipeline boundary stays at the PR |
| **Code signing / entitlements** | `eas credentials` manages certs, provisioning profiles, keystore in the cloud; declare entitlements (push, associated domains, keychain groups) | Manual certs/profiles (iOS), keystore (Android) | New `mobile-release-conventions` skill; signing is a **CI/EAS** concern, not a local gate |
| **Store-compliance gates** | Privacy manifest, privacy-nutrition / data-safety, required-reason APIs, ATT, account deletion | identical store rules | New `store-compliance-gate.sh` + `app-store-compliance` skill (§3.5, §3.6) |
| **Mobile accessibility** | `accessibilityLabel`/`Role`, Dynamic Type, 44pt/48dp tap targets; lint via `eslint-plugin-react-native-a11y`; assert via Maestro / Accessibility Inspector / Android Accessibility Scanner | VoiceOver/TalkBack native APIs | New a11y step + `mobile-accessibility` skill (§3.5) |
| **Mobile security** | `expo-secure-store` (Keychain/Keystore) for tokens; optional cert pinning; jailbreak/root awareness; validate deep-link/OAuth redirects | Keychain / Keystore native | `auth-patterns` mobile addendum + security-agent mobile checks (§3.3) |

**The macOS reality, stated plainly:** with RN+Expo you can develop, test (via simulator on
a Mac *or* skip to EAS), and ship the entire app from Windows because EAS owns the Mac.
Live iOS-*simulator* driving (ios-simulator-mcp) still needs a Mac — so on Windows, your
local UI verification is Android-emulator-first (via `claude-in-mobile`/ADB) + Maestro, with
iOS verified in EAS/TestFlight. That's a workable loop and it's the strongest argument
against native, where the Mac dependency is unavoidable at *build* time.

---

### 3.5 Pipeline stages / agents

Each candidate evaluated **add / skip** with reasoning. New human checkpoints are proposed
in the spirit of "trade throughput for oversight and learning."

| Candidate | Verdict | Reasoning |
|---|---|---|
| **UI/UX design + design-review agent** | **ADD (opt-in, UI-bearing features)** | Two touch-points: (a) *before* implementation, a design step that consumes Figma (Figma MCP) or runs the "propose 4 visual directions, you pick one" pattern → a `.pipeline/design-spec.md` + a **new human checkpoint** (`design-approved`); (b) *after* implementation, a design-conformance review against the design system + visual-regression diff. This is the single biggest front-end-quality lever and it's where your "audit & learn" goal pays off most |
| **Accessibility audit** | **ADD (gate, can start folded into testing)** | A11y is non-optional for store quality and partly *mandatory* for compliance. Make it deterministic where possible (a11y lint rules + Maestro assertions); a lightweight gate writes `.pipeline/a11y-report.md`. Fold into the testing agent first; split into its own step if it earns one |
| **Performance / scalability review** | **ADD (advisory, like plan-audit)** | A non-gating reviewer (Sonnet/Haiku) that flags N+1 queries, missing indexes, unbounded result sets, mobile bundle-size/startup regressions, and applies `ddia-patterns`/`performance-conventions` at review time → `.pipeline/perf-review.md`. Advisory keeps it cheap and non-blocking; promote to a gate later if it proves out |
| **App-store pre-submission compliance gate** | **ADD (deterministic gate, fail-closed)** | The mobile analog of `deployment-gate.sh`: privacy manifest present, data-safety/nutrition mapping complete, required-reason APIs declared, version/build bumped, entitlements ⊆ declared capabilities, no debug flags, account-deletion path present. Fits the existing fail-closed pattern exactly. Pair with a **new human checkpoint** (`submission-approved`) before any store upload |
| **Plan-audit → full planning quality loop** | **ADD once telemetry justifies** | The score→re-plan loop (`docs/pipeline-refinement-loops.md`) was held back chiefly on cost grounds ("≈ a fresh planning pass on $20"), alongside the recursion-risk caution it documents. Max removes the cost objection; the recursion concern is handled by the one-revision cap. PR 3 ships a lighter plan-audit-sourced variant now. Promote to the full loop after a few runs if `run-log` shows the human repeatedly sending plans back on the same rubric items — that's literally its own documented trigger |
| New "release-manager" agent | **SKIP for now** | Versioning/changelog/staged-rollout matters (§3.9) but belongs in CI post-merge, not in the pre-PR pipeline. Document it in deployment-targets; don't add a pipeline stage |

**Resulting stage order (mobile, UI-bearing feature):**

```
planning → plan-audit → [HUMAN: plan-approved]
        → design-spec (Figma/propose) → [HUMAN: design-approved]
        → implementation → smoke-check (mobile mode)
        → security → testing (unit/RNTL + Maestro) → a11y audit
        → perf-review (advisory)
        → documentation
        → store-compliance-gate → [HUMAN: submission-approved]
        → deployment (commit + PR)
```

Backend-only features skip the design/a11y/compliance stages automatically (they no-op when
there's no UI / no mobile artifact, exactly like `infra-validate.sh` no-ops without `infra/`).

---

### 3.6 Hooks

All new hooks copy the existing patterns: ambient Stop hooks open with
`[ -f .pipeline/state.json ] || exit 0` (instant no-op outside a bootstrapped project); the
gate hook has **no** guard so it fails closed; cross-script calls resolve via the
self-relative `HOOK_DIR`. New hooks are published by `install-global.sh` like the rest.

**Existing-hook status correction:** every shell hook the pipeline ships today is implemented
and wired except **`post-deploy-check.sh`**, which is the *only* `[UNIMPLEMENTED]` hook (it is a
post-merge concern, deliberately out of the pre-PR loop). Earlier "`[UNIMPLEMENTED]`" labels on
other hooks are stale — treat them as wired.

| Hook | Change | Pattern |
|---|---|---|
| `smoke-check.sh` | Add a **mobile mode**, selected by `.pipeline/smoke.env` (e.g. `SMOKE_KIND=expo`). Expo path: `tsc --noEmit` → `npx expo export` (Metro bundle) → `npx expo-doctor`. **Native compile is explicitly deferred to EAS/CI** — don't attempt `xcodebuild` on Windows; on macOS, `xcodebuild build`/`gradlew assembleDebug` are valid as a heavier opt-in | Same greenfield/HEAD logic; same `write_smoke_status` |
| **`store-compliance-gate.sh`** (new) | Fail-closed pre-submission gate: privacy manifest present, data-safety map complete, required-reason APIs declared, version/build bumped vs last tag, entitlements ⊆ capabilities, account-deletion path present, no debug flags. Reads a `.pipeline/compliance-status.json` the compliance agent writes (same `jq`-status pattern as `security-status.json`) | Copies `deployment-gate.sh` exactly: no state guard, `jq`-presence check, exit 2 to block |
| **`a11y-lint.sh`** (new, ambient Stop) | Run `eslint-plugin-react-native-a11y` (mobile) / `axe`-style check (web) over the change set; write `.pipeline/a11y-report.md`; non-blocking by default (exit 1, non-silent) so it informs without halting | Like `infra-validate.sh`: no-op without UI files |
| `record-clean.sh` / `deployment-gate.sh` | Teach the deployment gate to *also* require `compliance-status.json == clean` **when a mobile artifact is present** (detected by `app.json`/`eas.json`/`*.xcodeproj`/`build.gradle`). On a backend-only change the new check no-ops, so nothing regresses | Extend the existing `jq` status checks; keep currency/`reviewed_change_hash` as-is |
| `infra-validate.sh` | Optionally add Trivy image scan when a Dockerfile/image is built (ties to the `containerization-conventions` gap) | Same no-op-without-`infra/` shape |

Critically, **none of these run native iOS builds locally** — that's a CI/EAS concern. The
local gates stay fast and deterministic; the heavy mobile build/sign/submit lives
post-merge, preserving the pipeline-ends-at-the-PR boundary.

---

### 3.7 Front-end quality specifically

This is the largest *quality* gap (distinct from the mobile *capability* gap). Today the
repo has **zero** front-end quality infrastructure: no design-system skill, no component
conventions, no visual-regression testing, no accessibility budget. `code-standards` is
backend-shaped.

**What's missing and what to add:**

- **Design-system / component conventions.** Add `design-system-conventions` (§3.3): design
  tokens (color/spacing/type scales), a chosen component kit — **NativeWind** (Tailwind-like)
  or **Tamagui** for RN, shadcn/Radix for web — and the rule that components are
  presentation-only with logic in hooks/services. Pick *one* styling approach and standardize
  (an open decision, §5).
- **Visual-regression testing.** Add it as a **deterministic runner step, not a model task**:
  Storybook + screenshot diffs (Chromatic or Playwright screenshots) for web; Maestro
  screenshots / a snapshot tool for mobile. Pixel diffs run in the runner at zero model cost —
  the same discipline the pipeline already applies to E2E.
- **Accessibility budgets.** Encode the `mobile-accessibility` rules as *lint* (fast,
  deterministic) plus a small set of asserted flows (Maestro). Budget examples: 100% of
  interactive elements have labels; tap targets ≥ 44pt/48dp; text scales to 200% without
  clipping; contrast ≥ WCAG AA.
- **Design-informed generation.** Wire the **Figma Dev Mode MCP** (§3.2) into the
  design-review + implementation path so the agent generates against real tokens/layout
  instead of guessing — the difference between "generic AI UI" and "matches the design."
  Combine with the "propose N directions before building" pattern for greenfield screens.
- **Claude Design as a design source (verified real — Anthropic Labs, Opus 4.7 research
  preview).** A third input path into the `design-spec` stage, alongside Figma Dev Mode MCP
  and propose-N-directions. A human designs the UI feature interactively in Claude Design
  (start from a prompt, uploaded images/docs, or by **linking this repo** so output matches
  our existing components/tokens), then uses **"Send to Claude Code"** to emit a **handoff
  bundle**: vanilla HTML/CSS/JS, per-state screenshots, the design tokens used on the canvas,
  and a README naming the target stack + conventions. That bundle *is* the `design-spec`
  input — it feeds the `design-approved` checkpoint, then the implementation agent
  **translates the vanilla markup into our framework** (React/JS per stack; it is not
  drop-in components). Two guardrails carried from the deferred-frontend memo: the handoff is
  the spec the deterministic **visual-regression pixel-diff gates against**, never itself a
  gate; and screenshot/README text is **untrusted input** — advisory to the build, never a
  driver of a deterministic gate.
- **Base the `design-system-conventions` skill on the official `frontend-design` plugin.**
  Anthropic ships `frontend-design` (in `anthropics/claude-code/plugins/`) — a two-pass
  "design-lead" skill that forces a token plan (4–6 hex palette; display/body/utility type;
  layout + ASCII wireframe; one signature element), self-critiques it against generic
  defaults, then builds. Adopt it as-is or fork it as the starting point for
  `design-system-conventions` rather than writing aesthetic guidance from scratch.

The net: a `design-spec` stage (fed by **Claude Design handoff / Figma MCP /
propose-N-directions**) + a design-conformance review + visual-regression in the runner + an
a11y budget turns the front-end from "renders" into "professional and publishable."

---

### 3.8 Backend scalability specifically

`ddia-patterns`, `logging-conventions`, and `iac-conventions` are good **decision guides**,
but they stop at the plan — nothing exercises scale, and two production essentials are named
as defaults yet not wired.

**Where today's skills fall short of production scale:**

- **`ddia-patterns` is plan-time only.** It weighs replication/partitioning/consistency but
  there's no review step that *checks* the implementation for the anti-patterns it warns
  about (N+1, unbounded scans, missing idempotency). Add the **performance/scalability review**
  (§3.5) so the guidance is enforced, not just documented; deepen the skill with the
  scale-out playbook (§3.3).
- **No load testing.** Add k6/Locust scaffolds via `performance-conventions` and a
  testing-agent mode (or the perf-review step) that runs a smoke-level load profile and
  records p50/p95/p99. On Max you can afford to generate and run these.
- **Observability is logged but not *alerted*.** `logging-conventions` is genuinely strong
  (structlog/Pino + OTel trace propagation + CloudWatch/X-Ray, PII redaction). What's missing
  is the **SLO/alerting automation** it references — wire CloudWatch alarms / SLO burn-rate
  alerts via `iac-conventions` so "alerting and SLOs" is real, not aspirational.
- **Error tracking (Sentry) is a named default but not wired.** This is the important one.
  Sentry MCP was correctly cut from the *pipeline loop* (architecture, not budget), but the
  **Sentry SDK belongs in the application code** — backend and mobile — for crash/error
  capture, release health, and breadcrumbs. Add it via `logging-conventions` (backend) +
  the mobile telemetry addendum, so every shipped app reports crashes from day one. Optionally
  give the *debugging* agent Sentry MCP for triaging a real prod incident.
- **IaC baseline lacks scale primitives.** `iac-conventions` covers the security baseline +
  S3/DynamoDB state + OIDC, but not auto-scaling groups, multi-AZ, health checks, or
  read-replica patterns. Add those as the production-scale defaults (§3.3).

---

### 3.9 What you're missing or forgetting

(Expanded in §6 — this is the dimension-anchored short list.)

- **Telemetry to measure your own upgrades.** `run-log.jsonl`/`log-run.sh` are
  **now wired** (Stop hook on all 8 agents) — the remaining gap is a digest that reads them (PR 5). They turn §3.1's model changes into a measured A/B
  instead of a vibe. Also where you'd watch LLM **cost control** on Max.
- **Secrets management at scale.** Today: `.gitignore` + GitHub secret-scanning + Dependabot
  (good hygiene) and a *mention* of AWS Secrets Manager/SSM in deployment-targets. Missing: a
  documented runtime-secrets pattern (pull from Secrets Manager at deploy, never GitHub
  secrets for app secrets) and the mobile side (`expo-secure-store`, EAS secrets).
- **CI/CD beyond the PR.** The patterns exist in deployment-targets but **nothing is wired**.
  EAS Workflows / GitHub Actions to TestFlight + Play internal is the post-merge half of the
  mobile story.
- **Legal / privacy.** GDPR/CCPA, a **privacy-policy URL** (both stores require one),
  **Apple's in-app account-deletion mandate** (required if you support account creation),
  data-export/deletion endpoints, the App Store data-disclosure + Play data-safety forms.
- **Crash analytics, feature flags, beta distribution, release management** — none wired
  (Sentry/Crashlytics; a flag service; TestFlight/Play internal; semver + changelogs + staged
  rollout). See §6 for the full candid list including push infra, deep linking, i18n, offline,
  and app-size budgets.

---

## 4. Prioritized, phased rollout

> **Superseded as the execution sequence by [`pipeline-revision-plan.md`](pipeline-revision-plan.md).**
> That plan is authoritative for *what ships in what order* (PR A → PR B → PR C, files, gates,
> verification). The phases below remain useful as the *rationale* for the grouping; where they
> differ from the plan, the plan wins (e.g. Opus is confined to planning + debugging, not
> implementation).

A **thin production-capable slice first**, then build out. Each phase is independently
shippable and (from Phase 1 on) measurable via the Phase 0 telemetry.

### Phase 0 — Instrument + raise the brains (days; pure config)
*Goal: immediate quality lift, and the instrument to prove it.*
- Wire `run-log.jsonl` / `log-run.sh` (telemetry first, so everything after is measured).
- Apply the §3.1 model/effort table: implementation → `opus`/xhigh, debugging → `opus`/xhigh,
  security → `opus`/high, testing → `sonnet`/medium, planning → `opus`/xhigh; **remove the
  no-op `effort:` lines from Haiku agents** (or move plan-audit to Sonnet).
- Risk: low (frontmatter only). Reversible instantly. **Do this first.**

### Phase 1 — Thin mobile slice end-to-end (the production-capable proof)
*Goal: one real mobile feature through the existing pipeline, validating the path.*
- Decide cross-platform vs native (§5) — recommended **RN + Expo**.
- Author `mobile-stack-conventions`; add the **mobile `smoke-check.sh` mode** (tsc + expo
  export + expo-doctor); add Jest/RNTL + one **Maestro** flow.
- Build ONE thin feature (a screen + an authenticated API call + its tests) through
  planning→…→deployment to validate the mobile cascade locally.
- Add the **EAS Build/Submit** docs to deployment-targets (cloud iOS build from Windows).
- Risk: medium (new stack). Contained to one feature; reuses all existing gates.

### Phase 2 — Quality + compliance (make it publishable)
*Goal: professional UI and a clean store submission.*
- `design-system-conventions` + **Figma MCP** (opt-in) + the **design-spec** stage and
  `design-approved` checkpoint; visual-regression in the runner.
- `mobile-accessibility` skill + `a11y-lint.sh` + asserted a11y flows.
- `app-store-compliance` skill + **`store-compliance-gate.sh`** + `submission-approved`
  checkpoint; `mobile-release-conventions` (signing/entitlements/EAS).
- Risk: medium. Each piece is a no-op on non-mobile/non-UI projects.

### Phase 3 — Scale + ops (production hardening)
*Goal: it survives real traffic and real users.*
- **Performance/scalability review** stage + `performance-conventions` + load testing.
- Wire **Sentry SDK** (backend + mobile); SLO/alerting via `iac-conventions`; auto-scale/
  multi-AZ IaC defaults.
- EAS Workflows / GitHub Actions to TestFlight + Play internal; secrets-manager pattern;
  feature flags; release management (semver + changelog + staged rollout).
- Implement the **planning quality loop** if Phase-0 telemetry shows repeat plan rejections.
- Risk: low-moderate; mostly additive and post-merge.

---

## 5. Open decisions for you

Concrete either/or choices, each with a recommendation.

1. **Mobile approach — cross-platform vs native.**
   **→ Recommend: React Native + Expo (cross-platform).** Windows-friendly (EAS builds iOS in
   the cloud), reuses your JS, first-class JS/TS AI SDKs, one codebase. Choose **native** only
   for a graphics/platform-deep product and a Mac at build time.
2. **If cross-platform — React Native vs Flutter.**
   **→ Recommend: React Native + Expo.** Flutter leads on pixel-perfect UI/animation but costs
   you JS reuse, the AI-ecosystem fit, and adds a non-JS language + cloud-Mac CI. RN keeps you
   in JS end-to-end.
3. **Expo managed (EAS) vs bare React Native.**
   **→ Recommend: managed / EAS.** Cloud iOS builds from Windows and managed signing
   credentials are the whole reason the iOS path works without a Mac. Eject later only if a
   native module forces it.
4. **Implementation-agent model — `opus`/xhigh vs `sonnet`/high.**
   **→ Recommend: `opus`/xhigh** for production-grade output; let Phase-0 telemetry confirm the
   cost is worth it. Sonnet/high is the fallback if the per-feature token delta surprises you.
5. **Security-agent model — `opus` vs `sonnet`.**
   **→ Recommend: `opus`/high.** The manual STRIDE/IDOR/RLS/validation reasoning deserves Opus;
   the scanners (Semgrep/OSV/Checkov) run model-independently, so you pay Opus rates only on the
   triage/remediation reasoning. `sonnet`/high is the cost-conscious fallback.
6. **Design source — Figma-driven vs code-first "propose N directions."**
   **→ Recommend: Figma MCP if you'll maintain Figma files; otherwise the propose-N-directions
   pattern.** Both feed the same `design-approved` checkpoint.
7. **RN styling / component kit — NativeWind vs Tamagui vs StyleSheet + tokens.**
   **→ Recommend: NativeWind** (closest to your likely web Tailwind instincts) **or Tamagui**
   (stronger design-system primitives). Pick one and standardize in `design-system-conventions`.
8. **Implement the planning quality loop now that Max makes it cheap?**
   **→ Recommend: yes, but gated on telemetry** — wire it only once `run-log` shows the human
   sending plans back on the same rubric items (its own documented trigger). The *cost*
   objection is gone; the *need* should still be demonstrated.

---

## 6. Things you may be forgetting (candid)

Beyond the dimensions above, the gap between "a pipeline that opens a PR" and "an app two
stores will approve and real users will trust":

- **Apple's in-app account-deletion mandate.** If the app supports account *creation*, Apple
  **requires** an in-app account-deletion path (not just "email us"). A frequent rejection
  cause. Add it to `app-store-compliance` and the gate.
- **Privacy policy URL — both stores require one.** Plus the App Store privacy "nutrition
  labels" and the Play data-safety form, which must *accurately* match what the app collects
  (including third-party SDKs). Mismatches get flagged.
- **Developer accounts & timelines.** Apple Developer Program ($99/yr) + Google Play ($25
  one-time). First review can take days–weeks; Play has a newer "closed testing before
  production" requirement for new personal developer accounts. Budget calendar time, not just
  tokens.
- **Crash analytics + release health.** Sentry or Crashlytics, wired in code (§3.8). Without
  it, your first signal of a production crash is a 1-star review.
- **Feature flags.** No flag system today. You'll want kill-switches and staged rollouts
  (LaunchDarkly / Statsig / a self-hosted flag table) before you ship to real users.
- **Beta distribution + staged rollout.** TestFlight (iOS) and Play internal/closed tracks
  (partly in deployment-targets); production rollouts should be **percentage-staged**, not
  100% on day one.
- **OTA boundaries.** EAS Update ships JS-only fixes instantly — but a **native** change
  (new permission, native module, SDK bump) needs a full store build. Encode this boundary so
  you don't try to OTA something that requires review.
- **Push notifications, deep links / universal links, i18n, offline/sync, app-size budgets.**
  Each is its own infrastructure (APNs/FCM; associated-domains + verified deep links;
  localization; offline cache + conflict handling; app-size keeps install conversion up). None
  exist yet; add them as features demand, but plan the auth/deep-link one early (it intersects
  your OAuth/MFA flow).
- **Secrets at scale + cost controls.** A runtime secrets-manager pattern (not GitHub secrets
  for app secrets) and **LLM cost telemetry** (the Phase-0 `run-log`) plus cloud cost
  alarms — on Max you have headroom, but headroom you don't watch is headroom you waste.
- **Monitoring / on-call.** SLOs + alerting + a paging path (even a solo-dev PagerDuty/email
  rule). "Logged" isn't "noticed."
- **The macOS dependency is real even if you go native/Flutter.** EAS is what removes it for
  RN; if you ever choose native, budget for a cloud-Mac CI (Codemagic, GitHub macOS runners,
  or a Mac mini) — there is no Windows escape hatch for native iOS builds.
- **Measure before you standardize.** The most important "forgetting" risk is upgrading every
  agent to Opus/xhigh and never reading the telemetry to see which upgrades actually moved
  quality. Wire the log, run a handful of features, and let the data — not this document —
  pick the final per-agent settings.
