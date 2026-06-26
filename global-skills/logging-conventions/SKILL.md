---
name: logging-conventions
description: Standard structured-log field set, PII redaction rules, log-level semantics, the structlog (Python, default) / Pino (JS) logger facade, OTel trace-ID propagation, and the AWS CloudWatch/X-Ray backend. Invoke when a feature produces observable events.
---

# Logging conventions

Invoke this when a feature produces observable events (errors, user actions,
state changes). Default logger is **structlog (Python)**; the Pino/JS variant and
GCP backend live in `pipeline-alternatives.md`. Buildable default code is in
`scaffold/` (`logger.py` + request `middleware.py`).

## The logger-facade rule

**One configured logger instance, imported everywhere.** Never instantiate a
second logger elsewhere. It redacts secrets/PII centrally. All modules import
`get_logger()` from `logging/__init__.py`.

## Standard fields

Always present: `timestamp`, `level`, `service`, `message`. Request-scoped (on
logs within a request): `traceId`, `requestId`, `userId`, `operation`. Plus
`duration`/`statusCode` on completion logs and `error.type`/`error.message`/
`error.stack` on error logs.

| Field | Rule |
|---|---|
| `timestamp` | Set by the logger, never the caller (ISO 8601) |
| `level` | `debug`/`info`/`warn`/`error`/`fatal` |
| `userId` | **Hashed/opaque only** — never raw email or PII |
| `operation` | What was attempted: `user.login`, `order.create` |
| `error.stack` | **Server-side only** — never sent to the client |

## Log levels

| Level | When |
|---|---|
| `debug` | Local dev only — internal state. Disabled in production |
| `info` | Normal ops — requests completed, jobs run, users authenticated |
| `warn` | Recoverable — retried a call, rate-limit approaching, deprecation |
| `error` | Something failed, system continues — a request/job errored |
| `fatal` | System cannot continue — unrecoverable, process crash |

## traceId resolution order

1. Active OTel span (`trace.get_current_span()`) when the OTel SDK is wired.
2. Else the cloud trace header — AWS `X-Amzn-Trace-Id` `Root=` segment (default
   cloud) or GCP `x-cloud-trace-context` first segment.
3. Else a generated UUID.

## Audit event categories — what must be logged

Every application must produce structured log entries for all five categories.
Omitting one is a security gap. Log every **attempt** — failures and denials
matter as much as successes.

| Category | Examples |
|---|---|
| **Authentication events** | Login (success/failure), logout, token refresh, MFA challenge, password reset |
| **Access control events** | Permission check (granted/denied), role assignment/removal, resource authorization |
| **CRUD events** | Create, Read, Update, Delete on every significant resource (users, files, orders, configs) |
| **Admin events** | Config changes, user management by an admin, feature flag changes, schema migrations |
| **User security events** | Account lockout, suspicious activity flag, credential change, session revocation |

## 5W+H completeness check

Every audit-significant log entry must be able to answer all six questions:

| Question | Field(s) |
|---|---|
| **Who** | `userId` (hashed/opaque), `sessionId`, `actorRole` |
| **What** | `operation` (verb.resource: `user.delete`, `file.read`), `resource_id`, `action` (`create`/`read`/`update`/`delete`) |
| **When** | `timestamp` (ISO 8601, set by the logger — never the caller) |
| **Where** | `service`, `requestId`, `traceId`, `ip_address` (if applicable) |
| **Why** | `reason` or `trigger` where deterministic (e.g., `"session_expired"`, `"rate_limit"`) |
| **How** | `method` (HTTP verb), `endpoint`, `user_agent` (if applicable) |

For automated system events (cron, background workers), `userId` should be the
system identity (e.g., `"system:scheduler"`) — never omitted.

## Immutability — write once, read many

Logs must not be alterable or deletable after they are written:

- **CloudWatch Logs (default):** Set a retention policy on every log group
  (never indefinite). Apply a resource-based policy that **denies**
  `logs:DeleteLogGroup`, `logs:DeleteLogStream`, and `logs:PutRetentionPolicy`
  to all principals except a dedicated ops role. This prevents application code
  or a compromised deploy role from erasing evidence.
- **Audit log group:** Keep audit events in a **separate log group** from
  operational logs so stricter retention and IAM policies apply only where
  needed.
- **Long-term archive:** For compliance-grade audit trails, ship logs to **S3
  with Object Lock** (WORM) enabled. Use Governance or Compliance mode per your
  retention requirements. Declare in Terraform with `object_lock_enabled = true`.
- **Never** log to a writable local file in production — no rotation scheme
  makes a local file tamper-proof.
- Application code must **never** hold `logs:DeleteLogGroup`,
  `logs:DeleteLogStream`, or `s3:DeleteObject` on the audit log bucket.

## PII rules (non-negotiable)

- `userId` is always hashed/opaque — never raw email, name, or phone.
- Never log passwords, tokens, API keys, session cookies, or card data.
- Scrub sensitive fields from request bodies before logging.
- Logs that satisfy the 5W+H check must do so **without** including PII — use
  hashed IDs, opaque references, and event codes rather than raw user data.

## Validation failure logging

Log input **and** output validation failures — they are reliable attack signals
(legitimate users rarely hit validation boundaries at volume):
- Input: malformed requests, out-of-range values, unexpected types → `warn`
- Output: schema mismatches, unexpected DB result shapes → `error`
- High-frequency failures from a single `userId`/IP → flag for alerting

## Alerting

Wire CloudWatch Alarms → SNS for:
- Repeated auth failures from a single IP or userId (brute-force / credential stuffing)
- Spike in access-denied events
- Any `fatal` log in production
- Admin actions outside business hours

Alarm config lives in `infra/`; thresholds are project-specific.

## Retention policy

| Tier | Minimum | Storage |
|---|---|---|
| Hot (queryable) | 3 months | CloudWatch Logs |
| Cold (archived) | 9 months | S3 Glacier / Object Lock |
| **Total minimum** | **12 months** | — |

Set CloudWatch log group retention to 90 days; export to S3 nightly for cold
storage. Regulated environments (HIPAA, SOC 2) may require longer — satisfy the
strictest applicable framework.

## Centralized log management

All services must ship logs to a **single queryable backend** (CloudWatch Logs
Insights by default; forward to a SIEM via Kinesis Firehose for regulated
environments). Cross-service incident correlation requires logs from every
service to be in one place with a shared `traceId`.

## Compliance framework quick-reference

| Framework | Key logging obligation |
|---|---|
| PCI DSS 4.0 | 12-month retention (3 hot); log all access to cardholder data |
| HIPAA | Audit controls for all PHI access; retain 6 years |
| SOC 2 | Logging of security events; evidence of monitoring |
| ISO 27001 | Event logging + log protection + admin/operator logs |

## Log integrity

Write-once (S3 Object Lock) prevents deletion. For compliance audits that
require tamper-evidence, also enable **CloudWatch Logs integrity validation**
(`aws logs start-query` with `--query-string` hash verification) or use
hash-chained log exports. Declare in `infra/`.

## Backend (AWS — default)

Structured JSON on stdout is ingested into **CloudWatch Logs** automatically on
ECS/Lambda — no app change. For traces/metrics, point the OTel SDK at a local
**ADOT** collector (`OTEL_EXPORTER_OTLP_ENDPOINT`), which forwards traces to
**X-Ray** and metrics to **CloudWatch**. Log groups, alarms, X-Ray write
permissions, and S3 archive bucket are declared in `infra/` (Terraform).
