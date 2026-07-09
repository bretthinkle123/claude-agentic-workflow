# Attack-surface delta — per-customer metric quotas

Best-effort hint for the security agent; the diff is the source of truth.

## New entry points

- `PUT /v1/quotas` — `src/api/routes/quotas.py:44` — new authenticated,
  admin-scoped HTTP route. Composed dependency: `require_api_key` ->
  `enforce_tier2_rate_limit` -> `principal.scope == "admin"` gate (403
  `forbidden` otherwise) — `src/api/routes/quotas.py:25-38`.
- No new CLI commands, event/queue consumers, or webhook receivers.
  `scripts/seed_api_key.py` gained a `--admin` flag (`scripts/seed_api_key.py:60-63`)
  but is the same pre-existing operator-run provisioning script, not a new
  entry point.

## New trust boundaries

- None. No new outbound third-party API calls, no new `subprocess`/`exec`
  invocations, no SSRF-capable fetches. The feature is entirely
  request -> app -> same RDS Postgres instance (existing app<->RDS boundary,
  extended with one more table and one more query path).

## New data flows / sinks

- `quotas` table (new) — `alembic/versions/0003_create_quotas_and_api_key_scope.py`.
  Stored fields and their at-rest classification (all non-sensitive
  operational config per the plan's data-classification table; no field-level
  KDF/KMS mechanism required, RDS SSE storage-level encryption only):
  - `customer_id` (TEXT) — non-sensitive, opaque tenant-assigned id — RDS SSE.
  - `metric` (TEXT) — non-sensitive, opaque metric name — RDS SSE.
  - `limit_per_window` (BIGINT) — non-sensitive, admin-set business config — RDS SSE.
- `api_keys.scope` column (new, TEXT, `CHECK IN ('ingest','admin')`) — non-sensitive
  authorization metadata (not a credential; the credential remains
  `secret_hash`, Argon2id, unchanged) — RDS SSE.
- All new SQL in `src/repositories/quotas_repo.py` uses SQLAlchemy `text()`
  with bound parameters only (no string interpolation); every query filters
  `api_key_id = :api_key_id` (row-level scoping) before any other predicate.
- New structured log events (via the existing structlog facade,
  `src/logging/__init__.py` redaction/anti-forging processors apply
  automatically): `quota.upsert` (INFO, `src/services/quota_service.py`),
  `quota.rejected` (WARNING, `src/services/events_service.py` — deliberately
  omits `current_total`/`limit_per_window`, only the enforcement event
  itself), `quota.forbidden` (WARNING, `src/api/routes/quotas.py`). No raw
  request bodies or credentials logged; `customer_id` is already in the
  global `_SENSITIVE_KEYS` redaction set and is redacted wherever it appears,
  including these new events.
- No new file read/write paths, caches, or deserialization of external input
  beyond the existing Pydantic schema validation layer.

## New privilege / authz surface

- `PUT /v1/quotas` is the first **function-level** authorization check in
  this codebase beyond authentication: `principal.scope == "admin"` gates the
  route (`src/api/routes/quotas.py:31-38`), layered over the pre-existing
  **data-level** tenant isolation (`api_key_id` scoping + RLS) that already
  applies to every table.
- `api_keys.scope` widens what an `admin`-scoped key can reach (create/replace
  a quota under its own tenant) but does not change what an `ingest`-scoped
  key can do — `POST /v1/events` and `GET /v1/usage` remain scope-agnostic, as
  the plan specifies (no behavior change for existing keys).
- No new token issuance, no new role hierarchy beyond the two-value
  `ingest`/`admin` scope, no cross-tenant capability introduced (a quota is
  always scoped to the authenticated key's own `api_key_id`; RLS policy
  `quotas_tenant_isolation` is the backstop).
