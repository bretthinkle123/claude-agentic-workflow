---
name: brett-profile
description: "Who Brett is, his stated preferences, and how to work with him"
metadata:
  type: user
---

Brett is a self-described beginner building his first serious agentic workflow on Claude Code.

**How to work with him:**
- Token-cost-conscious — respect token efficiency in every recommendation; call out the token tradeoff when it's relevant.
- Prefers thorough written reports/audits over quick takes when he asks for analysis.
- Does not want design decisions re-litigated. When a decision is settled and documented, treat it as settled.
- Default: no building until asked. Audit/prepare first, then propose, then build on approval.

**Default stack (use unless there's a good reason — flag the reason if deviating):**
- Cloud infra: AWS (Terraform, S3/DynamoDB state, OIDC roles)
- Auth: Firebase Auth (default, cloud-agnostic SaaS — no GCP infra); Amazon Cognito is the documented AWS-native alternative
- Backend: Python (structlog + firebase-admin scaffolds)
- Frontend: JavaScript
- Database: SQL (variant proposed by planning per project)
- MFA: Duo Mobile
- Logging: structlog (Python) / Pino (JS) + OpenTelemetry
- Errors: Sentry

See [[agentic-pipeline-project]] for the current project status.
