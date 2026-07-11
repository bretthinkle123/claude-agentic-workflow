# Roadmap — what's still open

> Forward-looking only. Everything shipped lives in `docs/pipeline-changelog.md` (design-unit view)
> and `docs/pr-history.md` (PR-indexed view); the current-state reference is
> `docs/system_architecture.md`. Deep assessment behind this sequencing:
> `plan/pipeline-june-analysis.md` (§7 delivery lifecycle, §10 master roadmap — historical).

## Orientation — the two "10/10" definitions (both reached)

- **10/10 scaffolder** — produces trustworthy PRs a human can confidently merge = PRs F–J.
  **Reached 2026-07-01.**
- **10/10 fully-functional pipeline** — also builds, ships, and operates production software =
  Track 2 PRs L–P. **Reached 2026-07-06.**

What remains is therefore *not* on either critical path: execution proof on real apps,
platform-bound adapters, and operator-side provisioning.

## Open items

### Execution proof (the M2 rule: nothing counts until a real run)

- **Track-2 delivery half, first true end-to-end run.** `pipeline-ci` → `build-provenance` →
  `deploy` (staging → canary) → load campaign → DR drill are lint/simulation/bootstrap-verified but
  need a supervised first run on a real containerized app with AWS environments. DAST Layers 2/3
  (`dast-staging.yml`) and CodeQL execute for real at the same moment. Specs:
  `plan/ci-merge-gate-plan.md`, `plan/delivery-operations-plan.md`,
  `plan/environments-delivery-plan.md`, `docs/dast-plan.md`.
- **Next real app runs.** The engine's validation era (#34) closed the M3/M4 findings; the next
  feature runs are application builds (photography app first, then the red-team/pentest app goal),
  which double as the delivery half's execution proof.

### Operator-provisioned (external to the repo)

- **Autonomy hardening, operator side** — the engine half merged (#39: notify hooks, WebFetch
  guard, registry wrapper, allowlists); remaining are operator steps: scoped GitHub PAT, WSL2
  sandbox, egress proxy bring-up (EG Layer 2, `plan/egress-control-plan.md`), and a canary run.
- **macOS-bound iOS work** — the honest gate adaptation for native iOS (`xcodebuild` smoke,
  Semgrep-Swift + Swift SCA = SB slice 4, `xccov` coverage) needs a macOS runner + a real iOS
  project; until then iOS runs self-stamp reduced assurance. `plan/ios-swiftui-target-plan.md`.
- **FE Layer-4 capture** — the Playwright visual-regression capture is runtime-bound (browser
  install); the deterministic budget compare is already in place.

### Candidate designs (specced, not scheduled)

- **Code-quality audit stage** — a dedicated post-implementation code-audit pass;
  `docs/pipeline-code-quality-audit.md` is the design.
- **Refinement loops** — candidate iterative-improvement designs in
  `docs/pipeline-refinement-loops.md` (the implemented planning revision loop is in the changelog).
- **DAST Layer 5** — Nuclei templated scan, advisory, any time (`docs/dast-plan.md`).
- **Agent-eval corpus growth** — extend `tests/agent-evals/` planted-defect trees as new finding
  classes land in `docs/finding-ledger.md` (the #34 mechanism: an escape caught once becomes a
  permanent check).

### Deferred workstreams (deliberate, tracked in memory)

- **Front-end deep-dive** — design-review/a11y/Figma beyond the shipped design-spec stage; a
  dedicated later PR.
- **Production-debugger expansion** — beyond the shipped read-only triage agent
  (`plan/triage-agent-plan.md`): Sentry-driven fix loops remain human-initiated by design.

## Standing cadences

- **Annual skill standards review** — next due 2027-07 (`global-skills/README.md`).
- **Continuous vuln re-scan + Renovate** — weekly, per project (PR P).
- **Monthly DR drill** — per deployed project (`dr-drill.yml`).
