# Attack-surface delta — Meterly feature 3 (read-only Usage Dashboard)

Best-effort hint for the security agent's diff reconciliation, scoped to this
change only. Feature 1/2's surface (API-key auth, Tier-1/Tier-2 throttles,
RDS/Redis/Secrets Manager/Sentry/OTel trust boundaries, `api_keys`/`events`/
`usage_rollup` storage, IAM) is **unchanged** and not re-listed here — see
the prior `surface-delta.md` history for that baseline. This file covers
only what feature 3 adds: a served HTML page, a same-origin BFF, and the
server-held `dashboard-reader` credential path.

## New entry points

- `GET /dashboard` — `src/api/routes/dashboard.py:29` — serves the static
  SCREEN-1 HTML shell via a fixed `FileResponse` (no user-controlled path,
  no query/path input). Unauthenticated at the viewer boundary (accepted
  risk S-D1/Q2 — see plan §Auth), inherits the Tier-1 IP+route throttle.
- `GET /dashboard/static/dashboard.css`, `GET /dashboard/static/dashboard.js`
  — `src/api/routes/dashboard.py:35,41` — fixed static asset routes, same
  posture as `/dashboard`.
- `GET /dashboard/api/config` — `src/api/routes/dashboard.py:47` — returns
  non-secret dropdown allowlists + the real deployment `environment`. No
  input, unauthenticated at the viewer boundary, Tier-1 throttled.
- `GET /dashboard/api/usage-series` — `src/api/routes/dashboard.py:60` — the
  BFF data route; the **one** new untrusted input surface (`customer_id`,
  `metric`, `granularity` query params), validated by
  `UsageSeriesQueryParams` (`src/api/schemas/dashboard.py:19`) with anchored
  allowlist regexes + allowlist-membership + a `Literal["hour","day"]`
  enum (`month` is excluded — Q1 human decision: hour+day live, month
  disabled client-side only). Unauthenticated at the viewer boundary,
  Tier-1 throttled (no Tier-2 — there is no client principal).

## New trust boundaries

- **Browser <-> served page/BFF** — the app's first browser-rendered surface
  and its first unauthenticated-at-the-viewer HTTP boundary. Mitigated by:
  the reader key's single-tenant/read-only/least-privilege blast radius, the
  `customer_id`/`metric` allowlists (bounds enumeration), the inherited
  Tier-1 IP throttle, and a documented expectation that `/dashboard` sits
  behind network/edge access control in a real deployment (accepted risk
  S-D1/Q2, not enforced in-app).
- **BFF -> Secrets Manager (`get_dashboard_reader_principal`,
  `src/auth/dashboard_reader.py:38`)** — a new runtime read of a dedicated
  `dashboard-reader` secret, memoized 300s. No new outbound third-party call
  — same AWS Secrets Manager boundary the DB-URL fetch already crosses.
- **BFF -> `get_usage` in-process (`src/services/dashboard_service.py:196`)**
  — not a new boundary (reuses feature 1's `get_usage`/RLS path), but now
  driven by a server-resolved principal instead of a client-presented one,
  with a bounded fan-out (11 reads for `hour`, up to 264 for `day`,
  concurrency-capped at 10 — `_MAX_CONCURRENT_READS`).

## New data flows / sinks

- **DOM sink (`src/web/static/dashboard.js`)** — usage values, window
  labels, and deltas are written to the browser DOM for the first time.
  Every write uses `textContent`/`createElement`/`classList` — no
  `innerHTML`, no inline event handlers, no `eval` (verified: grep of the
  shipped file finds no `innerHTML`/`eval(` outside of comments). Backed by
  the page's strict CSP (`script-src 'self'`, no `unsafe-inline`/`unsafe-
  eval`) added in `src/api/middleware.py`.
- **New logged event** — `dashboard.usage_series` (`src/services/
  dashboard_service.py:222`) — `userId` is the reader's own opaque
  `api_key_id` surrogate; `granularity`/`windows`/`state` only; **no raw
  `customer_id`** is ever passed to the logger (belt-and-suspenders on top
  of the existing structlog redaction processor, which already lists
  `customer_id`).
- **No new stored field for existing entities.** This feature persists
  nothing new for `events`/`usage_rollup` — it only *reads* the existing
  table via the existing `get_usage` repository query
  (`src/repositories/usage_repo.py`, unchanged). The one new stored secret
  is the `dashboard-reader` credential itself:
  - **Field:** `dashboard-reader` API key plaintext.
  - **Class:** `credential`.
  - **At-rest mechanism:** not stored in the app; held in AWS Secrets
    Manager (`aws_secretsmanager_secret.dashboard_reader`,
    `infra/modules/data/main.tf`), **KMS envelope-encrypted** with the
    existing data-tier CMK (`aws_kms_key.data`); its Argon2id hash (not the
    plaintext) lands in the existing `api_keys` table via
    `scripts/seed_api_key.py`, same as every other key. Terraform provisions
    the secret *container* only (a placeholder `secret_string` with
    `ignore_changes`); the real plaintext is written out-of-band by
    `scripts/seed_api_key.py --write-to-secret`, never in `*.tfstate`/
    `*.tfvars`.
- **`customer_id` newly exposed to the browser** (already `personal`-classed
  from feature 1; unchanged at-rest mechanism — RDS SSE/KMS CMK). New
  browser-facing controls added: `Cache-Control: no-store` on `/dashboard`
  and every `/dashboard/api/*` response (`src/api/middleware.py`), and it is
  never logged raw (see above).

## New privilege / authz surface

- **`dashboard-reader` principal (`src/auth/dashboard_reader.py`)** — a new,
  dedicated, least-privilege, read-only, single-tenant `AuthenticatedPrincipal`
  resolved server-side from Secrets Manager and verified through the exact
  same `verify_api_key` Argon2id path a browser-presented key would use.
  Memoized 300s (`_TTL_SECONDS`) so Argon2id runs once per TTL, not once per
  fan-out read. It carries **no elevated privilege** over an ordinary API
  key — same tenant scoping (`api_key_id`), same PostgreSQL RLS backstop.
- **ECS task role (`infra/modules/compute/main.tf`)** — one new
  `ReadDashboardReaderSecret` statement: `secretsmanager:GetSecretValue`,
  **resource-scoped to exactly the reader-secret ARN**, no wildcard
  `Action`/`Resource`. Reuses the existing `DecryptDataKey` KMS grant (the
  new secret is encrypted with the same CMK) — no new `kms:*` grant needed.
- **No change** to `require_api_key`, Tier-2 per-key throttling, or any
  `/v1/*` route's authorization — feature 1/2's authenticated surface is
  untouched.

## Deviations from the plan worth flagging to security/testing

- **`infra/envs/staging/main.tf` and `infra/envs/prod/main.tf` were also
  modified**, wiring `dashboard_reader_secret_arn = module.data.
  dashboard_reader_secret_arn` into each env's `module "compute"` block. The
  plan stated these need "no change," but `dashboard_reader_secret_arn` is a
  required compute-module variable with no default — leaving the two real
  deploy-target roots unwired would fail `terraform validate`/`plan` for
  both. This mirrors the existing `database_secret_arn` wiring pattern
  already present in both files; no new variable/default/topology was
  introduced beyond what the plan's `infra/main.tf` change already implied.
- No other deviation. `month` granularity is excluded from
  `UsageSeriesQueryParams`'s enum (422 if requested) and disabled
  client-side with a visible affordance (`aria-disabled` + tooltip), per the
  human decision on Q1 — hour + day ship live.
