# Plan — delivery & operations (PRs M–P): from a green merge to a live, operated app

> **Status: BUILT — merged as PRs #29 (M), #30 (N), #31 (O), #32 (P), 2026-07-06.** The "last 40%"
> (`pipeline-june-analysis.md` §7
> Phases 2–5, §10 rows M–P). Turns a gate-verified merge commit into a signed artifact, deploys it
> through staging to production with progressive delivery and automated rollback, observes it in
> operation, and validates it holds under load with a tested recovery path. Chains onto
> `plan/ci-merge-gate-plan.md` (PR L, required first). Companions: `plan/dast-plan.md` (targets the
> staging env PR N builds), `docs/pipeline-deployment-targets.md` (existing recipes this operationalizes),
> and the skills `iac-conventions`, `deployment-checklist-and-rollback`, `logging-conventions`,
> `containerization-conventions`, `secrets-management`, `ddia-patterns` (all already shipped).
>
> **Label legend:** tags like **S2/S3/S4, R1/R2/R3, A3** are short local labels carried over from an
> in-chat pipeline audit (2026-07-05) that was never committed — they resolve to no file in this
> repo. Each is named in place wherever it appears (S2 continuous vulnerability management ·
> S3 WAF/edge protection · S4 container hardening · R1 feature flags · R2 graceful shutdown ·
> R3 synthetic monitoring · A3 mobile crash reporting); read the name, treat the tag as a label.

## Goal, honest scope & mental model

**These are predominantly per-project infra/CD the pipeline SCAFFOLDS, plus a few skills — not new
pipeline agents.** The pipeline stays the authoring + pre-merge-review brain; PRs M–P extend it
*rightward across the merge boundary* via generated `.github/workflows/`, generated `infra/`
(Terraform the pipeline already knows how to write), and conventions. The one genuinely new
*pipeline* surface is the optional read-only triage agent in PR O — and it re-enters the normal
pipeline, never auto-deploys. Nothing here breaks the fresh-context / file-handoff / deterministic-gate
invariants.

**Honest bar.** "Deployed" ≠ "reliable at scale." Each PR closes a specific §3/§4 gap; the sequence
is strictly dependency-ordered (each presupposes the prior); and each names its residual rather than
asserting a property it can't prove.

---

## PR M — build + artifact provenance (§7 Phase 2)

**Closes:** "the artifact isn't immutable or traceable to the commit." **Depends on:** L, and PR I's
`generate-sbom.sh`.

- **Reproducible build → registry.** Generated workflow (on green `main`) builds the image, tags it
  by commit SHA (immutable; never `latest` in the deploy path), pushes to a registry (ECR default,
  per the AWS posture).
- **Provenance + signing.** Attach the existing CycloneDX SBOM; **cosign** sign the image (keyless
  via the same OIDC identity, no long-lived keys — mirrors `iac-conventions`); generate SLSA
  build provenance attestation. The deploy step (PR N) **verifies the signature** before rollout —
  an unsigned/mismatched image is refused.
- **Pipeline change:** a `delivery-conventions` skill section (build/tag/sign rules) + the workflow
  template extension. **Container hardening check** (non-root, read-only rootfs, pinned base,
  dropped caps) lands here as a hadolint/dockle CI step — the audit's S4 item. **M.**

## PR N — environments + progressive delivery + real load (§7 Phase 3 + M3)

**The biggest single jump toward live users.** Closes: no staging, no executed migrations, no
canary, no rollback automation, and §3-#3 "scalable is asserted, never validated." **Depends on:** M.
**Effort: L** — the heart of Track 2.

- **Staging that mirrors prod.** `infra/` Terraform (the pipeline authors it; `iac-conventions` +
  `infra-validate.sh` already gate it locally; here it is *applied*, not just planned) stands up a
  prod-shaped staging env. Remote state per the existing S3/DynamoDB convention.
- **Executed migrations, safely.** The migration the testing agent round-tripped locally is now
  **run against staging first**, with the **backup-before-migrate + verify-restore** step from
  `deployment-checklist-and-rollback` (already speced) made executable, and **expand/contract**
  ordering (already the skill's preference) enforced for zero-downtime.
- **Progressive delivery + auto-rollback.** Canary or blue/green (decide per app; default: ECS
  blue/green via CodeDeploy, or ALB weighted target groups for simpler cases — the
  `delivery-conventions` skill carries the decision rubric, same style as the containerization
  Docker-vs-serverless rubric). **Automated health/SLO-breach rollback** — the deploy watches the
  reborn `post-deploy-check.sh` (implemented as a CI job in PR L) + error-rate/latency alarms; a
  breach auto-reverts to the last-good SHA.
- **Real load (M3).** Upgrade testing's perf mode from smoke-sized to an **optional sustained-load
  campaign** (`LOAD_PROFILE=campaign`, k6) run **against staging, not localhost**, posting
  p95/throughput vs. the acceptance budget. This is where the F1 perf-completeness gate finally
  gets *real* numbers instead of serial-loop ones. A **failover test** (kill an AZ/task, assert the
  ASG/service recovers) proves multi-AZ instead of Checkov-asserting it.
- **Edge protection (audit S3):** CloudFront + AWS WAF managed rules + Shield baseline, authored
  into `infra/` — the deployed counterpart to the app-level `api-edge-conventions` rate limiting.
- **Feature flags (audit R1):** an env/SSM-backed flag convention (no vendor at this scale) so
  canaries can ship dark and a bad feature is killed without a redeploy — the enabler that makes
  progressive delivery safe. **Graceful shutdown / readiness-vs-liveness split (audit R2)** folds
  into the deploy conventions here (drain on SIGTERM so a rollout doesn't drop in-flight requests).

## PR O — observability + operations (§7 Phase 4; the production-debugger workstream)

**Closes:** deployed-but-blind; also a **security detection** control (you can't tell you're being
attacked with only pre-merge prevention). **Depends on:** N (can only observe what's deployed).
**Effort: L.**

- **Error tracking + tracing shipping for real.** Sentry SDK (backend + frontend/mobile), the
  structured logs + OTel trace IDs that `logging-conventions` already specifies now actually
  exported to CloudWatch/X-Ray, source-map/symbolication (incl. **mobile crash reporting +
  dSYM/mapping upload** — audit A3), release-tagged to the deploy SHA.
- **Alerting + SLOs.** SLO definitions + burn-rate alarms; the alarms that PR N's auto-rollback
  consumes. **Synthetic monitoring (audit R3):** scheduled probes of the top user journeys — the
  grown-up form of `post-deploy-check.sh`.
- **Optional read-only triage agent.** A new pipeline surface, tightly bounded: give the debugging
  agent Sentry MCP (read-only) to pull one incident's stack/breadcrumbs and **propose a fix that
  re-enters the normal pipeline** (planning → … → the M5 human checkpoint). **Never auto-deploys,
  never writes to prod.** This is the deferred production-debugger workstream, kept honest by the
  same gate discipline as everything else.

## PR P — scale validation + DR (§7 Phase 5)

**Closes:** the availability/data-loss gap before real users depend on it. **Depends on:** N.
**Effort: M.**

- **Campaign-scale load** beyond N's regression-sized run — sustained, to find the actual ceiling +
  the autoscaling policy firing.
- **Backup/restore + DR drill.** An *executed* restore (a backup you've never restored is a hope,
  not a backup — the skill already says this; here it's drilled), a documented RPO/RTO, and a
  failover rehearsal.
- **Cost guardrails.** Budget alarms + a per-env cost tag rollup (the tagging convention already
  exists in `iac-conventions`), so scale doesn't silently become a bill.

---

## Continuous vulnerability management (audit S2 — spans M–P, name it here)

A shipped app scanned only at authoring time rots: today's clean pinned dep is next month's CVE and
nothing re-checks it. Add, as part of this workstream (it needs the app repos M–P produce):
**Renovate/Dependabot** on each generated app repo + a **scheduled (weekly) OSV/Trivy re-scan of
`main`** with alerting, whose update PRs **flow back through the normal pipeline gates**. Small
(template + convention) but it's the difference between "secure at ship" and "stays secure." Belongs
in the `ci-conventions`/`delivery-conventions` skills. **S.**

## Implementation-readiness (honest, per PR)

This doc is a **plan-of-plans** at milestone altitude — deliberately, because specifying N/O/P in
build detail now would be specifying against churn (the same reason `pipeline-june-analysis.md`
gives for deferring DOC). Readiness differs per PR:

- **PR M — ready to build on go-ahead.** Scope is bounded (build → sign → push → attest), the
  tools are named and real (cosign keyless-OIDC, GitHub SLSA attestations, hadolint/dockle), and it
  reuses shipped pieces (`generate-sbom.sh`, the OIDC identity). No open design question.
- **PR N — NOT build-ready; needs its own plan doc at kickoff.** It bundles five heavy, coupled
  decisions (staging IaC shape, migration executor, canary-vs-blue/green mechanism, load harness,
  WAF/edge) — each an implementation choice, not a detail. Write `plan/environments-delivery-plan.md`
  when N starts, the same way this workstream got the CI doc first.
- **PR O — NOT build-ready; the triage agent needs a dedicated design.** A new pipeline surface
  (read-only Sentry MCP, re-enters the pipeline, never auto-deploys) deserves the same threat-model
  care K applied to the engine. The observability wiring (Sentry/OTel/alarms) is per-project infra
  and is closer to ready; the *agent* is not.
- **PR P — ready in outline, low open-question surface**, but presupposes N's env exists, so it
  can't start earlier regardless.

Net: **M can start the moment L is green; N/O each get a short plan doc first** (they are where the
real design work lives), matching how every prior workstream in this repo was built.

> **Readiness audit (2026-07-05) — verified against the live codebase:** PR M's named inputs are
> real and shipped — `generate-sbom.sh` exists (in **`global-hooks/`**), the OIDC/no-long-lived-keys
> posture is already the `iac-conventions` rule, and `post-deploy-check.sh` exists as the hook PR L
> retires into a CI job. **Post-draft status change:** `plan/dast-plan.md` **Layer 1 is now BUILT**
> (PR #26), so the DAST-in-CI slot referenced here re-homes two existing scripts rather than
> awaiting new ones; DAST L2/L3 still wait on N's staging, as stated. The per-PR readiness verdicts
> above (M ready · N/O need kickoff plan docs · P outline-ready) were re-checked and stand — no
> assumption in this doc has been invalidated by the DAST/STORE work.

## Sequencing

Strict dependency order: **L → M → N → (O, P, DAST-L2/3 in parallel)**. Do N *through a real app*
(ledgerly or the red-team app), not abstractly — the M2 rule; Track 2 against a real repo will
surface F1-class surprises the same way run #1 did. S2 (Renovate) can land as soon as M produces the
first deployable repo.

## Non-goals

- **Not new gate hooks / no `loop-exit` change** — the local invariant is untouched; this is CI/CD +
  infra the pipeline scaffolds, plus the read-only triage agent.
- **Not multi-cloud** — AWS default (matches the whole repo); GCP/Cognito stay in `pipeline-alternatives.md`.
- **Not the app-store delivery path** — that's the mobile sibling (`plan/store-compliance-plan.md`
  for the gate; a Fastlane/Gradle *delivery* row for the upload) and depends on the macOS runner.
- **Not auto-remediating prod** — the triage agent proposes; humans + the pipeline approve.

## Tie-in

Chains onto `plan/ci-merge-gate-plan.md`; operationalizes the recipes in
`docs/pipeline-deployment-targets.md`; consumes `generate-sbom.sh` (PR I) and every infra/logging/
deploy skill already shipped; provides the staging target `plan/dast-plan.md` needs. Update
`pipeline-june-analysis.md` §10 rows M–P (and add the named audit items — continuous vuln, WAF/edge,
feature flags, graceful shutdown, synthetics — as sub-bullets)
when each moves from spec to build.
