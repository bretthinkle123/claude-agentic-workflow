# Pipeline changelog — what shipped, by design unit

> The single answer to "what's implemented and why it improved the pipeline," organized by the
> design-plan lettering (PR A–K, Track 2 L–P, side-tracks), newest last. Each row: what changed ·
> why · where the deep rationale lives (archived under `plan/`). The GitHub-PR-indexed view of the
> same history — every actual pull request with dates — is `docs/pr-history.md`; this doc is the
> design-unit view. Current-state reference: `docs/system_architecture.md`. No new claims here —
> content consolidated from `plan/pipeline-june-analysis.md` §10, `plan/pipeline-revision-plan.md`,
> and `plan/max-pipeline-improvements.md`.

## Track 1 — the authoring engine (→ "10/10 scaffolder", reached 2026-07-01)

- **PR A — instrument + retune** (merged as #2). Model/effort retune across all agents (planning
  opus/xhigh, implementation kept sonnet/high deliberately — the quality investment goes in the
  audit layer, not the generator); `log-run.sh` telemetry derives model from agent frontmatter.
  Rationale: `plan/max-pipeline-improvements.md` §3.1; decisions: `plan/pipeline-revision-plan.md`
  PR A.
- **PR B — smarter agents + contracts** (#3). The plan-audit structural completeness check with
  material-vs-advisory flags and a one-shot planning revision loop; validation + acceptance-criteria
  contracts that downstream stages verify against. `plan/pipeline-revision-plan.md` PRs 3/4/6.
- **PR C — autonomous loop + circuit-breaker** (#4). The post-approval orchestrator loop driving
  security ⇄ debugging ⇄ testing to GREEN without human turns, circuit-breaker in the same commit,
  run-log digest. `plan/pipeline-revision-plan.md` PR 5.
- **PR D — post-revision cleanup** (#5). Doc/tracking polish after A–C; debugging regression-test
  scoping.
- **PR E — robustness roadmap** (#6). Seven conditional, trigger-gated conventions: migration
  round-trip / fuzz / concurrency test modes, perf budgets + k6 smoke load, Trivy container scan —
  all no-op unless a feature warrants them. `plan/pipeline-revision-plan.md` roadmap table.
- **PR F — M2 fast-fixes + SEC/DEP bundle** (#7). Greenfield `.gitignore` fix (F2) + per-agent
  `maxTurns` bumps (F4); security → opus with the step-6f STRIDE-delta reconciliation; deployment →
  sonnet with read-only pre-commit content inspection.
- **PR G — quality + criterion-completeness gate (M1)** (#8). The deterministic perf-pairing floor:
  a non-null `perf.budget.*` must have a non-null `perf.measured.*` for the criterion to count as
  covered (closes finding F1 — partial verification scored as full coverage); advisory
  `test-quality.json`; branch coverage surfaced, not gated.
- **PR G6 — results-file integrity** (#9, with AE). Real `ran_at` via the `stamp-ran-at.sh` Stop
  hook; terminal `loop-state` on GREEN exit (closes F6).
- **PR H — the eval harness (M8)** (#10). `tests/run-eval.sh`, deterministic bash+jq, zero model
  calls — 6 suites / 74 assertions at birth against a golden Linkly fixture; the repo's safety net
  ever since (now 21+ suites in CI). Its crown-jewel suite asserts **loop-exit ≡ deployment-gate**
  from the SKILL's own predicates (#13 hardened this to read the live predicates, so drift fails
  the harness).
- **PR I — review integrity + supply chain (M5/M6/F3)** (#11). Human-only TTY-gated
  `approve-diff.sh` whose approved change hash becomes the deploy gate's currency anchor (closes
  the F3 self-re-anchor vector); `/code-review` as the automated pre-review; `lockfile-check.sh` +
  CycloneDX SBOM; prod-shaped migration seeds + backup-before-migrate.
- **PR J — token/altitude polish** (#12). Always-loaded prompt blocks moved behind on-demand skills
  (`dependency-audit-policy`), threat-model formatting de-duped into the preloaded STRIDE skill.
  Completed Track 1.

## Engine trust + app-security side-tracks (parallel, 2026-07-01 → 07-06)

- **PR K — pipeline-as-target threat model (M9)** (#15/#16). STRIDE over the *engine itself*
  (`docs/pipeline-threat-model.md`); approval-marker forgery structurally blocked two ways
  (`guard-approval-markers.sh` Bash hook + Write/Edit deny).
- **M2 audit remediation** (#17). Locale-stable change hashing, `.gitattributes` bootstrap,
  gate/telemetry/calibration fixes; hash-determinism suite. `plan/audit-remediation-plan.md`.
- **Input-control enforcement** (#18). Every input source needs a validation contract + rate-limit
  policy or recorded waiver, with declared-vs-implemented drift detection.
  `plan/input-controls-enforcement-plan.md`.
- **ASVS 5.0.0 + ASVS-DET** (#19/#20/#25). The 17-chapter checklist as enforced
  definition-of-done with deterministic gate floors (`asvs.reconciled`, human-owned waivers,
  `asvs-sast.sh` Tier-1 rules). Roadmap doc: `docs/asvs-determinism-roadmap.md`.
- **DS — design-spec stage** (#21/#22). Untrusted design bundles (Claude Design / Figma / 
  screenshots) normalized into a human-vouched, hash-anchored `design-spec.md` with an injection
  report. `plan/design-spec-stage-plan.md`.
- **DP / EG / SB — security side-tracks** (#23/#24). Per-field at-rest protection as a gate floor
  (`plan/data-protection-enforcement-plan.md`); default-deny egress allowlist + detection
  (`plan/egress-control-plan.md`); scanner breadth (Gitleaks, `trivy fs`, per-stack Semgrep).
- **DAST** (#26, completed #33). Runtime security in four layers, from the post-GREEN local ZAP
  passive baseline to nightly staging Schemathesis fuzz + authenticated active scan. Living
  convention doc: `docs/dast-plan.md`.
- **STORE — app-store compliance gate** (#27, completed #33). Deterministic `store-compliance.sh`
  (SC-1…SC-9) blocking known auto-rejection causes for a declared iOS/Android target; reduced-
  assurance stamp for gate-unverifiable targets. `plan/store-compliance-plan.md`.

## Track 2 — delivery + operations (→ "10/10 fully-functional", reached 2026-07-06)

Full specs: `plan/ci-merge-gate-plan.md` (L), `plan/delivery-operations-plan.md` (M–P),
`plan/environments-delivery-plan.md` (N), `plan/triage-agent-plan.md` (O).

- **PR L — CI as the merge gate** (#28). The eval harness as a required GitHub check; design-record
  retention; `SCAN_BASE` re-run mode so CI re-verifies the merge commit rather than trusting the
  author's local green. Day one it caught a real engine bug (0644 exec bits from Windows).
- **PR M — build + artifact provenance** (#29). Immutable SHA-tagged images, CycloneDX SBOM,
  cosign keyless signing, SLSA provenance; `delivery-conventions` skill.
- **PR N — environments + progressive delivery + real load** (#30). Verify-before-rollout →
  staging (snapshot → migrate → rollout) → prod behind a human environment rule → weighted canary
  with burn-rate auto-rollback; k6 load campaign closing F1 with real numbers.
- **PR O — observability + read-only triage agent** (#31). Sentry/OTel/SLO wiring feeding the
  canary rollback; the operator-invoked triage agent, safe by tool absence.
- **PR P — scale validation + DR** (#32). Scale-ceiling ramp proving autoscaling fires, monthly
  executed DR restore drill, cost guardrails, continuous vuln re-scanning.
- **CQ — CodeQL in CI** (#33). Semantic taint analysis as the Layer-4 CI job, per-language build
  matrix, alert-only by default.

## Validation era — evidence-driven fixes (2026-07-07 →)

- **M3 unified fix plan** (#34). The first PR shaped by *running* the pipeline: 22 engine fixes
  from three real Meterly runs. Headline class: **gates green over wrong work** — presence checks
  where efficacy checks were needed. Answers: recompute `criteria_covered` from `by_id`,
  per-category security efficacy questions, hash-anchored scan reconciliation as a new
  loop-exit≡gate conjunct, `docs/finding-ledger.md`, and the `tests/agent-evals/` planted-defect
  corpus. Full detail: `docs/pr-history.md` row 34; run plans under `plan/` (m3/m4 files).
- **TA — skill & MCP overhaul** (#35) and **SK — skill enrichment** (#36). The vetted-tooling
  adaptations and the public-skill mining pass over the authoring agents' skill files.
- **Regulated-data skills** (#37). `regulated-data-conventions` (regime → control router),
  `audit-trail-conventions`, `data-lifecycle-conventions`; AEAD pin in data-protection; the annual
  standards-review cadence in `global-skills/README.md`.
- **Autonomy hardening** (#39). Zero-prompt runs between checkpoints: notify hooks (toast),
  WebFetch domain guard, registry wrapper, command allowlists. Operator-side steps (PAT, WSL2
  proxy, canary) tracked separately.

## Findings that drove the work (the evaluation evidence)

Compressed from the M2 run-#1 audit (`plan/pipeline-june-analysis.md` §8 keeps the full record,
including the M3/M4 findings that followed):

- **F1** — a perf test verified a *weaker condition* than its criterion (p95 at concurrency 1 vs
  "under 100 req/s") yet scored `covered:true` → PR G's perf-pairing floor; truly closed by PR N's
  real k6 campaign.
- **F2** — a GitHub-created initial commit broke the greenfield currency anchor → PR F bootstrap
  fixes (+ the Node `.gitignore` follow-up).
- **F3** — the deployment agent could re-anchor the reviewed change hash itself → PR I binds the
  gate to the human-approved hash.
- **F4** — `maxTurns` starvation, invisible in telemetry → PR F bumps; log-run visibility work.
- **F5** — line coverage gated while branch coverage (70.97%) rode along ungated → surfaced by
  PR G, deliberately not gated.
- **F6** — placeholder `ran_at`, non-terminal `loop-state` → PR G6's enforcement hooks.
- **M3/M4 class (2026-07-07/09)** — gates green over wrong work (a criteria count contradicted by
  its own `by_id`; inert STRIDE mechanisms verified "present"; scan counts never recounted) → #34's
  deterministic recomputation + efficacy questions + `docs/finding-ledger.md` so an escaped class
  becomes a permanent check.
