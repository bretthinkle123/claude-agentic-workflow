# IaC security baseline

The per-resource checklist the security agent (Checkov) enforces over `infra/`.
A violation of an item marked **critical** maps to `critical_count`; the rest are
warnings unless project policy raises them.

## Identity & access (Elevation of Privilege)

- **critical** — no wildcard `Action: "*"` or `Resource: "*"` in IAM policies.
- **critical** — no inline admin/`*:*` managed policies on deploy roles.
- Permission boundaries set on roles that can create other roles.
- Least-privilege: the deploy role is scoped to exactly the stack's services.

## Data protection (Information Disclosure)

- **critical** — no public S3 buckets (Block Public Access on; no public ACL/policy).
- **critical** — encryption at rest enabled (S3 SSE, RDS/EBS encryption, DynamoDB SSE).
- **critical** — no secrets in state or `.tfvars`; use Secrets Manager / SSM.
- **critical** — RDS instances provisioned for multi-tenant or user-scoped data must
  have RLS enabled at the schema level (enforced via a post-provision migration, not
  Terraform alone). Confirm in the security scan that no application role carries
  `BYPASSRLS`.
- TLS enforced in transit (bucket policies deny non-TLS; ALB redirects to HTTPS).

## Network exposure (Tampering / DoS)

- **critical** — no `0.0.0.0/0` ingress except on intended public load balancers,
  and never to admin ports (22, 3389, database ports).
- Security groups scoped to the minimum CIDRs/ports the workload needs.
- VPC flow logs / resource-level logging enabled.

## Audit & resilience (Spoofing / Repudiation)

- CloudTrail enabled and logging on provisioned resources.
- Backups / retention configured for stateful resources (RDS snapshots, S3
  versioning where data loss matters).
- Deletion protection on production databases.

## Production scale (Availability — only when the stack runs long-lived compute)

Applies when `infra/` provisions a service that must **stay available** (an
ASG / ECS service / managed runtime fronting user traffic) — not a one-off job or
a static bucket. Most are Availability checks Checkov does not rate critical by
default, so they are **surfaced at the human checkpoint via `infra-plan.txt`**;
the deterministic ones (Multi-AZ RDS, deletion protection) ride Checkov.

- **Multi-AZ** — compute and the managed data tier span ≥ 2 Availability Zones
  (ASG across per-AZ subnets; RDS Multi-AZ; cache with a cross-AZ replica).
- **Auto-scaling** — a target-tracking policy (CPU or request-count-per-target)
  with sane `min`/`max`, never a fixed single instance for a user-facing service.
- **Health checks** — an ALB target-group health check wired to a real app
  **readiness** endpoint; unhealthy targets are drained, not served.
- **No single point of failure** — `desired_count` / `min_size` ≥ 2 behind the
  load balancer for a production service.
- **Graceful deploy** — rolling or blue/green with connection draining so a
  deploy does not drop in-flight requests.

## Drift

- Remote state locked (DynamoDB) so concurrent applies can't corrupt state.
- `terraform plan -detailed-exitcode` in CI confirms no out-of-band drift.
