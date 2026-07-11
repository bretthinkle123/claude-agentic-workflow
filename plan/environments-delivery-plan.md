# Plan — environments + progressive delivery + real load (PR N kickoff)

> **Status: BUILT — merged as PR #30 (2026-07-06).** This is the doc
> `plan/delivery-operations-plan.md` requires before PR N starts. It converts N's milestone bullets
> into concrete, buildable choices, each with the alternative it rejects and why. Depends on PR M
> (signed artifact); provides the staging target `plan/dast-plan.md` L2/L3 needs. Everything here is
> **per-project scaffolding the pipeline authors** (templates + skills + `infra/` Terraform) — no new
> gate hooks, no loop-exit change, no new agents.

## The five decisions

### D1 — Staging IaC shape: one module set, two environment instantiations

`infra/` gains an environment axis, keeping the existing `iac-conventions` facade:

```
infra/
├── modules/            ← the real resources (service, db, network, edge) — written ONCE
├── envs/
│   ├── staging/main.tf ← thin instantiation: small sizing, single-AZ RDS allowed, no Shield
│   └── prod/main.tf    ← full sizing, multi-AZ, deletion protection, WAF+edge
```

- **Same modules, different `variables.tf` inputs** — staging mirrors prod *shape* (same service
  topology, same migration path, same LB/health wiring) at reduced *scale*. Shape-parity is what
  makes staging results transferable; scale-parity is what you pay for only in the load campaign.
- **Separate state per env** (two keys in the same S3 bucket + one DynamoDB lock table, per the
  existing remote-state convention). *Rejected:* Terraform workspaces — implicit, easy to apply to
  the wrong env; two explicit `envs/` dirs are greppable and diff-reviewable.
- **Staging auto-applies on green `main`** (a `workflow_run` job chained on PR L's CI); **prod
  applies only from the deploy workflow with a manual approval** (GitHub environment protection
  rule — the operator clicks; no TTY marker needed post-merge, the environment gate is the CI-side
  human checkpoint, consistent with `ci-merge-gate-plan.md`'s honest-scope table).

### D2 — Migration executor: a deploy-workflow job step, staging-first, backup-gated

Who actually runs `alembic upgrade head` (etc.) against a real database:

- **A dedicated job step in the deploy workflow**, running the app image's migration command against
  the target env **before** the new tasks roll, in this order: `snapshot → migrate staging →
  staging health/smoke → snapshot prod → migrate prod → progressive rollout`.
- Snapshot = the `deployment-checklist-and-rollback` backup-before-migrate step made executable
  (`aws rds create-db-snapshot` + wait), and the **restore path is verified in PR P's drill**, not
  assumed here.
- **Expand/contract stays a convention enforced upstream** (plan-audit flags a destructive
  migration paired with a same-release code dependency); the workflow adds the runtime guard:
  the migrate step runs the *old* image's healthcheck after expanding, so a contract-too-early
  fails in staging.
- *Rejected:* init-container/entrypoint migrations (races when multiple tasks start; ties schema
  change to task lifecycle) and one-off ECS RunTask (harder to sequence/gate in the workflow, no
  added safety at this scale).

### D3 — Progressive delivery mechanism: ALB weighted target groups first, CodeDeploy blue/green when criteria say so

- **Default: canary via ALB weighted target groups** driven by the deploy workflow: deploy the new
  task set at 10% weight → watch the health gate (D5's alarms + `post-deploy-check` job) for a
  soak window → 50% → 100% → retire old. Simple, no extra service, one rubric.
- **Escalation rubric** (carried in `delivery-conventions`, same style as the Docker-vs-serverless
  rubric): choose **ECS blue/green via CodeDeploy** when the app needs instant all-or-nothing
  cutover (schema-coupled releases), sub-minute automated rollback, or listener-level test traffic.
- **Auto-rollback is alarm-driven either way:** the workflow watches the CloudWatch alarms (5xx
  rate, p95 latency, target-health) during the soak; any alarm → weight back to 0/old task set
  redeployed → job fails loudly. The alarms are the same ones PR O's SLOs formalize — N ships the
  minimal three, O upgrades them to burn-rate SLOs.
- **Feature flags (R1):** env/SSM-Parameter-backed booleans read at request time (no vendor). The
  convention: risky features ship dark behind a flag, so "roll back" is usually "flip the flag,"
  not "redeploy." **Graceful shutdown (R2):** SIGTERM drain + readiness-vs-liveness split baked
  into `containerization-conventions` + the task definition template.

### D4 — Load harness: k6 in a workflow-dispatch job against staging

- **k6, run as a manually-dispatched (plus weekly scheduled) CI job against staging** — not in the
  PR path (a load campaign in every PR is cost without signal). `LOAD_PROFILE=campaign` ramps to the
  acceptance budget's stated RPS, sustained ≥ 10 min, thresholds encoded as k6 `thresholds` from
  `perf.budget.*` — the F1 fix finally measured for real: **p95 under load AND throughput**, the
  two numbers the local gate could only pair, not produce.
- The job posts results to the run summary + fails on threshold breach; a breach is a *finding*, not
  a deploy blocker (staging load runs after merge by construction — the fix re-enters the pipeline).
- **Failover test:** a second dispatch job kills one AZ's tasks (`aws ecs update-service` forced
  drain) mid-load and asserts recovery inside the health-gate window — multi-AZ *proven*, not
  Checkov-asserted.

### D5 — Edge/WAF: CloudFront + AWS managed rules in prod's module set only

- Prod env instantiates **CloudFront → WAF (AWS managed core + known-bad-inputs rule groups) → ALB**;
  Shield Standard is implicit. Staging skips CloudFront/WAF (cost; the app-level
  `api-edge-conventions` rate limiting still applies there, so staging isn't naked).
- *Rejected for now:* Shield Advanced (cost, personal scale), vendor WAFs. Residual, stated: WAF
  managed rules are generic — app-specific abuse cases remain the app's rate-limiting job.

## Build order (slices, each independently shippable)

1. **N1 — `envs/` split + staging auto-apply** (D1) — the enabler for everything.
2. **N2 — migration job + executable backup-before-migrate** (D2).
3. **N3 — canary + alarms + auto-rollback + flags/shutdown** (D3).
4. **N4 — k6 campaign + failover dispatch jobs** (D4).
5. **N5 — prod edge/WAF module** (D5).

Pipeline-side file touches: `delivery-conventions` skill (new; D2/D3 rubrics + rollback runbook),
`iac-conventions` (envs/ layout addendum), `containerization-conventions` (R2), workflow templates
under `templates/ci/` (deploy, load, failover), and `pipeline-june-analysis.md` row N on ship.
**Prove on a real app repo (M2 rule)** — ledgerly or the red-team app — not abstractly.

## Residuals (named, per the honest bar)

- Staging ≠ prod scale; only N4's campaign temporarily buys scale-truth.
- The soak window is a heuristic — a slow-burn regression can pass the canary gate; O's SLO
  burn-rate alarms are the real detector.
- Restore path unverified until PR P's drill executes it.
