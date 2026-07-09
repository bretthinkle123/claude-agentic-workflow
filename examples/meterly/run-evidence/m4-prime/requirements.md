# Requirements — usage CSV export

Elicited 2026-07-09 (operator interview, pre-planning). Brief: PROJECT.md (GET /v1/usage/export,
caller's rollups as CSV, existing API-key auth, no behavior change to existing endpoints,
no design source).

## Resolved

- What rows does the export return? → Every `usage_rollup` row under the authenticated
  `api_key_id`, with **optional** `customer_id` and `metric` query filters (reusing the
  existing validated types). No required params.
- Time-range semantics? → Optional `from`/`to` aware-datetime params, validated like the
  existing window bound (`from <= to`, both within `[now−90d, now+1h]`); omitted → the full
  supported range. Naive datetimes rejected (existing idiom).
- Size control? → **Streaming** response (constant memory, rows written as read) with a
  **hard cap of 100,000 rows**; a result exceeding the cap fails 422 `validation_failed`
  telling the caller to narrow filters. No pagination this slice.
- Who may export? → **Any authenticated key** (ingest or admin) — it is the caller's own
  tenant data, same read authority as GET /v1/usage; normal edge stack
  (require_api_key → Tier-2 per-key throttle).
- CSV formula injection? → **Escape formula-leading text cells** at the CSV-encoding
  boundary (OWASP defense: prefix `'` when a text cell starts with `=`, `+`, `-`, `@`,
  incl. tab/CR variants; control chars stripped/quoted). Numeric/timestamp columns untouched.
- Response headers? → `Content-Type: text/csv; charset=utf-8` +
  `Content-Disposition: attachment; filename=usage-export-<UTC timestamp>.csv`
  (no tenant identifiers in the filename).
- Dialect? → RFC 4180 via the stdlib csv module (no hand-rolled encoder): header row always
  present, exactly `customer_id,metric,window_start,total_quantity` (brief's column order);
  CRLF line endings; quote fields containing comma/quote/newline.
- Empty result? → **200 with a header-only CSV** (one shape for consumers; mirrors the
  existing zeros-not-404 contract).
- Ordering? → Deterministic `ORDER BY window_start, customer_id, metric ASC` (index-friendly;
  identical exports diff cleanly).
- Value formats? → `window_start` as the UTC ISO-8601 string with offset (identical to the
  JSON response's string form); `total_quantity` as a plain decimal string via `str(Decimal)`
  (no scientific notation).
- Perf posture? → Reporting route: **documented p95 target, NOT a k6 load AC** (proposed
  default: p95 < 500 ms at the 100k-row cap, verified by an integration timing sanity check).
  The binding perf criterion is negative: POST /v1/events' existing budget, tests, and code
  path are untouched (the brief's own no-behavior-change constraint).
- New stored data? → None — read-only feature over existing rollups; no migration, no new
  data-classification surface.

## Open

- The exact documented p95 target number for the export route (500 ms at the cap was the
  proposed default; low stakes — planning states a default or raises it at the checkpoint).

## Out of scope

- Pagination (`limit`/`offset`) — the row cap + filters are the size control this slice.
- Admin-only gating of exports — any authenticated key may export its own tenant's data.
- Other formats (JSON export, XLSX), compression (gzip), and scheduled/async export jobs.
- Any change to GET /v1/usage, POST /v1/events, PUT /v1/quotas, or their budgets/tests.
- Per-export audit logging beyond the standard structured request log.
