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

## Drift

- Remote state locked (DynamoDB) so concurrent applies can't corrupt state.
- `terraform plan -detailed-exitcode` in CI confirms no out-of-band drift.
