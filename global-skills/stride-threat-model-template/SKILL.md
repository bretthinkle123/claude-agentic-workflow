---
name: stride-threat-model-template
description: STRIDE worksheet — trust boundaries, per-category threat prompts, and the severity rubric appended to plan.md.
---

# STRIDE threat-model template

Append a `## Threat Model` section to `plan.md`, scoped to **this feature** only.
Method: STRIDE (Shostack, *Threat Modeling*). A worked example for a sample auth
feature is in `examples.md` (sibling).

## Step 1 — Assets and trust boundaries

List the assets the feature introduces or touches (data, tokens, endpoints,
resources) and the trust boundaries it crosses (client↔server, service↔service,
app↔datastore, app↔cloud control plane). Threats live at boundaries.

## Step 2 — Enumerate threats (fill this table)

| Category | Asset / Boundary | Attack vector | Severity (H/M/L) | Mitigation |
|---|---|---|---|---|

Use 1–2 trigger questions per category:

- **Spoofing** — Can an actor pretend to be a user/service? Is every request
  authenticated at the boundary?
- **Tampering** — Can data in transit, at rest, or in a request be modified?
  Are inputs validated and integrity-checked?
- **Repudiation** — Can an actor deny an action? Is there sufficient audit
  logging (who did what, when)?
- **Information Disclosure** — Can data leak (PII in logs/errors, over-broad
  responses, unencrypted storage)?
- **Denial of Service** — Can the feature be exhausted (unbounded input, missing
  rate limits, expensive queries)?
- **Elevation of Privilege** — Can a low-privilege actor gain higher access
  (missing authorization checks, over-permissioned roles)?

## Step 3 — Severity rubric (impact × likelihood)

- **High** — high impact (data breach, account takeover, privilege escalation)
  AND a plausible vector. Must be mitigated before ship.
- **Medium** — meaningful impact but constrained likelihood, or limited impact
  with an easy vector. Mitigate or consciously accept.
- **Low** — minor impact or remote likelihood. Note and move on.

## Step 4 — Accepted risks / out of scope

List threats deliberately not addressed in this feature and why (accepted risks).
Be explicit — an unstated gap reads as an oversight at the human checkpoint.

## Cloud trigger (when the change includes `infra/`)

Also enumerate the cloud attack surface (see *Threat-model additions for cloud
infrastructure* in the plan):
- **Elevation of Privilege** — over-permissioned IAM, wildcard `Action`/`Resource`,
  missing permission boundaries.
- **Information Disclosure** — public S3 buckets, unencrypted data at rest,
  secrets in state/`.tfvars`, over-broad security-group ingress.
- **Tampering / DoS** — unrestricted exposure (`0.0.0.0/0`), missing
  resource-level logging, absent backups/retention.
- **Spoofing / Repudiation** — no CloudTrail/audit logging on provisioned
  resources.
