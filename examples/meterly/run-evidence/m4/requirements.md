# Requirements — per-customer metric quotas

Elicited 2026-07-08 (operator interview, requirements-elicitation first live run).
Brief: PROJECT.md (PUT /v1/quotas admin-scoped; POST /v1/events 429s on would-exceed;
one expand-only migration; existing p95 < 50 ms budget on POST /v1/events; no design source).

## Resolved

- What window is `limit_per_window`? → The existing UTC hour rollup window
  (`floor_to_hour_utc` / rollup `window_start`). The quota check reads the current-hour
  rollup; no new aggregation.
- How is a quota tenant-scoped? → Per tenant: `(api_key_id, customer_id, metric)`.
  Quota rows carry the tenant key like every other table; an admin key sets quotas for
  its own tenant's customers only.
- What does "would exceed" mean at the boundary (rollup R, incoming quantity Q, limit L)?
  → Reject when `R + Q > L`; usage never exceeds L. An event with Q > L against an empty
  window is rejected too.
- Throttle-vs-quota precedence on POST /v1/events, and error code? → Tier-2 token-bucket
  throttle stays first (pre-handler dependency, protects the DB from quota-check load);
  quota rejections are a distinct envelope `code: quota_exceeded` (429). Existing
  throttle keeps `code: rate_limited`.
- How does a key become admin-scoped? → New `scope` column on `api_keys` (default
  `'ingest'`, expand-only), `scripts/seed_api_key.py` grows an `--admin` flag, the
  authenticated principal carries the scope, PUT /v1/quotas requires `scope = 'admin'`
  (403 `forbidden` otherwise).
- PUT /v1/quotas semantics for an existing row? → Upsert: create-or-replace
  `(customer_id, metric) → limit_per_window` (201 create / 200 replace); response body
  echoes the stored quota. No removal path this slice.
- When does a quota set/changed mid-window take effect? → Immediately, against the
  current window's already-accumulated rollup. Lowering L below current R blocks the
  rest of the window.
- Concurrent POSTs racing at the quota edge? → Strict enforcement: the quota check is
  atomic with the rollup increment inside the existing per-request transaction (guarding
  the rollup row, e.g. row lock / conditional update), so usage can never exceed L.
  Serializes concurrent posts on the same (customer, metric, window) row; the p95
  < 50 ms budget still applies.
- Idempotent replay (duplicate idempotency_key) when the window is now over quota? →
  200 replay with the original stored result; the quota is not consulted. The
  idempotency contract is absolute — a retry of an accepted event never flips to 429,
  and a replay adds no usage.
- Validation bounds on `limit_per_window`? → Integer >= 1 only; 0 and negatives are
  rejected 422 (`validation_failed`). A quota is a cap, not a kill switch.
- Extra contents of the 429 quota response? → `Retry-After` header = seconds until the
  next hour window (matches the throttle's existing header pattern). Body stays the
  standard three-field envelope `{code, message, requestId}` — no usage numbers in
  error bodies.
- The brief's "ONE expand-only migration" vs the new api_keys scope column? → One
  Alembic revision containing both expand-only changes: CREATE TABLE quotas + ALTER
  TABLE api_keys ADD COLUMN scope DEFAULT 'ingest' (backfill-free).
- Is PUT /v1/quotas behind the normal edge stack? → Yes: require_api_key → Tier-2
  per-key throttle → scope check (403) → handler. No admin special-casing.
- Data classification of the new stored fields (customer_id, metric, limit_per_window,
  scope)? → Non-sensitive operational config; customer_id/metric are opaque
  tenant-scoped identifiers already stored in events/rollups. Storage-level encryption
  (RDS SSE) suffices; no field-level crypto.

## Open

- Latency budget for PUT /v1/quotas itself — not discussed in the interview; the stated
  p95 < 50 ms budget applies to POST /v1/events only. Planning should either state a
  sensible default for the (low-traffic, admin-only) route or raise it at the plan
  checkpoint.

## Out of scope

- Removing/unsetting a quota (DELETE /v1/quotas or `limit: null`) — customers go back
  to unlimited only via direct DB change this slice.
- GET /v1/quotas (read/list endpoint) — the PUT response echo is the only read.
- `limit_per_window = 0` as a customer/metric kill switch — blocking a customer
  outright is a different feature.
- Global / cross-tenant quotas — quotas are per (api_key_id, customer_id, metric) only.
- Deferred effectiveness (`effective_from` / next-window-only quota changes) — changes
  apply immediately.
- Usage/limit/window-reset detail in the 429 error body.
- Daily or per-quota-configurable windows — hour windows only.
- Any change of behavior for customers without a quota row (they stay unlimited).
