# Attack-surface delta — usage CSV export (`GET /v1/usage/export`)

Best-effort hint for security's diff reconciliation. Categories below reflect
only what this change adds; the diff (`git diff HEAD`) is the source of truth.

## New entry points

- `GET /v1/usage/export` — new HTTP route, `src/api/routes/usage_export.py:71`
  (`get_usage_export`). Registered in `src/main.py` (new `include_router` call
  for `usage_export_router`, alongside the existing `usage_router`/
  `quotas_router`/`events_router`). Reuses the existing API-key auth facade
  (`require_api_key`) and the existing Tier-2 per-`api_key_id` throttle
  (`enforce_tier2_rate_limit`) — no new auth mechanism.
- No new CLI commands, event/queue consumers, or webhook receivers.

## New trust boundaries

- **CSV file → downstream spreadsheet application** (new boundary this
  feature introduces, per the plan's threat model): the exported file may be
  opened in Excel/Sheets, where an unescaped leading `= + - @ \t \r` cell
  would execute as a formula. Mitigated by `escape_csv_text_cell`
  (`src/api/csv_export.py:29`), applied to `customer_id`/`metric` text cells
  at the encoding sink, plus `Content-Disposition: attachment` +
  `X-Content-Type-Options: nosniff` (existing) so a browser downloads rather
  than renders the response.
- No new outbound third-party API calls, no new `subprocess`/`exec`
  invocations, no new SSRF-capable fetches. API ↔ PostgreSQL is an existing
  trust boundary, not a new one — this route adds two new query shapes over
  it (see Data flows below), not a new boundary.

## New data flows / sinks

- **New DB queries** over the existing `usage_rollup` table (no new table,
  column, index, or migration): `count_usage_rollups` (pre-flight cap check,
  `SELECT count(*) ... WHERE api_key_id = :api_key_id [AND ...]`) and
  `stream_usage_rollups` (the export read, same WHERE shape + fixed-literal
  `ORDER BY window_start, customer_id, metric` + `LIMIT`), both in
  `src/repositories/usage_repo.py`. Both are scoped by the authenticated
  `api_key_id` first (mandatory predicate, bound parameters only — see
  `_export_filter_clause_and_params`, `src/repositories/usage_repo.py:74`).
- **New response body shape**: a streamed `text/csv` file
  (`src/services/usage_export_service.py:82`, `stream_export_csv`) — no new
  file writes on the server side (the CSV is generated in-memory per row and
  streamed directly to the HTTP response; nothing is written to disk).
- **New log event**: `usage.export` (info, on completion) and
  `usage.export.rejected` (warn, on over-cap) through the existing
  `get_logger()` facade (`src/services/usage_export_service.py`). Logged
  fields are opaque `api_key_id` (`userId`), row count, `capped`/`completed`
  booleans, and filter-*presence* booleans (`filtered_by_customer`,
  `filtered_by_metric`, `bounded_from`, `bounded_to`) — never the raw
  `customer_id`/`metric` values (the centralized redaction processor also
  scrubs `customer_id` as belt-and-suspenders). No new category of data is
  logged beyond what `usage_service`/`events_service` already log.
- **No new stored user data.** This is a read-only feature: every field the
  export emits (`customer_id`, `metric`, `window_start`, `total_quantity`) is
  already stored via the existing ingest path (migration 0002); no new column,
  table, or at-rest control was added. Classification/at-rest mechanism for
  these fields is unchanged from the existing `usage_rollup` table (personal-
  class `customer_id`, no field-level encryption change — see the plan's Data
  section for the pre-existing RLS-`FORCE` gap this feature does not worsen).

## New privilege / authz surface

- `GET /v1/usage/export` is reachable by **any authenticated key**
  (`ingest` or `admin` scope) — no new scope gate, matching the brief's
  explicit "not admin-gated" resolution. This is a **widening** relative to
  `PUT /v1/quotas` (admin-only) but identical in shape to the existing
  `GET /v1/usage` (also any-authenticated-key, read-only, tenant-scoped).
  The only access-control boundary is tenant isolation: `api_key_id` is
  sourced exclusively from the authenticated principal, never from the
  request (`UsageExportQueryParams` has no `api_key_id` field and
  `extra="forbid"` rejects one if supplied) — closes IDOR/BOLA the same way
  `GET /v1/usage` already does.
- No new token issuance, no new role, no new admin capability.
