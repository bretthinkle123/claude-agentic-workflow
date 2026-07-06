# PR History

Every pull request made against this repo, in order. All 33 land between **2026-06-27 and 2026-07-06** — the repo's entire PR history falls inside the last two weeks, so the concept summary at the end covers everything.

## The PRs

| # | Date | Title | What it did |
|---|------|-------|-------------|
| 1 | Jun 27 | Plan-audit agent + security inline remediation | New advisory **plan-audit** agent (plan-wording flags, anti-slopsquatting dependency checks, version policy); security agent upgraded to fix exploitable vulns inline and verify STRIDE mechanisms from `plan.md`. |
| 2 | Jun 29 | Pipeline revision PR A: retune + audit fixes | Model/effort retune across all 8 agents (planning opus/xhigh, security sonnet/high, etc.); `log-run.sh` auto-derives model from agent frontmatter. |
| 3 | Jun 29 | PR B: smarter agents + plan/acceptance contracts | plan-audit structural completeness check with material-vs-advisory flags and `revision_recommended`; planning one-shot revision loop; acceptance-criteria contracts. |
| 4 | Jun 29 | PR C: autonomous loop + circuit-breaker | Post-approval orchestrator loop driving security ⇄ debugging ⇄ testing until GREEN, with circuit-breaker shipped in the same commit and a run-log digest. |
| 5 | Jun 29 | PR D: post-revision cleanup | Doc/comment/tracking polish after A/B/C; two small behavior changes (debugging regression-test scoping). |
| 6 | Jun 29 | PR E: 7 robustness-roadmap items | Conditional, trigger-gated conventions: migration round-trip / fuzz / concurrency test modes, perf budgets + k6 smoke load, Trivy container scan, and more — all no-op unless a feature warrants them. |
| 7 | Jul 1 | PR F + SEC: M2 fast-fixes + security-agent upgrade | Security → opus/high with independent STRIDE-delta reasoning; deployment → sonnet with read-only pre-commit content inspection; M2 audit fast-fixes. |
| 8 | Jul 1 | PR G (M1): criterion-completeness gate | Deterministic `deployment-gate.sh` check: every non-null perf-budget dimension must be measured for a criterion to count as covered; advisory test-quality flags. |
| 9 | Jul 1 | AE wiring + G6 | `api-edge-conventions` skill wired on-demand into planning/implementation; F6 integrity nits. |
| 10 | Jul 1 | PR H (M8): deterministic eval harness | `tests/run-eval.sh` — zero-LLM bash+jq regression suite (6 suites / 74 assertions at birth) against a golden Linkly fixture; the repo's safety net ever since. |
| 11 | Jul 1 | PR I: review integrity + supply-chain (M5/M6/F3) | Human-only `approve-diff.sh` (TTY-gated); deployment gate requires `diff-approved` + matching change hash; supply-chain and data-safety checks. |
| 12 | Jul 1 | PR J: token/altitude polish | Moved always-loaded prompt blocks (dependency-audit policy, threat-model de-dup) behind on-demand skills; no gate/loop/hook logic change. Completed Track 1. |
| 13 | Jul 2 | Track-1 hardening: loop-exit ≡ gate guard | The invariant suite now extracts the orchestrator SKILL's *own* jq predicates instead of comparing against a harness-private copy — drift in any clause now fails the harness. |
| 14 | Jul 2 | PR K (closed, superseded by #15) | Auto-closed when its stacked base branch was deleted on merge of #13. |
| 15 | Jul 2 | PR K (M9): pipeline threat model + marker guard | STRIDE over the *engine itself* (`docs/pipeline-threat-model.md`); `guard-approval-markers.sh` PreToolUse hook + Write/Edit deny blocking subagents from forging human approval markers. |
| 16 | Jul 2 | docs: PR K guard verification | Live-verified the Write/Edit marker deny is precisely scoped to the two markers; recorded in the threat model. |
| 17 | Jul 2 | M2 audit remediation (determinism, gates, telemetry) | Every pipeline finding from the dual Ledgerly/Linkly audit: locale-stable change hashing, `.gitattributes` bootstrap, gate/telemetry/calibration fixes; new hash-determinism suite. |
| 18 | Jul 2 | Universal input-control enforcement | Every input source must have a validation contract + rate-limit policy (or recorded waiver), test-covered, with declared-vs-implemented drift detection. ASVS V5/V11-aligned. |
| 19 | Jul 2 | ASVS 5.0.0 verification layer | 17-chapter ASVS checklist; threat model declares a target level (L1/L2/L3); security step 6g verifies triggered chapters and records verified/missing requirements. |
| 20 | Jul 3–4 | ASVS enforcement + hardening specs | Turned ASVS from advice into enforcement: planning emits an `## ASVS Compliance` block, L1+L2 items are definition-of-done, deterministic gate floors (`asvs.reconciled`, waiver authenticity, `asvs-sast.json` critical block). |
| 21 | Jul 4 | Front-end design integration | New **design-spec** agent (opus): normalizes untrusted design bundles (Claude Design / Figma MCP / screenshots) into `.pipeline/design-spec.md` with provenance + injection report and a human vouch; iOS/SwiftUI target planned. |
| 22 | Jul 4–5 | docs: design-spec sync | Reference docs brought current with the design-spec stage (interlock table, nine agents, marker list). |
| 23 | Jul 4–5 | Security side-tracks: DP + EG + SB | **DP**: every stored sensitive field needs a named at-rest control or waiver (new gate floor, mirrored into loop-exit). **EG**: egress allowlist + `egress-check.sh`. **SB**: scanner breadth incl. Gitleaks. |
| 24 | Jul 5 | docs: DP/EG/SB sync | README counts (21 hooks, 16 global skills, 7 project skills) and architecture docs updated. |
| 25 | Jul 5 | ASVS-DET Slices C/D + FE Layer 4 | `asvs-sast.sh` deterministic rules (cookie-flag disables critical; debug-to-client/CORS-wildcard/secret-in-URL advisory); reduced-assurance stamp; design-review Layer 4. |
| 26 | Jul 5–6 | DAST Layer 1 (runtime ZAP baseline) | First *runtime* security control: post-GREEN advisory stage boots the app and runs an OWASP ZAP passive baseline (launcher + pure-jq testable core). Plus Track-2 delivery/security plan docs. |
| 27 | Jul 6 | App-store compliance gate | Deterministic `store-compliance.sh` (privacy manifest, release-build debuggable, etc.) blocking known auto-rejection causes for iOS/Android; reduced-assurance Android arm. Wired like `asvs-sast.sh` — deploy-only floor, zero loop-exit churn. |
| 28 | Jul 6 | Track 2 kickoff: PR L — CI as the merge gate | `.github/workflows/eval.yml` runs the full harness (20 suites / 333 assertions) on every push/PR; design-record retention into `docs/decisions/<branch>/`; PR N/O kickoff plans. |
| 29 | Jul 6 | Track 2: PR M — build + artifact provenance | `templates/ci/build-provenance.yml` chains on PR L's merge gate: hadolint → OIDC AWS auth → immutable SHA-tagged build → dockle → CycloneDX SBOM → cosign keyless sign + attest → SLSA provenance; self-skips without a Dockerfile. New `delivery-conventions` skill. |
| 30 | Jul 6 | Track 2: PR N — environments + progressive delivery + real load | `templates/ci/deploy.yml` (inert until `DEPLOY_ENABLED=true`): cosign verify-before-rollout identity-pinned to this repo's workflow → staging deploy (RDS snapshot → migrate → rollout) → canary with burn-rate rollback; real load campaign. No new gate hooks, no loop-exit change. |
| 31 | Jul 6 | Track 2: PR O — triage agent + observability wiring | New read-only **triage** agent: operator-invoked with one Sentry issue id, writes `.pipeline/incident-brief.md` and stops — safety by tool absence (no Bash/Edit). Plus observability scaffolding (Sentry, OTel→CloudWatch/X-Ray, SLOs + burn-rate alarms) feeding the canary rollback. |
| 32 | Jul 6 | Track 2: PR P — scale validation + DR drill + cost + continuous vuln | Final Track-2 item: `scale-ceiling` k6 ramp proving autoscaling fires (abort = the ceiling measurement), monthly `dr-drill.yml` executing a real restore, cost guardrails, continuous vulnerability re-scanning. Per-project scaffolding; no engine/gate change. |
| 33 | Jul 6 | CQ + DAST Layer 4 + STORE SC-6/7/9 + doc sync & audit-residual fixes | `codeql` job fills `pipeline-ci.yml`'s Layer-4 reserved slot (security-extended queries, SHA-pinned, alert-only by default; CI-only by design). **DAST Layer 4**: `dast-conventions` skill + planning's DAST-readiness ACs (served OpenAPI schema, seeded test user, auth context) + a plan-audit material flag. **STORE SC-6/7/9**: Required-Reason API compare (critical), permission declared↔used and debug-log-flood checks (advisory) — the store plan fully delivered. Plus this doc, the post-Track-2 architecture sync, and fixes for the pre-build audit's surviving findings. |

## Two-week summary, by concept

**The agent roster.** The pipeline grew from its original agents to eleven: **plan-audit** (#1, advisory plan completeness + dependency reality-checks), **design-spec** (#21, untrusted design-bundle normalization), and **triage** (#31, read-only incident summarizer, safe by tool absence) are entirely new. Existing agents were retuned (#2, #7): planning runs opus/xhigh, security became opus/high with independent STRIDE-delta reasoning and inline vulnerability fixing (#1, #7), deployment gained read-only pre-commit content inspection (#7), and testing gained conditional modes for migrations, fuzzing, concurrency, and perf load (#6).

**Autonomy with a leash.** The orchestrator's post-approval loop (#4) drives security ⇄ debugging ⇄ testing to GREEN without human turns, guarded by a circuit-breaker. Its highest-severity invariant — **loop-exit ≡ deployment-gate** — got a real regression guard that reads the SKILL's own predicates (#13).

**Trust and integrity.** Human approval became unforgeable: TTY-gated `approve-diff.sh` plus a gate that binds approval to the exact change hash (#11), then a structural two-vector block (Bash hook + Write/Edit deny) preventing any subagent from writing the approval markers (#15, #16), all mapped in an engine-level STRIDE threat model (#15).

**App security, layered.** Static: universal input-control accountability (#18), ASVS 5.0.0 as enforced definition-of-done with deterministic gate floors (#19, #20), deterministic ASVS-SAST rules (#25), data-protection / egress / scanner-breadth side-tracks (#23). Runtime: DAST Layer 1 with a ZAP passive baseline (#26). Delivery: the app-store compliance gate (#27).

**Verifiability + delivery.** The deterministic eval harness (#10) grew from 74 to 333 assertions across 20 suites and now runs in CI as the merge gate (#28), with post-merge builds producing immutable, cosign-signed, SBOM-attested images with SLSA provenance (#29). Track 2 then completed the path to production: verify-before-rollout deploys with staging → canary → burn-rate rollback and real load validation (#30), and finally scale-ceiling drills that prove autoscaling fires, an executed monthly DR restore, cost guardrails, and continuous vulnerability re-scanning (#32).

**Operations.** Deployed apps get observability wiring — release-tagged Sentry, OTel→CloudWatch/X-Ray, SLO definitions with burn-rate alarms feeding the canary rollback — plus the operator-invoked triage agent that turns one Sentry issue into a human-facing incident brief without any write or exec capability (#31). Criterion-completeness (#8) closed the "covered:true but unmeasured perf budget" hole; the M2 audit remediation (#17) made change-hashing and gate telemetry deterministic.

**Front-end.** The design-spec stage (#21, #25) lets the pipeline build faithfully from a provided design while treating the bundle as untrusted input requiring a human vouch.

**Efficiency + docs.** Token/altitude polish moved always-loaded blocks behind on-demand skills (#9, #12); three dedicated doc-sync PRs (#16, #22, #24) plus cleanup (#5) kept the human-facing references honest.
