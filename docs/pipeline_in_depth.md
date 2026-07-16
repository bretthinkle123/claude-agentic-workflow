# Pipeline in depth — every file, grouped by function

A plain-language map of everything in this repo: what each group of files is for, what the
individual files do, and exactly when each one gets touched during a live pipeline run. Written
as a study/interview reference — `system_architecture.md` is the formal spec; this is the
"explain it to another engineer" version.

**The one-paragraph elevator pitch:** this repo is a reusable multi-agent SDLC pipeline built
on Claude Code. Ten specialized subagents each own one stage (design-spec → planning →
plan-audit → implementation → security → testing → documentation → deployment, plus a debugging
loop and a standalone triage agent). Agents share **no** conversation context — every piece of
cross-stage state travels through files in a gitignored `.pipeline/` directory. Every
deterministic decision (gates, retry caps, scan evidence, approval currency) is enforced by
shell scripts (hooks) that cost zero LLM tokens and that a prompt-injected model cannot argue
with. The whole thing installs once to `~/.claude/` and bootstraps into any project with one
command.

---

## Table of contents

1. [Agents (`global-agents/`)](#1-agents-global-agents)
2. [Hooks (`global-hooks/`)](#2-hooks-global-hooks)
3. [Global skills (`global-skills/`)](#3-global-skills-global-skills)
4. [Project-skill templates (`global-project-skills/`)](#4-project-skill-templates-global-project-skills)
5. [Templates (`templates/`)](#5-templates-templates)
6. [Scripts (`scripts/`)](#6-scripts-scripts)
7. [The runtime interlock files (`.pipeline/` — created per project)](#7-the-runtime-interlock-files-pipeline)
8. [Telemetry & analytics (the `.jsonl` files)](#8-telemetry--analytics-the-jsonl-files)
9. [The eval/regression harness (`tests/`)](#9-the-evalregression-harness-tests)
10. [CI for the engine itself (`.github/workflows/`)](#10-ci-for-the-engine-itself-githubworkflows)
11. [Curated documentation (`docs/`)](#11-curated-documentation-docs)
12. [Plan archive (`plan/` and gitignored `plans/`)](#12-plan-archive-plan-and-gitignored-plans)
13. [Session memory (`memory/`)](#13-session-memory-memory)
14. [Run evidence (`examples/meterly/run-evidence/`)](#14-run-evidence-examplesmeterlyrun-evidence)
15. [Repo plumbing (root files and `.claude/`)](#15-repo-plumbing-root-files-and-claude)
16. [A live run, file by file](#16-a-live-run-file-by-file)

---

## 1. Agents (`global-agents/`)

**What they are:** ten Markdown files, one per pipeline stage. Each file is YAML frontmatter
(model, effort level, tool allow-list, skills to preload, hooks to wire, `maxTurns` cap)
followed by a system-prompt body that tells the agent exactly what its one job is. They are
published to `~/.claude/agents/` by the installer and invoked from the main Claude Code session
(the orchestrator) via the Agent tool.

**The key design property:** every subagent starts with a **fresh, blank context**. It sees
only its own system prompt plus the short instruction string it was invoked with. It cannot see
the conversation that spawned it. That is *why* all state must flow through `.pipeline/` files
— the files are the pipeline's shared memory.

| File | Stage | Model / effort | Job in one line |
|---|---|---|---|
| `design-spec.md` | conditional pre-stage | opus / high | Normalize an untrusted design bundle (Figma export, screenshots, Claude Design) into `.pipeline/design-spec.md` with a provenance + prompt-injection report. Only runs if the project has a design source. |
| `planning.md` | 1 | opus / xhigh | Read the codebase (or `PROJECT.md`), write `.pipeline/plan.md` (with a STRIDE threat model) + `.pipeline/acceptance.md` (the definition of done). Never writes app code. Opus at max effort because a bad plan is the most expensive mistake in the pipeline. |
| `plan-audit.md` | 2 | sonnet / medium | Advisory second pair of eyes on the plan before the human sees it: completeness, ambiguous wording, dependency reality (are these packages real? — anti-slopsquatting), version policy. Never edits the plan; can trigger exactly one planning revision. |
| `implementation.md` | 3 | sonnet / high | Refuses to start without the human's `plan-approved` marker, then writes the code. Highest-volume stage, so it runs on Sonnet. On large features (≥25 files) it runs once per task segment from `tasks.md`. |
| `debugging.md` | on failure | opus / xhigh | Two roles from one definition: *sanity* (smoke check failed) and *remediation* (security/testing failed). Reproduce-first, write a failing→passing regression test, log the root cause to `debug-notes.md`. Retry-capped — never loops forever. |
| `security.md` | 4 | opus / high | Runs the scanner battery (Semgrep, OSV, Gitleaks, Trivy, Checkov) through evidence-stamping wrappers, plus manual reasoning: STRIDE-mechanism verification, attack-surface delta, ASVS 5.0 checks. Fixes exploitable findings directly; writes `security-report.md` + machine-readable `security-status.json`. |
| `testing.md` | 5 | sonnet / medium | Writes missing tests, runs the suite, maps results to acceptance criteria (`criteria_covered`), records coverage and the `tested_change_hash` into `test-results.json`. |
| `documentation.md` | 6 | sonnet | Updates per-directory READMEs, the architecture doc, and writes `pr-description.md`. Only runs once security and testing are clean. Its Stop hook checks that every identifier it documented actually exists in the tree (no invented API names). |
| `deployment.md` | 7 | sonnet | Bash-only agent that makes the pipeline's first and only commit, pushes, and opens the PR — but only after the deterministic deployment gate passes. |
| `triage.md` | standalone | opus / high | **Not part of the loop.** Operator-invoked, read-only (no Bash, no Edit) incident summarizer: one Sentry issue in, one human-facing `incident-brief.md` out. It never fixes or deploys anything. |

**Model assignment is a deliberate cost strategy:** Opus (expensive, deep reasoning) only on
low-volume/high-stakes stages — planning, debugging, security. Sonnet on the high-volume
structured stages. Agents that touch untrusted content (web, dependency docs, design bundles)
are never the agents that can push.

---

## 2. Hooks (`global-hooks/`)

**What they are:** 41 shell scripts (plus the `loop-exit-predicate.jq` GREEN-predicate data
file, two egress-proxy helpers, and the `ui-capture.mjs` Node helper) published to
`~/.claude/hooks/`.
Hooks are the pipeline's **deterministic enforcement layer** — they run outside the model, at
zero LLM cost, wired into agent frontmatter as either `Stop` hooks (fire when an agent
finishes) or `PreToolUse` hooks (fire *before* a tool call executes and can block it). The
design mantra: *a prompt-injected agent cannot argue with a shell script.* Every ambient hook
opens with `[ -f .pipeline/state.json ] || exit 0`, so they are instant no-ops in
non-pipeline repos.

### Gates and guards (can block the pipeline)

| File | Fires | What it does |
|---|---|---|
| `deployment-gate.sh` | PreToolUse on deployment's `git commit` | The final gate. Recomputes — never trusts agent claims — the five core conditions: tests pass, acceptance criteria fully covered, security status `clean`, `pr-description.md` exists, and the human `diff-approved` marker exists **and** its hash matches the current working tree. On top of those it enforces deterministic floors that a rosy `clean` status can't override: any OSV finding at CVSS ≥ 7 without a human waiver, `asvs.reconciled == false`, `scan_reconciled == false`, uncontrolled input sources, unprotected sensitive stored fields, `asvs-sast.json` / `store-compliance.json` critical > 0, fabricated waivers (any waiver claimed in `security-status.json` with no matching human record in `waivers.json`), and source markers in the change set. Fails closed if interlock files are missing. |
| `smoke-check.sh` | Stop on implementation | Boots the app and curls `/health` (or does a build/import check pre-first-commit). Exit 2 routes to the debugging agent. Writes `smoke-status.json`. |
| `infra-validate.sh` | Stop on implementation | If an `infra/` directory exists, runs `terraform fmt/validate/plan` and saves the plan output for human review. |
| `loop-guard.sh` | orchestrator-called (`reset`/`tick`/`done`) | The circuit breaker: caps debug cycles and wall-clock time per feature. Cap hit = stop and escalate to the human. Writes `loop-state.json` and journals to `loop-events.jsonl`. |
| `guard-approval-markers.sh` | PreToolUse Bash on every Bash-carrying agent | Blocks any tool call that would create/modify the human-owned files: `plan-approved`, `diff-approved`, `design-approved`, `waivers.json` — including indirect routes (`echo >`, scripts) a permission glob would miss. One of three independent layers preventing an agent from approving its own work. |
| `guard-push.sh` | PreToolUse Bash on the 6 **non-deployment** Bash agents | Blocks `git push` / `gh pr` writes / mutating `gh api` (incl. subshell/brace/backtick/chained forms) so **only the deployment stage can reach the remote** — a prompt injection at any earlier stage can't publish code. Exit 2, never a prompt (autonomy preserved). Deployment deliberately does *not* carry the hook, so it still pushes; a bypassed push reaches at most a branch, which branch protection + `diff-approved` still block from merging. |
| `guard-source-markers.sh` | Stop on implementation + debugging; also a gate conjunct | Greps the change set for revert/do-not-commit-class markers (`TEMP-REVERT`, `DO NOT COMMIT`) and blocks. Plain TODOs pass. |
| `guard-tree-hygiene.sh` | Stop on security + debugging | Blocks scanner/scratch junk left in the repo tree — enforces "tool output goes to `.pipeline/`, never the tree." |
| `guard-webfetch-domains.sh` (+ `webfetch-domains.txt`) | settings-level PreToolUse on WebFetch | Domain allowlist for the **main orchestrator thread's** web fetches (no pipeline subagent holds WebFetch — the main thread reads untrusted content too, so it's injectable too). Deny-not-ask by design: a deterministic denial lets an unattended run adapt and keep moving instead of stalling on a prompt. Denials are logged to `.pipeline/webfetch-denied.jsonl` for between-run triage into the list; parses the URL defensively (strips path/query/fragment before userinfo so a planted `@` can't bypass it) and fails closed on any parse problem. |
| `lockfile-check.sh` | run by security | Supply-chain integrity: a manifest changed without its lockfile is a blocking critical; unpinned deps warn. |
| `check-doc-identifiers.sh` | Stop on documentation | Verifies every identifier written into a README resolves in the tree and signatures match the def site — kills hallucinated API names in docs. Tally persisted to `doc-identifiers.json`. |
| `design-review-check.sh` | post-GREEN, conditional | Compares UI captures to the visual/a11y budget → advisory `design-review.json`. Never a gate. |
| `store-compliance.sh` | Stop on security (declared iOS/Play target only) | Deterministic app-store checks: privacy manifest, usage strings, targetSdk floor, debuggable release, permission declared↔used. Gate blocks on critical > 0. |
| `asvs-sast.sh` | Stop on security | Deterministic grep-level SAST for four high-value ASVS violations (JWT `alg:none`, fast password hash, non-CSPRNG, weak cipher). Gate blocks on critical > 0 — a floor that holds even if the model's judgment fails. |

### Human-only checkpoint tools

| File | What it does |
|---|---|
| `approve-diff.sh` | The M5 diff-review checkpoint. **Refuses to run without a TTY** so only a human typing in a real terminal can execute it. Writes `diff-approved` containing the SHA-256 of the exact working tree that was reviewed — so a later change silently invalidates the approval (currency anchoring). |
| `approve-plan.sh` | The plan-side twin of `approve-diff.sh`, same TTY-only pattern. Checks `plan.md` exists, asks for explicit confirmation, and writes `plan-approved` with a `plan_sha256` provenance record. Exists because a real run had an "operator said approved but the marker was never touched" mix-up (the orchestrator correctly refused and waited ~2h). A bare `touch .pipeline/plan-approved` remains valid — the checkpoint contract is existence — but the script is the recommended path. |
| `record-waiver.sh` | TTY-only recorder of security waivers (`waivers.json`). The security agent may *honor* a waiver but can never *create* one; the gate cross-checks that every claimed waiver has a matching human record. |
| `notify-checkpoint.sh` | Pages the operator when a run reaches a checkpoint, caps out, or hits an unexpected prompt — this is what makes "walk-away" runs practical. Three backends in order: ntfy push (if a topic is configured), Windows toast, and always an append to `.pipeline/notify-log.jsonl`. Also wired as a settings-level Notification hook so *any* unexpected permission wait pages instead of silently freezing the run ("stall-to-page"). Hard payload rule: event kind + feature slug + repo name only — never findings or diff content, since ntfy crosses an external service. Always exits 0, so a notification failure can never wedge a run. |

### Scan-evidence chain (the "stop trusting a summary integer" system)

| File | What it does |
|---|---|
| `semgrep-scan.sh`, `osv-scan.sh`, `trivy-scan.sh`, `checkov-scan.sh`, `gitleaks-scan.sh`, `ast-grep-scan.sh` | Wrappers that run the real scanner with identical args, write raw output to `.pipeline/<tool>.json`, then stamp the execution. The raw binaries are deliberately **not** on the permission allow-list — a scan can't run unstamped. |
| `stamp-scan.sh` | Appends one hash-anchored stamp per scanner run to `scan-log.jsonl`: `{tool, exit_code, artifact_sha256, ts}`. A security report may only claim a scan "executed this pass" if a this-pass stamp exists — otherwise it's honestly "carried forward". |
| `reconcile-scans.sh` | Stop hook on security: **recomputes** every per-tool finding count from the raw artifacts and blocks on any mismatch with `security-status.json`. The model cannot report a rosier number than the artifacts support. |
| `generate-sbom.sh` | Writes a CycloneDX SBOM (`sbom.cdx.json`) via Trivy. Best-effort, non-gating. |

### Hashing, telemetry, and state plumbing

| File | What it does |
|---|---|
| `compute-change-hash.sh` | SHA-256 over the working-tree diff + untracked files — the single change-set identity used by approvals, testing, and documentation. |
| `write-review-manifest.sh` | Called by documentation; records `reviewed_change_hash` into `review-manifest.json` (a sanity input to `approve-diff.sh`). |
| `log-run.sh` | Stop hook on **every** agent: appends one JSON line per stage per run to `run-log.jsonl` — the audit trail that makes an unattended run reviewable after the fact. |
| `stamp-ran-at.sh` | Fires first on testing + security Stop: stamps the real UTC `ran_at` into the result JSONs so a stale artifact can't masquerade as fresh. |
| `record-clean.sh` | Stop on testing: when both security and tests are green, resets the per-cycle debug retry counters in `state.json`. |
| `registry-check.sh` | Plan-audit's anti-slopsquatting lookup, and a nice example of least-privilege design: bare `curl` is never allow-listed (any-host egress), so this wrapper enumerates exactly the npm/PyPI JSON API hosts and refuses everything else. Its exit codes distinguish "package does not exist" (the slopsquat signal) from a network timeout (treated as *unverified*, never as *absent*). |
| `check-run-host.sh` | Kickoff pre-flight (advisory, never a hard gate): names the isolation tier of the run location — WSL-native filesystem (sandbox-eligible), Windows host (convenience tier), or worst-case `/mnt/*`/OneDrive paths (sync-corruption hazard; a real canary run had its venv quarantined by OneDrive mid-run). The orchestrator surfaces the verdict; the human decides. |
| `post-deploy-check.sh` | Lives here but is CI-homed: reborn as the `deploy-verify` job in `pipeline-ci.yml` (probes the deployed health URL). Never a pipeline Stop hook. |

### Deterministic driver (advisory — L1)

**Not gates** — these block nothing. They make orchestration reproducible: the orchestrator
consults them to decide *what runs next and with what prompt*, but is only advised by them,
not compelled (enforcing that would be "L2"). They reuse the deploy gate's own GREEN
predicates, so a decision the driver makes can never disagree with what the gate would accept.

| File | What it does |
|---|---|
| `next-stage.sh` | Transition function: reads `.pipeline/*` + the **same** jq GREEN predicates the deploy gate uses, and prints ONE next-action token (`run:<stage>` / `run:debugging:<conjunct>` / `checkpoint:plan\|diff` / `mark:loop-completed` / `stop:capped` / `run:deployment`). Loop ordering (re-scan after debugging) *emerges* from a change-set hash rather than a remembered cursor: security records `scanned_change_hash`, testing `tested_change_hash`; a recorded hash that no longer matches the tree means "stale → re-run." Pinned byte-identical to the gate by `tests/suites/next-stage.sh` (`driver ≡ gate ≡ SKILL`). |
| `stage-prompt.sh` | Context registry: an action token → the agent name + a prompt whose slots are filled from state by jq (the failing security conjunct's CVSS/lists, the failing test's names) — a reproducible `Agent(name, prompt)` instead of an improvised prose prompt. |
| `loop-exit-predicate.jq` | The **canonical GREEN predicate** itself (a jq expression, not a script). Moved here from `tests/` so it publishes with the hooks and `next-stage.sh` can consume it at runtime; shared by the deploy gate check, the orchestrator, and the test harness so the three can never drift. |

### Egress control (the sandbox's network layer)

| File | What it does |
|---|---|
| `egress-allowlist.txt` | The default-deny outbound ACL — the single source of truth for which hosts a run may reach (git remote, package registries, harness domains). |
| `egress-check.sh` | Stop hook on security: reads the proxy's `egress-log.jsonl` and surfaces any DENIED host as a warning — a signal that something tried to phone home. |
| `egress-proxy/` (`tinyproxy.conf`, `tinyproxy-logonly.conf`, `build-filter.sh`, `bridge-log.sh`, `README.md`) | The operator-provisioned enforcing proxy recipe for the WSL2 sandbox — tinyproxy configs (enforcing + log-only reconnaissance mode), the filter builder, and the log bridge that produces `egress-log.jsonl`. |

### Optional runtime verification (advisory, never gates)

| File | What it does |
|---|---|
| `ui-capture.sh` + `ui-capture.mjs` | Front-end Layer 4: Playwright renders declared screens → screenshot → pixelmatch diff vs baseline → axe a11y scan → `ui-capture.json`. No `ui.env`/Playwright ⇒ clean no-op. |
| `dast-capture.sh` | DAST Layer 1: boots the app and runs the OWASP ZAP passive baseline in Docker → raw `dast-capture.json`. Opt-in via `dast.env`. |
| `dast-review.sh` | Tallies ZAP alerts by severity against `dast-budget.json` → advisory `dast-review.json`. |

---

## 3. Global skills (`global-skills/`)

**What they are:** reference-knowledge packages — a directory per skill with a `SKILL.md` (and
sometimes scaffold code or companion docs). Published to `~/.claude/skills/`. Two loading
modes, and the distinction is a cost lever:

- **Preloaded** — named in an agent's frontmatter, injected into its context on *every*
  invocation (costs tokens every time). Reserved for knowledge the stage always needs.
- **On-demand** — the agent invokes it via the Skill tool only when the feature actually needs
  it (a feature with no auth never pays for `auth-patterns`).

### The pipeline's own operating manual

- `pipeline-orchestration/` — the most important skill: stage sequence, interlock-file
  contracts, gate semantics, debug-loop routing, run pre-flight, evidence preservation. Loaded
  by the **orchestrator** (the main session driving the run), not by a subagent.
- `requirements-elicitation/` — operator-invoked pre-planning interview that sharpens a thin
  brief into `.pipeline/requirements.md`. Never auto-invoked, never a gate.
- `debugging-escalation-protocol/` — preloaded in debugging: retry caps, sanity-vs-remediation
  roles, when to escalate.
- `deployment-checklist-and-rollback/` — preloaded in deployment: pre-flight checks, the
  commit → push → PR sequence.
- `diff-scoping-conventions/` — preloaded in security + testing so both stages compute the
  **same** change set and hash.

### Engineering-conventions library (mostly on-demand, loaded per feature shape)

- `code-standards/` (+ `examples.md`) — preloaded in implementation: naming, SOLID, facade
  modules, security invariants, and the report-honesty rule.
- `stride-threat-model-template/` (+ `asvs-5.0-checklist.md`, `examples.md`) — preloaded in
  planning: the STRIDE worksheet and the ASVS compliance-scope block; the checklist sibling is
  what security's ASVS verification step reads.
- `doc-conventions/` (+ templates for READMEs, PR descriptions, diagram examples) — preloaded
  in documentation.
- `auth-patterns/` (+ TypeScript/Python scaffold files) — Firebase facade, OAuth, MFA.
- `logging-conventions/` (+ scaffold) — structured logging, PII redaction, OTel.
- `secrets-management/` — runtime secret fetch from AWS SM/SSM behind a facade.
- `data-protection-conventions/` — classify every stored field → required at-rest control.
- `data-lifecycle-conventions/`, `regulated-data-conventions/`, `audit-trail-conventions/` —
  retention/erasure, compliance-regime mapping (HIPAA/PCI/GDPR), per-record access audit.
- `api-edge-conventions/` (+ middleware scaffold) — rate limiting, CORS, headers, idempotency.
- `iac-conventions/` (+ `baseline.md`) — Terraform layout and IaC security baseline.
- `ddia-patterns/`, `containerization-conventions/` — architecture decision guides for planning.
- `dependency-audit-policy/` — plan-audit's registry reality-check + version-cooldown policy;
  only loads when the plan adds a dependency.
- `ci-conventions/`, `dast-conventions/`, `delivery-conventions/`,
  `observability-conventions/` — the post-merge world: CI gate contract, DAST opt-in
  mechanics, signed/attested builds, SLOs and burn-rate alarms.
- `triage-conventions/` — preloaded in triage: incident-brief schema, redaction rules.

### Vendored third-party content

- `VENDORED.md` — the provenance ledger: every vendored tool/skill is pinned to an upstream
  commit, reviewed, and rowed here; a test suite (`tests/suites/vendored.sh`) enforces it.
- `frontend-design/` — vendored Anthropic design-guidance skill (not yet wired to an agent).
- `skill-creator/` — vendored authoring guide for writing new skills (operator tool).
- `impeccable/` — **dormant** reference material only: no SKILL.md, wired to nothing; its
  network-touching engine was deliberately excluded.
- `README.md` — how to add/update a skill in this system.

---

## 4. Project-skill templates (`global-project-skills/`)

Same format as global skills, but these are **copied into each project** by bootstrap (into the
project's `.claude/skills/`) because their content is project-specific:

- `test-conventions/` — test structure, runner, coverage thresholds; carries `<placeholders>`
  the planning stage fills per project.
- `semgrep-ruleset-guide/` — which Semgrep rule packs apply per language/framework.
- `ast-grep-rules/` — security's structural-search rules pack; findings are advisory prose
  only, never a count or gate input.
- `design-system-conventions/` — design-spec's extraction schema.
- iOS/store set (loaded only for a declared mobile target): `swift-conventions/`,
  `apple-hig-compliance/`, `claude-design-to-swiftui/`,
  `app-store-submission-requirements/`, `google-play-submission-requirements/` — the
  store-submission rules become acceptance criteria at planning time, not surprises at review.

---

## 5. Templates (`templates/`)

Seed files that `bootstrap-project.sh` copies into a new project:

| File | Becomes | Purpose |
|---|---|---|
| `CLAUDE.md` | project `CLAUDE.md` | Per-project conventions + run commands (fill placeholders). |
| `project-settings.json` | project `.claude/settings.json` | The **entire permission model**: `defaultMode: "auto"` for autonomy, the scoped command allow-list, the `ask` tier (force-push, settings edits), the `deny` tier (credentials, approval markers), and the `autoMode` policy (egress limited to git remote + registries; approval markers hard-denied "by ANY means"). Kept project-scoped on purpose — never elevated globally. |
| `state.json` | `.pipeline/state.json` | Seeds retry counters (`debug_retry_count`, `max_retries: 3`). Its existence is also the flag that marks a repo as a pipeline project (every ambient hook checks for it). |
| `mcp.json` | `.mcp.json` | Sample MCP server wiring for projects that opt in. |
| `ui.env` / `design-budget.json` | `.pipeline/…` | Opt-in for the visual-review stage: declare the servable UI + the visual-diff/a11y budget. |
| `dast.env` / `dast-budget.json` | `.pipeline/…` | Opt-in for the DAST stage: scan target + boot command, per-severity ZAP caps. |
| `renovate.json` | project root | Continuous dependency updates whose PRs flow through the same gates. |
| `notify.env.example` | operator config | Notification (toast/ntfy) settings for checkpoint paging. |

### `templates/ci/` — the per-project delivery chain (GitHub Actions)

The authoring pipeline ends at the PR; these extend the guarantees past the merge:

- `pipeline-ci.yml` — the CI merge gate: re-runs the deterministic gates on the merge commit
  (so a laptop-side bypass can't merge), plus CodeQL deep SAST (alert-only), deploy-verify,
  and an opt-in mutation-testing job. A placeholder guard fails any job left in vacuous-green
  template state.
- `build-provenance.yml` — post-merge: hadolint → OIDC to AWS → SHA-tagged image build →
  dockle → CycloneDX SBOM → cosign keyless signing → SLSA attestation. Self-skips without a
  Dockerfile.
- `deploy.yml` — opt-in: verify signature → staging (snapshot → migrate → rollout) → prod
  behind a GitHub environment rule → weighted canary (10/50/100) with burn-rate auto-rollback.
- `load-campaign.yml` — k6 load tests against staging with thresholds from the acceptance
  budget, failover drill, scale-ceiling ramp.
- `dr-drill.yml` — monthly disaster-recovery drill: real restore into a throwaway instance,
  verify, assert RTO/RPO, tear down.
- `scheduled-rescan.yml` — weekly OSV + Trivy re-scan of the shipped artifact.
- `dast-staging.yml` — nightly Schemathesis API fuzz + authenticated ZAP active scan vs
  staging (DAST Layers 2+3).

---

## 6. Scripts (`scripts/`)

Operator/installer tooling — run by a human or the orchestrator, not by pipeline agents:

- `install-global.sh` — publishes `global-agents/`, `global-hooks/`, `global-skills/`, and
  `templates/` to `~/.claude/`. The repo is the source of truth; `~/.claude/` is the runtime.
- `bootstrap-project.sh` — run once in any target repo: writes `.claude/settings.json`,
  `.pipeline/state.json`, `smoke.env`, `CLAUDE.md`, `PROJECT.md` stub, `.gitignore` entries,
  and copies the project skills. Idempotent — never clobbers edited files; never runs git.
- `run-log-digest.sh` — zero-LLM summary of `run-log.jsonl` (per-stage attempts, flags).
- `run-summary.sh` — at GREEN, distills the run log + loop journal into
  `run-summary.json` (per-stage attempts/models/caps + the assurance level). The retrospective
  must quote from it, never hand-write numbers.
- `preserve-transcripts.sh` — evidence preservation: copies every subagent transcript out of
  the Claude Code session store into a run-evidence dir with a sha256 MANIFEST; refuses empty
  files. Exists because an earlier run silently lost its evidence.
- `list-skills.sh` — classifies every SKILL.md as preloaded vs on-demand by parsing agent
  frontmatter (the authoritative view).
- `setup-wsl-pipeline.sh` / `verify-sandbox.sh` — provision and verify the WSL2 sandbox
  (disposable Linux userland + enforcing egress proxy + repo-scoped GitHub token) that makes
  fully unattended runs safe against hostile inputs.

---

## 7. The runtime interlock files (`.pipeline/`)

These don't live in this repo (the directory is gitignored in every project) but they are the
heart of a live run — the shared memory between fresh-context agents. Grouped by who owns them:

**Written by agents (stage outputs):**
`design-spec.md`, `plan.md`, `acceptance.md` (criteria contract + `criteria_total`
denominator), `tasks.md` (large features only), `plan-audit.md`, `surface-delta.md`
(implementation's attack-surface hint to security), `implementation-progress.md` (warm-resume
note every ~15 turns), `debug-notes.md`, `security-report.md` + `security-status.json`,
`test-results.json` + `test-quality.json`, `pr-description.md`, `incident-brief.md` (triage).

**Written only by humans (the checkpoint markers):**
`plan-approved` (typed `touch` after reading the plan + audit), `diff-approved` (via TTY-only
`approve-diff.sh`; embeds the approved tree hash), `design-approved` (orchestrator-transcribed
with a content hash), `waivers.json` (TTY-only `record-waiver.sh`), `requirements.md` (the
operator's own words). Agents are blocked from minting these three independent ways: the
permission deny rule, the autoMode hard-deny, and the `guard-approval-markers.sh` hook.

**Written by hooks (deterministic evidence):**
`smoke-status.json`, `asvs-sast.json`, `store-compliance.json`, `scan-log.jsonl`, raw
`<tool>.json` scanner artifacts, `sbom.cdx.json`, `doc-identifiers.json`,
`review-manifest.json`, `ui-capture.json` / `design-review.json`, `dast-capture.json` /
`dast-review.json`, `infra-plan.txt`.

**State and configuration:**
`state.json` (retry counters), `loop-state.json` (the feature-level breaker budget),
`smoke.env` / `ui.env` / `dast.env` / budgets (operator opt-ins), `repomix-pack.xml`
(optional single-file repo map for planning on big codebases).

---

## 8. Telemetry & analytics (the `.jsonl` files)

Append-only JSON Lines files — the pipeline's flight recorder. Append-only matters: a later
event can never erase an earlier one (e.g. a loop `reset` can't hide a prior cap-out).

| File | Writer | One line per | Why it exists |
|---|---|---|---|
| `run-log.jsonl` | `log-run.sh` (every agent's Stop hook) | stage invocation | The core audit trail: `{ts, feature, branch, stage, status, model, attempt, retries, files_changed, notes, …}`. Testing lines add coverage and pass/fail counts; security lines add finding counts. From it you derive cost-per-stage (model tier × files changed), first-pass gate rate, debug-retry rate, wall-clock per stage, and cap-outs. A capped stage's Stop hook never fires, so the orchestrator writes an explicit `capped` breadcrumb line — a missing line is itself a finding. |
| `loop-events.jsonl` | `loop-guard.sh` | breaker event (reset / cap-out / done) | The durable cross-check on the loop: proves how many debug cycles a feature took and whether it capped. |
| `scan-log.jsonl` | `stamp-scan.sh` via every scanner wrapper | real scanner execution | `{tool, exit_code, artifact_sha256, ts}` — the evidence that a scan actually ran this pass, hash-anchored to its raw artifact. The reconciliation hook recounts findings from those artifacts. |
| `egress-log.jsonl` | the sandbox's egress proxy | outbound connection attempt | ALLOWED/DENIED per host. Any DENIED host becomes a security warning — the tripwire for exfiltration attempts or a dependency phoning home. |
| `notify-log.jsonl` | `notify-checkpoint.sh` | page sent | Record of when/why the operator was paged during an unattended run (the always-on third backend after ntfy/toast). |
| `webfetch-denied.jsonl` | `guard-webfetch-domains.sh` | denied WebFetch | `{ts, domain}` per denial — triaged into `webfetch-domains.txt` between runs, so the allowlist converges the same way the egress list does. |
| `run-summary.json` | `run-summary.sh` at GREEN | (single JSON, not JSONL) | The distilled per-run rollup: per-stage invocations, attempts, caps, models, and the `assurance` stamp. Downstream docs must quote it rather than hand-writing numbers. |

For real token/$ figures (not available to shell hooks), the operator runs `npx codeburn`
out-of-band and snapshots it into the run journal.

---

## 9. The eval/regression harness (`tests/`)

The pipeline's own test suite — deterministic, zero-LLM, run with `bash tests/run-eval.sh`
(~690 assertions across 34 suites). This is how changes to the *engine* are verified before
they ship.

- `run-eval.sh` — entry point; exit 0 iff every suite passes. Also the CI merge gate.
- `suites/*.sh` — one suite per enforcement mechanism: gate logic, diff-approval currency,
  marker forgery guards, loop-guard caps, the canonical GREEN predicate, hash determinism,
  scan reconciliation, egress, waiver authenticity, tree hygiene, doc identifiers, telemetry,
  notification, sandbox, WebFetch guard, vendored-content ledger, bootstrap integration, and
  more. The naming convention is: every past escape/incident became a permanent suite.
- `helpers/` — `assert.sh` (shared assertions). The **canonical GREEN predicate**
  `loop-exit-predicate.jq` — the single jq expression defining "security clean AND tests pass
  AND criteria complete" — now lives in `global-hooks/` (so it publishes with the hooks and
  `next-stage.sh` consumes it at runtime), shared so the gate, the orchestrator, and the tests
  can never drift apart.
- `fixtures/` — golden `.pipeline/` snapshots the suites run against: `linkly-green/` (a known
  all-green state) and `m3/` (preserved evidence from the M3 validation runs — both an audit
  corpus and regression fixtures).
- `agent-evals/` — the *other* kind of test: planted-defect golden trees
  (`security-topology/`, `testing-dead-knob/`, `doc-invented-name/`, …) where
  `run-agent-evals.sh` invokes the **real agent** against a frozen tree containing a documented
  defect and greps its output for the finding. Needs model access, so it's a separate step, not
  part of `run-eval.sh`. Each has an `expected-findings.json`.
- `tests/README.md` — how to run all of it.

---

## 10. CI for the engine itself (`.github/workflows/`)

- `eval.yml` — runs the full deterministic harness on every push/PR to main; `eval` is a
  required check, so the engine's own merge gate is the same harness developers run locally.
  (The `templates/ci/` workflows are what the pipeline gives *target projects*; this one file
  is the engine eating its own dog food.)

---

## 11. Curated documentation (`docs/`)

Operator-curated living docs (nothing auto-generated lands here):

- `pipeline-changelog.md` — what shipped, organized by design unit, with rationale.
- `pr-history.md` — the same history PR-by-PR with a by-concept summary.
- `roadmap.md` — forward-looking only: open items, deferred workstreams, cadences.
- `pipeline-threat-model.md` — STRIDE applied to **the pipeline engine itself** (prompt
  injection, marker forgery, exfiltration) — deliberately separate from the per-feature threat
  model the planning agent writes for the app being built.
- `finding-ledger.md` — one row per confirmed escape/incident; each becomes a permanent check
  (suite case, hook, or agent-eval). The "never re-learn a lesson" mechanism.
- `sk-assessment-log.md` — ongoing skill-assessment log.
- `pipeline-wsl-operations.md` — the operator guide for sandboxed walk-away runs: WSL2 setup,
  checkpoint/notification flow, token lifecycle, egress-allowlist maintenance.
- `pipeline-alternatives.md` / `pipeline-deployment-targets.md` / `pipeline-mcp-config.md` —
  reference companions: non-default stacks, post-merge CI/CD patterns, MCP wiring per agent.
- `decisions/<branch>/` — design-record retention: documentation copies
  plan/acceptance/plan-audit/security-report here per feature branch before the PR.
- `pipeline_in_depth.md` — this file.

---

## 12. Plan archive (`plan/` and gitignored `plans/`)

`plan/` is the tracked archive of every shipped design: the ~2,900-line
`agentic-pipeline-plan.md` chronological design log, the original June analysis and master
roadmap, per-track specs (CI merge gate, delivery ops, egress control, DAST, ASVS determinism,
design-spec stage, iOS target, store compliance, triage agent…), executed run plans
(M3/M4-series, the eval runs), and audits. Two files are explicitly *designs not yet built*
(`pipeline-code-quality-audit.md`, `pipeline-refinement-loops.md`). `plan/README.md` states
the convention.

`plans/` (plural) is gitignored scratch — new drafts live there and get promoted into `plan/`
only when a PR publishes them.

These files are not used during a run; they are the paper trail of *why the engine is shaped
the way it is* — useful interview material in their own right.

---

## 13. Session memory (`memory/`)

Claude Code's persistent cross-session memory for **this repo's development** (not for target
projects). One Markdown file per durable fact with frontmatter (`name`, `description`,
`type: user|feedback|project|reference`), e.g. `brett-profile.md`, `project-context.md`,
`testing-coverage-contract.md`, `audit-prompt.md`. `MEMORY.md` (in the user-level memory
directory) is the index — one line per memory — loaded into context at the start of every
session so a new session starts already knowing the settled decisions, preferences, and open
threads instead of re-deriving them.

**Role in a live run:** none directly — the pipeline agents never read it. It's what keeps the
*orchestrating* Claude consistent across sessions of building and operating the engine
(e.g. "approvals are desk-only", "check existing plan files before asking").

---

## 14. Run evidence (`examples/meterly/run-evidence/`)

Preserved, hash-verified evidence from real validation runs against the Meterly test app —
the proof the pipeline works, kept for audit:

- `m3-final-pipeline/`, `m4/`, `m4-prime/`, `m4-double-prime/`, `canary-usage-daily/` — each
  is a frozen `.pipeline/` snapshot from a real run: the plan, audits, scanner artifacts,
  telemetry JSONLs, run summaries, retrospectives, and audit reports.
- `transcripts*/` subdirectories — every subagent transcript from the run, preserved by
  `preserve-transcripts.sh` with a `MANIFEST.sha256` so an auditor can verify nothing was
  altered after the fact.
- `run-journal.md` — the operator's narrative journal across runs.

This is also where the evidence-preservation lesson lives: an early run lost its feedback data
(the M2 incident), which is why preservation is now a scripted, hash-verified protocol.

---

## 15. Repo plumbing (root files and `.claude/`)

- `README.md` — entry point: install, bootstrap, propagation workflow, doc map.
- `system_architecture.md` — the formal current-state reference (every file, every contract,
  the Mermaid flow diagrams). This doc is its narrative companion.
- `.claude/settings.json` — the permission model for developing *this repo* (same shape as the
  project template, plus expected writes to `~/.claude/` since the installer publishes there).
- `.gitignore` — keeps `.pipeline/`, `plans/`, env files, and state out of git.
- `.gitattributes` — line-ending/diff behavior (shell scripts must stay LF to run in WSL).
- `LICENSE` — the license.

---

## 16. A live run, file by file

The timeline of one feature moving through a bootstrapped project, naming every file as it
comes into play:

**Before the run (once per project):** `install-global.sh` has published agents/hooks/skills
to `~/.claude/`; `bootstrap-project.sh` has written `.claude/settings.json` (permissions),
`.pipeline/state.json` (retry counters), `smoke.env` (only when `--start`/`--health`/`--build`
flags were given), `CLAUDE.md`, `PROJECT.md`, and project skills. For a walk-away run, the WSL2 sandbox is up (`setup-wsl-pipeline.sh`,
`verify-sandbox.sh`) and the egress proxy is logging to `egress-log.jsonl`.

1. **Kickoff.** The operator describes the feature (optionally sharpening it first with the
   `requirements-elicitation` skill → `requirements.md`). The orchestrator loads
   `pipeline-orchestration` and runs pre-flight (`check-run-host.sh`, identity asserts).
2. **Design-spec (conditional).** If a design source exists, the design-spec agent (guided by
   `design-system-conventions`) writes `design-spec.md` with an injection report; the human
   reviews and `design-approved` (with a content hash) is recorded.
3. **Planning.** The planning agent (preloading `stride-threat-model-template`, pulling
   conventions skills on demand) writes `plan.md` + `acceptance.md` (and `tasks.md` if ≥25
   files). Its Stop fires `log-run.sh` → first line in `run-log.jsonl`.
4. **Plan audit.** plan-audit writes advisory `plan-audit.md` (loading
   `dependency-audit-policy` + `registry-check.sh` if new deps appear). One planning revision
   max if material flags exist.
5. **Human checkpoint #1.** The human reads plan + audit and records approval in their own
   terminal — `approve-plan.sh` (TTY-only, records the plan's sha256) is the recommended
   path; a bare `touch .pipeline/plan-approved` also satisfies the gate. No agent can create
   this file — permission deny + autoMode hard-deny + `guard-approval-markers.sh`.
6. **Implementation.** Verifies `plan-approved`, writes code (preloading `code-standards`),
   appends `implementation-progress.md` every ~15 turns, emits `surface-delta.md`. On Stop:
   `smoke-check.sh` boots the app and hits `/health` (→ `smoke-status.json`),
   `infra-validate.sh`, `guard-source-markers.sh`, `log-run.sh`.
7. **Debug loop (on failure).** Smoke fail → debugging agent (sanity role), guided by
   `debugging-escalation-protocol`, logs to `debug-notes.md`, increments `state.json`
   counters. `loop-guard.sh` ticks `loop-state.json` and journals `loop-events.jsonl`;
   cap hit → `notify-checkpoint.sh` pages the human.
8. **Security.** Scans the change set (scoped by `diff-scoping-conventions`) through the
   stamped wrappers — raw artifacts to `.pipeline/<tool>.json`, stamps to `scan-log.jsonl` —
   plus manual STRIDE/ASVS reasoning. Stop hooks: `guard-tree-hygiene.sh`, `asvs-sast.sh`,
   `store-compliance.sh`, `egress-check.sh` (reads `egress-log.jsonl`), `stamp-ran-at.sh`,
   `reconcile-scans.sh` (recounts findings — blocks on mismatch), `log-run.sh`. Output:
   `security-report.md` + `security-status.json`.
9. **Testing.** Writes/runs tests, maps `criteria_covered` against `acceptance.md`, records
   `tested_change_hash` (via `compute-change-hash.sh`) into `test-results.json` +
   advisory `test-quality.json`. Stop: `stamp-ran-at.sh`, `record-clean.sh` (resets retry
   counters if all green), `log-run.sh`.
10. **GREEN check.** The orchestrator evaluates the canonical jq predicate
    (`loop-exit-predicate.jq` logic): security clean AND tests pass AND criteria complete.
    Not green → debugging (remediation role) → re-run security AND testing. Green →
    `loop-guard.sh done`, `run-summary.sh` writes `run-summary.json`.
11. **Optional runtime checks.** `ui.env` present → `ui-capture.sh`/`ui-capture.mjs` →
    `design-review-check.sh` (advisory). `dast.env` present → `dast-capture.sh` (ZAP) →
    `dast-review.sh` (advisory). Neither ever gates.
12. **Documentation.** Updates READMEs and architecture docs per `doc-conventions`, writes
    `pr-description.md`, copies decision records to `docs/decisions/<branch>/`, calls
    `write-review-manifest.sh` (→ `review-manifest.json`). Stop:
    `check-doc-identifiers.sh` (no invented names), `log-run.sh`.
13. **Human checkpoint #2.** The human reviews the diff (plus an automated `/code-review`
    pre-step) and runs `approve-diff.sh` — TTY-only — which writes `diff-approved` containing
    the SHA-256 of the exact reviewed tree.
14. **Deployment.** The deployment agent attempts `git commit`; `deployment-gate.sh` fires
    first (PreToolUse) and independently recomputes all five conditions — tests pass, criteria
    complete, security clean, PR description exists, `diff-approved` current — plus the
    deterministic floors (`asvs-sast.json`, `store-compliance.json`, waiver authenticity,
    source markers). Pass → commit, push, `gh pr create`. The pipeline's first and only commit.
15. **After the PR.** `pipeline-ci.yml` re-runs the gates on the merge commit;
    `build-provenance.yml` produces the signed/SBOM'd/attested image; opt-in workflows deploy
    with canary + auto-rollback, load-test, DR-drill, and re-scan. Production incidents come
    back through the read-only triage agent (`incident-brief.md`) into a *new* human-started
    run. The operator archives evidence with `preserve-transcripts.sh`.

**The interview-sized summary of why it's built this way:** fresh-context agents +
file-based interlocks make every handoff explicit and auditable; deterministic hooks make
every gate incorruptible by prompt injection; human approvals are unforgeable files anchored
to content hashes; append-only JSONL telemetry makes unattended runs reviewable after the
fact; and every past failure is frozen into a permanent test so the engine only ever fails a
given way once.
