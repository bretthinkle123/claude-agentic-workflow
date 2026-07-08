# Plan — per-customer metric quotas

Authoritative brief: `.pipeline/requirements.md` (operator-elicited; Resolved / Open / Out-of-scope).
Every Resolved item below is turned into scope + an acceptance criterion; the single Open item
(PUT latency budget) is carried as an Open Question with a stated default; Out-of-scope items are
hard exclusions and are **not** planned. Design source: none (backend HTTP API — no UI to build).

## Summary

Meterly already ingests metered events idempotently (`POST /v1/events`) and rolls them into an
hourly per-tenant counter (`usage_rollup`). This feature adds an **admin-set, per-customer,
per-metric usage cap** enforced against that existing hourly rollup. Two surfaces change:

1. **`PUT /v1/quotas`** (new, admin-scoped) upserts a cap `(customer_id, metric) → limit_per_window`
   for the caller's own tenant (201 create / 200 replace, echoing the stored row).
2. **`POST /v1/events`** (existing) now rejects an event with **429 `quota_exceeded`** when the
   current-hour rollup `R` plus the incoming quantity `Q` would exceed the cap `L` (`R + Q > L`);
   customers with no quota row stay unlimited (no behavior change).

The core approach is **enforce against the value that already exists** — the hourly rollup — rather
than introduce any new aggregation, and to make the check **atomic with the rollup increment inside
the request's existing transaction** so usage can never exceed `L` under concurrency. The chosen
serialization mechanism is a `SELECT … FOR UPDATE` row lock on the quota row (details and rejected
alternatives in *Backend* below). One expand-only Alembic migration adds the `quotas` table and an
`api_keys.scope` column; no new cloud infrastructure is provisioned. The scanner/auth context stays
the existing `Authorization: Bearer mtr_live_<key_id>_<secret>` split-token (relevant to DAST
readiness, below).

## Stack notes

Assessed each default against this project; every choice **endorses the existing Meterly stack**
recorded in `CLAUDE.md` — this is a brownfield increment, so consistency with the established stack
is the overriding consideration, and each default already fits.

- **Language / framework:** Python 3.12 + FastAPI + async SQLAlchemy `text()` repositories — endorsed
  (matches every existing module; no reason to diverge for a two-endpoint increment).
- **Database:** PostgreSQL (RDS) — endorsed. The feature leans on two Postgres-specific guarantees the
  codebase already relies on: `INSERT … ON CONFLICT` upserts and `SELECT … FOR UPDATE` row locking.
  Both are proven, boring, well-understood primitives (DDIA: prefer a single-node transactional store
  with real row locks over inventing a distributed counter) — no new datastore is warranted.
- **Migrations:** Alembic — endorsed; one new revision `0003`, expand-only (see *Data / migrations*).
- **Auth:** existing API-key facade (Argon2id split-token, per-key Tier-2 throttle) — endorsed and
  **extended** with a `scope` column (`ingest` default, `admin` for quota management). No third-party
  IdP is introduced (consistent with `CLAUDE.md`). Admin is modeled as a **superset scope**: an
  `admin` key may do everything an `ingest` key does *plus* call `PUT /v1/quotas` (rationale in *Auth*).
- **Cloud / IaC:** AWS + Terraform — **no change**. The feature adds one table and one column to the
  existing RDS instance; no new AWS service, IAM role, or `infra/` resource. Encryption-at-rest for
  the new columns is covered by the existing RDS SSE (see *Data classification*). `iac-conventions`
  therefore not invoked — nothing is provisioned.
- **Observability / logging:** structlog facade + CloudWatch/X-Ray + Sentry — endorsed; the feature
  emits three new structured events (see *Logging*).
- **Runtime secrets:** unchanged — the feature consumes no new credential (`secrets-management` not
  triggered; DB URL is already fetched at runtime behind the secrets facade).

Nothing here recommends *against* a default, so there is no divergence for the checkpoint to ratify —
only the confirmation that the brownfield increment stays on the established stack.

## Backend

### The tenant model (why `api_key_id` is the tenant, and what "admin" means)

Every existing table (`events`, `usage_rollup`) is keyed and RLS-isolated by `api_key_id` — in this
system **the api_key *is* the tenant**. The quota model follows suit exactly: a quota row is
`(api_key_id, customer_id, metric) → limit_per_window`, stored under the authenticated principal's
`api_key_id`. This is the only model that makes enforcement *bind*: the rollup a `POST /v1/events`
increments is keyed by the ingesting key's `api_key_id`, so for a quota to apply to those events its
`api_key_id` must be that same key. **Admin is therefore a superset scope, not a separate key
family:** a tenant that wants quotas provisions one `admin`-scoped key and uses it to both ingest and
administer; `POST /v1/events` accepts any authenticated key (no scope restriction — nothing in the
brief restricts ingestion by scope), while `PUT /v1/quotas` requires `scope = 'admin'`.

- *What:* `scope` is a single column on `api_keys` (`'ingest'` default, `'admin'` elevated), the
  authenticated principal carries it, and only the quota-management route checks it.
- *Why this over alternatives:* a **separate `quota_admins` join table or RBAC role table** was
  rejected — it introduces a many-keys-per-tenant concept the schema does not have and the brief
  puts out of scope (global/cross-tenant quotas are excluded). A **boolean `is_admin`** was rejected
  in favor of a `scope` string with a `CHECK (scope IN ('ingest','admin'))` because a string leaves
  room for future scopes (e.g. `readonly`) without another migration, at no extra cost today.
- *How it fits:* the same `AuthenticatedPrincipal` that already flows from `require_api_key` (and is
  cached) simply gains a `scope` field; existing routes ignore it, so their behavior is unchanged.
- *Tradeoff accepted:* a tenant wanting quotas must ingest with its admin key (single-key-per-tenant).
  Multi-key-per-tenant is out of scope per the brief; this is consistent with the current schema and
  flagged, not silently assumed.

### `PUT /v1/quotas` — upsert semantics

- *What:* a new route `src/api/routes/quotas.py` exposing `PUT /v1/quotas`, body
  `{customer_id, metric, limit_per_window}`, that upserts the cap and echoes the stored row —
  **201** on create, **200** on replace. No delete / unset path (out of scope).
- *Why PUT + upsert (not POST/PATCH):* the resource identity is `(customer_id, metric)` supplied in
  the body and the operation is **create-or-replace with no partial merge** — that is idempotent
  replacement, which is precisely PUT's contract (a repeat PUT is a no-op change). POST would imply a
  new sub-resource each call; PATCH would imply a partial merge we explicitly do not want (the brief
  says replace, not merge). Idempotent PUT also needs no `Idempotency-Key`.
- *How create-vs-replace is detected in one statement:* the repository upsert uses
  `INSERT … ON CONFLICT (api_key_id, customer_id, metric) DO UPDATE … RETURNING (xmax = 0) AS inserted, …`.
  The `xmax = 0` idiom returns true only when the row was freshly inserted (an `ON CONFLICT` update
  leaves a non-zero `xmax`), so the service maps `inserted → 201` else `200` **without a second
  round-trip or a read-before-write race**. (This idiom is documented inline in the repo because a
  reviewer needs the "why".)
- *Edge stack (unchanged ordering):* the route inherits the middleware stack (security headers, CORS,
  8 KiB body guard, Tier-1 IP throttle) by being mounted, then composes
  `require_api_key → enforce_tier2_rate_limit → admin-scope check → handler`, mirroring the
  `events`/`usage` routes' sibling `_require_authenticated_and_throttled` pattern (kept per-route, not
  shared, per the existing convention). The scope check raises `HTTPException(403)` → envelope
  `code: forbidden` for a non-admin key.
- *Latency:* a single indexed PK upsert; see the Open Question for its budget.

### `POST /v1/events` — the quota check (atomic, strict, replay-safe)

The existing service already branches on "did this insert land a new row?". The quota check slots
**exactly into the winning-insert branch**, which is what makes the three hardest requirements fall
out naturally:

```
insert_event_if_new(...)            # ON CONFLICT DO NOTHING (unchanged)
  ├─ returned a row (new event) ──► read_tenant_quota_state_locked(...)   # NEW
  │                                   if quota exists and R + Q > L:  raise AppError(429, quota_exceeded)  # rolls back the event insert
  │                                 increment_usage_rollup(...)           # unchanged
  └─ returned None (replay)   ──►  find_event_by_idempotency_key(...) → 200 replay   # quota NEVER consulted
```

1. **Idempotent replay never consults the quota** (brief: a retry of an accepted event must never
   flip to 429 and adds no usage) — because the check lives only on the `inserted is not None` branch;
   a duplicate `idempotency_key` takes the untouched replay path and returns the original 200.
2. **A rejected event leaves no trace** — the check runs *after* the event `INSERT` but *inside* the
   same `scoped_transaction`; raising `AppError` propagates out of the `session.begin()` context,
   which **rolls back**, undoing the event row and skipping the rollup increment. Usage is never
   incremented for a rejected event, and — because the event row is rolled back — a later retry of a
   *rejected* event is a fresh insert re-evaluated against the (possibly changed) quota, which is the
   correct semantics (a 429'd event was never accepted).
3. **`R + Q > L` is checked, including the empty window** — `R` defaults to 0 when no rollup row
   exists yet, so an event with `Q > L` against an empty window is rejected too (brief).

#### The atomic read-and-decide (the strict-enforcement mechanism)

- *What:* one repository function `read_tenant_quota_state_locked(session, api_key_id, customer_id,
  metric, window_start)` runs a single statement that reads the limit **and** the current rollup
  total while taking a row lock on the quota row:

  ```sql
  SELECT q.limit_per_window,
         COALESCE(r.total_quantity, 0) AS current_total
  FROM quotas q
  LEFT JOIN usage_rollup r
    ON  r.api_key_id = q.api_key_id AND r.customer_id = q.customer_id
    AND r.metric = q.metric AND r.window_start = :window_start
  WHERE q.api_key_id = :api_key_id AND q.customer_id = :customer_id AND q.metric = :metric
  FOR UPDATE OF q
  ```

  Returns `None` → **no quota → unlimited** (proceed to the normal upsert, zero extra locking).
  Returns a row → the service computes `current_total + Q > limit` and either raises or increments.
- *Why `FOR UPDATE` on the quota row (and why it is race-free):* strict enforcement is a
  **check-then-act** on a shared counter — the classic TOCTOU. The quota row is the natural
  serialization point because, in the enforced path, **it always exists** (a rollup row may not yet
  exist for a fresh window, so it cannot be the lock target). Every concurrent `POST` for the same
  `(customer, metric)` must acquire `FOR UPDATE OF q` on that one row first, so they **block on it
  until the holder commits/rolls back**. While the lock is held, no other writer can read `current_total`
  or increment the rollup, so the decision is made on an accurate value and the subsequent
  `increment_usage_rollup` is the only mutation until commit. Result: **usage can never exceed `L`**.
  Reading `current_total` via an unlocked `LEFT JOIN` is safe precisely because the rollup row is only
  ever written by holders of the quota lock.
- *Enabling conditions (so this is a verifiable mechanism, not a slogan):*
  - **Lock ordering is consistent → no deadlock:** every request acquires locks in the same order —
    the new event row (distinct `idempotency_key`, no cross-contention) → the quota row (`FOR UPDATE`)
    → the rollup row (`ON CONFLICT DO UPDATE`). Two posts for the same `(customer, metric)` contend
    only on the quota row, in that order, so no lock cycle can form.
  - **Fail-secure on reject:** the rollback is what enforces "no partial write"; the `AppError` is
    raised *before* `increment_usage_rollup`, so a rejected request commits nothing.
  - **Unlimited path takes no lock:** when the quota `WHERE` matches nothing, `FOR UPDATE` locks no
    row — customers without a quota add zero contention (only a single indexed lookup that returns 0
    rows). This is the common path and protects the p95 budget.
- *Why not the alternatives:*
  - A **single-statement CTE upsert with a `WHERE total + EXCLUDED <= limit` guard** was rejected: the
    decision sub-CTE reads a snapshot value while `ON CONFLICT DO UPDATE` re-reads the row at write
    time, so under READ COMMITTED two concurrent posts can both pass the snapshot check and jointly
    exceed `L` — it does **not** give strict enforcement, and the guard also cannot cleanly reject the
    *first* insert into an empty window (`Q > L`).
  - **`SERIALIZABLE` isolation** was rejected: it would force retry-loop handling on the hot ingest
    path and abort-storm under contention — heavier and less predictable than a targeted row lock.
  - **`pg_advisory_xact_lock(hash(customer,metric,window))`** was rejected: it serializes on exactly
    the right granularity but reasons over a hashed integer (collision handling, no visible row) and
    is less reviewable than locking the real quota row the brief itself suggests ("row lock").
- *Tradeoff accepted (brief-sanctioned):* posts to the **same quota'd `(customer, metric)`**
  serialize. Under realistic and load-test traffic (keys spread across many customers/metrics) this is
  near-zero contention; a single hot quota'd bucket serializes its writers, which is the price of
  "usage never exceeds `L`". The p95 < 50 ms budget is measured with quotas active (AC20).

### The error-code facade extension (`quota_exceeded` vs `rate_limited`)

- *Problem:* the error envelope maps status→code via `_STATUS_TO_CODE`, and **429 already maps to
  `rate_limited`** (the Tier-2 throttle). Quota rejection must be a *distinct* 429 code.
- *What / how:* add a small `AppError(HTTPException)` in `src/api/errors.py` carrying an explicit
  `app_code`, and have `handle_http_exception` prefer `getattr(exc, "app_code", None)` over the status
  map. `QuotaExceededError` is `AppError(429, app_code="quota_exceeded", detail="metric quota exceeded
  for the current window", headers={"Retry-After": <seconds to next hour>})`. The throttle's
  `HTTPException` still resolves to `rate_limited` (no `app_code`), so throttle-vs-quota precedence and
  codes are exactly as the brief requires.
- *Why not extend `_STATUS_TO_CODE`:* a status→code map cannot represent two codes sharing one status;
  a per-exception `app_code` is the minimal, single-boundary change that keeps the one-envelope facade.
- *`Retry-After`:* seconds until the next hour boundary = `(window_start + 1h) − received_at`, floored
  to `>= 1`; matches the throttle's existing header pattern. The body stays the three-field envelope
  `{code, message, requestId}` — **no usage/limit numbers** (brief; also an info-disclosure control).

## Data / migrations

### New/changed stored fields and their classification (data-protection)

`data-protection-conventions` consulted. The brief classifies all new stored fields as **non-sensitive
operational config**, and that holds under the taxonomy:

| Field | Table | Class | At-rest control |
|---|---|---|---|
| `customer_id` | `quotas` | non-sensitive (opaque tenant-assigned id, already stored in `events`/`usage_rollup`) | RDS SSE (storage-level) — no field-level crypto |
| `metric` | `quotas` | non-sensitive (opaque metric name, already stored) | RDS SSE |
| `limit_per_window` | `quotas` | non-sensitive (a business cap the admin itself sets) | RDS SSE |
| `scope` | `api_keys` | non-sensitive authorization metadata (not a credential; the credential is `secret_hash`, already Argon2id) | RDS SSE |

No field is `credential`, `sensitive-PII`, or `personal`, so **no field-level `data_protection`
mechanism (KDF/KMS) is required** — recorded here as an explicit classification so security's
`data_surface` reconciliation sees it declared. Storage-level encryption is the existing RDS SSE on
the instance (unchanged; no new KMS key). *Note:* usage **totals** are treated as billing-adjacent by
the existing code (`Cache-Control: no-store` on `/v1/usage`), which is why the quota **error body and
logs deliberately omit usage/limit numbers** (see *Logging* and threat I1) — but the stored *config*
fields above are not themselves sensitive.

### Migration `0003_create_quotas_and_api_key_scope.py` (one revision, expand-only)

Both expand-only changes land in **one** Alembic revision (brief: "ONE expand-only migration" now
also covers the `scope` column):

- `CREATE TABLE quotas`:
  - `api_key_id BIGINT NOT NULL REFERENCES api_keys(id)`, `customer_id TEXT NOT NULL`,
    `metric TEXT NOT NULL`, `limit_per_window BIGINT NOT NULL`,
    `created_at`/`updated_at TIMESTAMPTZ NOT NULL DEFAULT now()`.
  - `PRIMARY KEY (api_key_id, customer_id, metric)` — the tenant-scoped natural key (one cap per
    customer/metric per tenant; the PK doubles as the upsert conflict target and the lookup index).
  - `CHECK (limit_per_window >= 1)` — a cap is `>= 1`, never 0 (a kill-switch is out of scope; the
    DB CHECK is the backstop behind the schema's `conint(ge=1)`).
  - `ENABLE ROW LEVEL SECURITY` + `CREATE POLICY quotas_tenant_isolation USING (api_key_id =
    current_setting('app.current_api_key_id', true)::bigint)` — mirrors `events`/`usage_rollup`.
    **RLS enabling condition (U-02):** this backstop is only effective if the application's DB role is
    **not the table owner** and lacks `BYPASSRLS` (a table owner bypasses non-`FORCE` RLS). The
    existing tables use `ENABLE` (not `FORCE`), implying the app already connects as a non-owner role;
    `quotas` mirrors that. The **primary** control is the explicit `api_key_id = :api_key_id` filter
    present in every `quotas` query; RLS is defense-in-depth. Verifying the app role is a non-owner (or
    adding `FORCE ROW LEVEL SECURITY`) is called out as an Open Question.
- `ALTER TABLE api_keys ADD COLUMN scope TEXT NOT NULL DEFAULT 'ingest'` +
  `CHECK (scope IN ('ingest','admin'))` — backfill-free (the `DEFAULT` applies to existing rows), so
  no data migration and safe on a live table.
- `downgrade()`: `DROP TABLE quotas`; `ALTER TABLE api_keys DROP COLUMN scope` (FK/constraint-safe).

**Reversibility kind (audit E6 — asserted precisely by AC16):** this revision is *both* a
create-migration (`quotas`) and an expand on a populated table (`api_keys.scope`):
- `quotas` — **schema + constraints** reversibility only: `down` drops the table, so literal row
  survival across `down` is undefined by definition; `up→down→up` must restore the schema and
  re-enforce every PK/FK/CHECK identically.
- `api_keys.scope` — the pre-existing `api_keys` **rows survive** `up→down→up` (only a column is
  added/dropped; the other columns are untouched). The added `scope` column's *values* reset to the
  `'ingest'` default on `down` — that is the **defined expand/contract contract of an add-column**, not
  data loss of a populated business column. AC16 asserts row survival for the pre-existing columns and
  the constraint re-enforcement, and phrases the `scope` reset as expected.

DDIA operability note: the migration is O(1) on schema plus a metadata-only column add with a constant
default (Postgres 11+ does not rewrite the table for a non-volatile default) — safe under live ingest,
consistent with how `0002` reasons about deploy ordering.

## Auth

- `api_keys_repo.find_active_key_by_key_id` gains `scope` in its `SELECT` and `ApiKeyRecord`;
  `api_keys_repo.create_api_key` gains a `scope: str = "ingest"` parameter (defaulted so existing
  callers are unaffected).
- `AuthenticatedPrincipal` gains `scope: str = "ingest"` (defaulted → any direct construction in unit
  tests keeps working); `verify_api_key` populates it from the record. The verification cache stores
  the whole principal, so `scope` is cached with it — no cache-contract change.
- The `PUT /v1/quotas` route's composed dependency runs `require_api_key → enforce_tier2_rate_limit`
  then asserts `principal.scope == 'admin'`, else raises `HTTPException(403)` (envelope `forbidden`)
  and logs `quota.forbidden`. This is **function-level authorization** (ASVS 8.2.1) — the admin gate —
  layered over the **data-level** tenant isolation (ASVS 8.2.2/8.4.1) that the `api_key_id` scoping +
  RLS already provide on the quota rows.
- No new provider, token type, or MFA path — `auth-patterns`' third-party IdP flows are not in scope
  (this project uses API keys per `CLAUDE.md`). `seed_api_key.py` grows an `--admin` flag that sets
  `scope='admin'` at provisioning; the printed `mtr_live_<key_id>_<secret>` value is unchanged.

## Infrastructure

No infrastructure change. The feature adds one table and one column to the existing RDS PostgreSQL
instance via Alembic; it provisions no new AWS service, IAM role, security group, or `infra/`
resource, and introduces no new runtime secret. Encryption-at-rest for the new columns is the existing
RDS SSE. `iac-conventions` is therefore not triggered. (The `infra/` diffs in the working tree belong
to a different branch/feature and are out of scope here.)

## Logging

New observable events, via the existing `structlog` facade (`get_logger(service="meterly")`), OTel
trace-id already propagated (`logging-conventions`):

- `quota.upsert` (**INFO**) on a successful `PUT /v1/quotas` — `userId=<admin api_key_id>`,
  `action="create"|"replace"`, `customer_id`, `metric`, `limit_per_window`, `requestId`. This is the
  **audit trail** for who set what cap when (repudiation / ASVS 16.2.1). `limit_per_window` is
  non-sensitive config the admin itself supplied, so it is safe (and useful) to log.
- `quota.rejected` (**WARNING**) on a 429 quota rejection — `userId`, `action="deny"`, `customer_id`,
  `metric`, `reason="quota_exceeded"`, `requestId`. **Deliberately omits `current_total`/`limit`** —
  usage totals are billing-adjacent (consistency with the `/v1/usage` `no-store` treatment and the
  brief's "no usage numbers in error bodies"); the enforcement event itself is what ops needs
  (ASVS 16.3.3 — security-control / business-limit enforcement).
- `quota.forbidden` (**WARNING**) on a non-admin `PUT /v1/quotas` — `userId`, `action="deny"`,
  `reason="insufficient_scope"`, `requestId` (ASVS 16.3.2 — failed authorization).

All three ride the existing PII-redaction and generic-error-envelope facade — no stack/SQL leaks to
the client (ASVS 16.5.1/16.5.3).

## API edge

`api-edge-conventions` applied to the new HTTP surface:
- `PUT /v1/quotas` inherits the full edge stack by being mounted; it is a **per-owner resource**
  endpoint, so its rate limit is the **principal-keyed post-auth Tier-2** token bucket (shared
  `enforce_tier2_rate_limit`, keyed on `api_key_id`) — not the IP-keyed Tier-1 (that stays the pre-auth
  edge shed). The two-principals-one-IP discriminating shape from the existing `test_rate_limit.py`
  proves the key dimension (AC15).
- **CORS:** `configure_cors` currently allows `["GET", "POST"]`; add `"PUT"` for correctness. (This is
  a server-to-server API with an empty origin allowlist, so CORS is effectively inert — the change is
  for completeness, not a live control.)
- The new 429 `quota_exceeded` + `Retry-After` follow the throttle's established header/envelope
  pattern; idempotency-key handling is unchanged (PUT is idempotent by method).

## DAST readiness

`dast-conventions`: the running app serves this new HTTP surface, so it must arrive scan-ready.
- **Served OpenAPI schema:** FastAPI auto-generates `/openapi.json` from the route + Pydantic schemas;
  `PUT /v1/quotas` and its `QuotaPutRequest`/`QuotaResponse` will appear automatically. AC21 asserts
  the path is present in the served schema so the scanner's spec matches the implemented route.
- **Seeded non-prod test user + auth context:** the endpoint is authenticated **and** admin-scoped, so
  the DAST auth context needs an **admin** test key. `seed_api_key.py --admin` provisions it in
  staging/local; the auth context stays `Authorization: Bearer mtr_live_<key_id>_<secret>` (the
  existing DAST-3 context, still documented here so `test_dast_context_documented.py` stays green).
  AC21 records the admin test-key requirement.

## Input surface (enumerated for security's `input_surface` reconciliation)

Every input source the feature exposes, with its planned controls (each PUT input also carries a
validation + a rate-limit acceptance criterion — see `acceptance.md`):

1. **`PUT /v1/quotas` request body** (new): `customer_id`, `metric`, `limit_per_window`; unknown
   fields rejected (`extra='forbid'`). Validation contract in *Threat Model → Validation contracts*.
   Rate limit: Tier-2 per-`api_key_id` (post-auth, principal-keyed). → AC5 (validation) + AC15
   (rate-limit).
2. **`Authorization` header** (unchanged): the existing anchored split-token regex in
   `src/auth/api_key.py` — reused, not modified.
3. **`POST /v1/events` request body** (pre-existing input source, behavior extended not re-shaped):
   the existing `EventCreateRequest` contract and Tier-2 throttle remain the validation + rate-limit
   controls; the feature adds a **business-limit** (the quota) on top (ASVS 2.3.2/2.4.1), not a new
   input contract. Enumerated here so the surface is accounted for; no new input field is introduced.

## Files affected

Create:
- `alembic/versions/0003_create_quotas_and_api_key_scope.py` — the one expand-only revision (quotas
  table + RLS policy; `api_keys.scope` column + CHECK).
- `src/api/schemas/quotas.py` — `QuotaPutRequest` (validation contract) + `QuotaResponse` (echo shape).
- `src/api/routes/quotas.py` — `PUT /v1/quotas` route + the admin-scope composed dependency.
- `src/repositories/quotas_repo.py` — `upsert_quota` (xmax insert/replace) + `read_tenant_quota_state_locked` (the `FOR UPDATE` read-and-decide).
- `src/services/quota_service.py` — orchestrates the `PUT` upsert (transaction + 201/200 mapping + `quota.upsert` log).
- `tests/test_schemas_quotas.py` — unit: `limit>=1`, 0/negative/non-int → 422, `extra='forbid'`, customer/metric allowlist.
- `tests/integration/test_quotas_endpoint.py` — PUT create/replace, admin-scope 403, 401, validation 422, tenant isolation.
- `tests/integration/test_events_quota_enforcement.py` — `R+Q>L` 429, empty-window `Q>L`, unlimited passthrough, replay-over-quota 200, mid-window effect, rollback-no-partial, `Retry-After`, `quota_exceeded` code.
- `tests/integration/test_quota_concurrency.py` — strict enforcement: N concurrent distinct-key posts never exceed `L`.
- `tests/integration/test_quota_migration.py` — `0003` up→down→up schema+constraints round-trip; api_keys row survival.
- `tests/integration/k6/load_events_quota.js` — k6 driver for the quota-active ingest perf run (AC20).

Modify:
- `src/repositories/api_keys_repo.py` — `SELECT scope`; `ApiKeyRecord.scope`; `create_api_key(scope=…)`.
- `src/auth/api_key.py` — `AuthenticatedPrincipal.scope`; populate it in `verify_api_key`.
- `src/services/events_service.py` — insert the quota check on the winning-insert branch; `quota.rejected` log; raise `QuotaExceededError`.
- `src/api/errors.py` — add `AppError(HTTPException)` with `app_code`; honor `app_code` in `handle_http_exception`.
- `src/api/middleware.py` — add `"PUT"` to CORS `allow_methods`.
- `src/main.py` — mount `quotas_router`.
- `scripts/seed_api_key.py` — `--admin` flag → `scope='admin'`.
- `tests/integration/test_seed_api_key_script.py` — cover `--admin` sets `scope='admin'`; default `'ingest'`.
- `tests/integration/test_perf_k6_load.py` — quota-active ingest perf scenario (seed high quotas, run `load_events_quota.js`, record p95 vs the 50 ms budget).
- `docs/system_architecture.md` — quotas surface + the enforcement/atomicity note (also carries the `mtr_live`/`Bearer` DAST-3 context string).
- `src/api/README.md`, `src/services/README.md`, `src/repositories/README.md`, `src/auth/README.md` — per-directory doc updates for the touched modules.
- `CLAUDE.md` — note the `admin` scope + `PUT /v1/quotas` in the auth line (touched-surface doc).

## Test strategy

**`pyramid`** (the project default). Most coverage is unit — the validation schema
(`test_schemas_quotas.py`), the 201/200 upsert mapping, the `R+Q>L` decision boundary, and the
`Retry-After` computation are all pure/near-pure logic testable without a database. A **focused
integration tier** against the real Postgres + Redis testcontainers (existing `conftest`) covers the
guarantees that are only real against actual Postgres — the `FOR UPDATE` strict-enforcement
concurrency, the transaction rollback-no-partial, the RLS tenant isolation, and the migration
round-trip — matching how `events`/`usage` are already tested. One **perf** run (k6, existing harness)
measures the ingest p95 with quotas active. E2E stays minimal (the endpoint round-trips are covered at
the integration tier). This is a bias toward the unit tier, not a relaxation of the coverage gate
(>= 85% branch coverage still required).

## Open questions

1. **PUT /v1/quotas latency budget** (the brief's single Open item). The stated p95 < 50 ms budget is
   for `POST /v1/events` only. *Proposed default:* **p95 < 100 ms** for `PUT /v1/quotas` as a
   documented target, **not** a load-tested AC — it is an admin-only, low-traffic route doing a single
   indexed upsert, so a sustained k6 load test would be over-engineering. Confirm at the checkpoint,
   or raise the budget to a hard AC if admin tooling is expected to batch-set quotas at volume.
2. **RLS enabling condition.** `quotas` mirrors the existing `ENABLE ROW LEVEL SECURITY` (not `FORCE`),
   which is only effective if the app's DB role is a **non-owner** of the table. *Proposed:* confirm
   the app role is a non-owner (the existing `events`/`usage_rollup` design already depends on this);
   if it is the owner, add `FORCE ROW LEVEL SECURITY` to `quotas` (and ideally the existing tables).
   The explicit `api_key_id` filter in every query is the primary control regardless.
3. **Admin = ingest superset (tenant model).** The plan models a quota-using tenant as **one
   admin-scoped key that both ingests and administers** (the only model under which enforcement binds
   with the current single-key-per-tenant schema). Confirm this is acceptable, or defer quotas until a
   multi-key-per-tenant model exists (larger; out of this slice's scope per the brief).

## Threat Model

Method: STRIDE (Shostack), scoped to this feature. Each credible threat names a **concrete mechanism**
(library/config/SQL construct + the file it lives in) and the **ASVS 5.0.0** requirement it satisfies.

### Assets and trust boundaries

Assets: the `quotas` rows (per-tenant caps), the `api_keys.scope` authorization attribute, the
`usage_rollup` counters the check reads, the admin API key (`Argon2id`-hashed secret), and the
`PUT /v1/quotas` / `POST /v1/events` endpoints. Trust boundaries crossed: **client ↔ app** (public
internet → ALB → FastAPI: unauthenticated bytes become an authenticated, scope-bearing principal) and
**app ↔ RDS** (the transaction that atomically checks the quota and increments the rollup). No new
service↔service or cloud-control-plane boundary is introduced.

### Validation contracts (per boundary input)

| Input | Contract | Sink it protects | Lives in |
|---|---|---|---|
| `customer_id` (PUT body) | `constr(pattern=r'^[A-Za-z0-9_.:-]{1,128}$')` (reused `CustomerId`) | `quotas` upsert + the quota-lookup SQL | `src/api/schemas/quotas.py` |
| `metric` (PUT body) | `constr(pattern=r'^[A-Za-z0-9_.:-]{1,64}$')` (reused `Metric`) | `quotas` upsert + lookup SQL | `src/api/schemas/quotas.py` |
| `limit_per_window` (PUT body) | `conint(ge=1, le=10**15)` (BIGINT-safe upper bound; 0/negative → 422) | BIGINT column + the `R+Q>L` comparison (overflow/absurd-value guard) | `src/api/schemas/quotas.py` |
| unknown PUT fields | `ConfigDict(extra='forbid')` | mass-assignment (no client-set `api_key_id`/`scope`) | `src/api/schemas/quotas.py` |
| `Authorization` header | existing anchored `^mtr_live_<key_id>_<secret>$` regex | `api_keys` lookup | `src/auth/api_key.py` (unchanged) |
| `POST /v1/events` body | existing `EventCreateRequest` (unchanged) | events/rollup/quota SQL sinks | `src/api/schemas/events.py` (unchanged) |

All new SQL uses SQLAlchemy `text()` with **bound parameters only** — no string interpolation
(ASVS 1.2.4).

### STRIDE table

| Category | Asset / Boundary | Attack vector | Severity | Mitigation (mechanism + file) | ASVS req(s) |
|---|---|---|---|---|---|
| **Spoofing** | `PUT /v1/quotas` / client↔app | Unauthenticated or non-admin caller sets/changes a cap | High | `require_api_key` (Argon2id split-token) then an `admin`-scope assertion in the route's composed dependency raising `HTTPException(403)` — `src/api/routes/quotas.py` + `src/auth/api_key.py` | 6.2.x, 8.2.1 |
| **Tampering** | `quotas` SQL / client↔app | SQLi via `customer_id`/`metric` into the new quota queries | High | Anchored allowlist `constr` (`src/api/schemas/quotas.py`) + parameterized `text()` bind params (`src/repositories/quotas_repo.py`) | 1.2.4, 2.2.1 |
| **Tampering** | `quotas` / mass-assignment | Client sets `api_key_id`/`scope` via the PUT body to write another tenant's cap or self-elevate | High | `ConfigDict(extra='forbid')` on `QuotaPutRequest`; server sets `api_key_id` from the principal, `scope` is never a body field — `src/api/schemas/quotas.py`, `src/services/quota_service.py` | 15.3.3, 8.2.3 |
| **Tampering** | `usage_rollup` / app↔RDS | Concurrent posts race the check-then-increment so usage exceeds `L` (TOCTOU) | High | `SELECT … FOR UPDATE OF q` on the quota row serializes all writers for a `(customer,metric)`; the check + `increment_usage_rollup` run in one `scoped_transaction`; a reject raises before the increment and the transaction rolls back (fail-secure). Enabling conditions: consistent lock order (event→quota→rollup) → no deadlock; unlimited path takes no lock — `src/repositories/quotas_repo.py`, `src/services/events_service.py` | 2.3.3, 2.3.4, 15.4.x |
| **Repudiation** | admin action / audit | Admin denies setting a blocking cap; client disputes a 429 | Medium | Structured `quota.upsert` (who/what/when incl. `limit_per_window`) and `quota.rejected` (`userId`,`customer_id`,`metric`,`requestId`) via the structlog facade; `requestId` ties the envelope to the log — `src/services/quota_service.py`, `src/services/events_service.py` | 16.2.1, 16.3.2, 16.3.3 |
| **Info Disclosure** | 429 body / client↔app | Error body/logs leak `current_total`/`limit`, letting a caller probe a competitor's usage | Medium | Envelope is the three-field `{code,message,requestId}` only — no usage/limit numbers (`_envelope` in `src/api/errors.py`); `quota.rejected` log omits totals; `customer_id`/`metric` travel in the PUT **body**, never the URL/query string (scope: body only) | 14.2.1, 15.3.1, 16.5.1 |
| **Info Disclosure** | quota data at rest | Cap/scope readable if the store is compromised | Low (accepted) | Classified non-sensitive operational config; existing RDS SSE (storage-level) covers it; no field-level crypto required — see *Data classification* | 14.1.x |
| **Denial of Service** | both endpoints | Request flood spends Argon2id verifies / DB work | Medium | Tier-1 IP+route pre-auth throttle (`Tier1EdgeThrottleMiddleware`, `/health` exempt, client IP from `request.client` behind the ALB) + Tier-2 per-`api_key_id` post-auth token bucket (`enforce_tier2_rate_limit`) on the new route + 8 KiB body guard — `src/api/middleware.py`, `src/auth/rate_limit.py` | 2.4.1, 4.x, 15.2.2 |
| **Denial of Service** | `usage_rollup` hot row | The `FOR UPDATE` lock serializes a hot quota'd bucket, spiking latency | Medium (accepted) | Lock scoped to the quota row so only quota'd `(customer,metric)` serialize; bounded 2-statement critical section; p95 measured under load with quotas active (AC20) — `src/repositories/quotas_repo.py` | 15.4.x |
| **Denial of Service** | `limit_per_window` | Absurd/overflowing limit value | Low | `conint(ge=1, le=10**15)` + BIGINT column — `src/api/schemas/quotas.py` | 2.2.1 |
| **Elevation of Privilege** | `PUT /v1/quotas` (function-level) | `ingest` key calls the admin route | High | `principal.scope == 'admin'` gate → `HTTPException(403)`; `quota.forbidden` logged — `src/api/routes/quotas.py` | 8.2.1 |
| **Elevation of Privilege** | `quotas` (data-level / cross-tenant) | A key reads/writes/enforces another tenant's cap (IDOR/BOLA) | High | Every `quotas` query filters `api_key_id = :principal.api_key_id`; `quotas_tenant_isolation` RLS policy via `SET LOCAL app.current_api_key_id` in `scoped_transaction`. Enabling condition: RLS effective only if the app role is a non-owner (else `FORCE ROW LEVEL SECURITY`) — see Open Question 2 — `src/repositories/quotas_repo.py`, `alembic/versions/0003_*`, `src/db/session.py` | 8.2.2, 8.4.1 |

### Accepted risks / out of scope

- **Same-bucket serialization latency** (DoS row-2) is accepted as the cost of strict enforcement
  (brief-sanctioned); measured, not eliminated.
- **Quota data at rest** relies on RDS SSE only (non-sensitive classification) — no field-level crypto.
- **Removing/unsetting a quota, `GET /v1/quotas`, kill-switch (`limit=0`), global/cross-tenant quotas,
  deferred effectiveness, per-quota windows** — all out of scope per the brief; not modeled.
- **Multi-key-per-tenant** (a separate ingest key + admin key sharing one tenant) is not supported
  this slice (Open Question 3); quotas bind to a single `api_key_id`.

### Threat-model diagram (Mermaid DFD)

```mermaid
flowchart TD
    admin[Admin/Ingest API client]:::ext
    subgraph edge[Trust boundary: public edge - ALB to FastAPI]
        t1(Tier-1 IP throttle + body guard)
        auth(require_api_key + Tier-2 throttle)
        scope(admin-scope gate):::warn
        put(PUT /v1/quotas handler)
        post(POST /v1/events handler)
        check(quota check + rollup increment - one txn):::warn
    end
    subgraph rds[Trust boundary: app to RDS Postgres]
        keys[(api_keys + scope)]
        quotas[(quotas)]
        rollup[(usage_rollup)]
        events[(events)]
    end
    redis[(Redis token buckets)]

    admin -- HTTPS: Bearer mtr_live_key -->|body: customer_id,metric,limit| t1
    t1 -- rate ok --> auth
    auth -. verify Argon2id .-> keys
    auth -. token bucket .-> redis
    auth --> scope
    scope -- scope=admin --> put
    auth --> post
    put -- upsert under principal.api_key_id --> quotas
    post -- insert event --> events
    post --> check
    check -- FOR UPDATE OF q --> quotas
    check -- read R / increment --> rollup

    classDef ext fill:#eee,stroke:#333;
    classDef warn fill:#ffe0b2,stroke:#b71c1c,stroke-width:2px;
```

⚠ high-risk nodes: the **admin-scope gate** (Spoofing/EoP) and the **quota check + rollup increment
single transaction** (Tampering/TOCTOU).

### Copy-paste visualization prompt

```text
Build a threat-model visualization for this feature (Meterly per-customer metric quotas).

ASSETS: quotas rows (per-tenant caps: api_key_id, customer_id, metric, limit_per_window);
api_keys.scope authorization attribute; usage_rollup hourly counters; events log; the admin API
key (Argon2id-hashed split token); the PUT /v1/quotas and POST /v1/events HTTP endpoints.

TRUST BOUNDARIES: (1) client <-> app: public internet -> ALB -> FastAPI, where unauthenticated
bytes become an authenticated, scope-bearing principal; (2) app <-> RDS PostgreSQL: the single
transaction that atomically checks the quota (SELECT ... FOR UPDATE on the quota row) and
increments the rollup.

STRIDE THREATS (threat; vector; severity; mitigation + concrete mechanism):
- Spoofing; unauthenticated/non-admin caller sets a cap; HIGH; require_api_key (Argon2id split
  token) + admin-scope assertion raising HTTP 403 in the PUT route dependency.
- Tampering; SQL injection via customer_id/metric; HIGH; anchored allowlist constr + parameterized
  SQLAlchemy text() bind params only.
- Tampering; mass-assignment of api_key_id/scope via the PUT body; HIGH; Pydantic extra='forbid';
  server sets api_key_id from the principal; scope is never a request field.
- Tampering; concurrent posts race the check-then-increment so usage exceeds the cap L (TOCTOU);
  HIGH; SELECT ... FOR UPDATE OF the quota row serializes writers; check + increment in one
  transaction; reject raises before increment and the transaction rolls back (no partial write);
  consistent lock order event->quota->rollup avoids deadlock.
- Repudiation; admin denies setting a blocking cap / client disputes a 429; MEDIUM; structured
  quota.upsert (who/what/when) and quota.rejected (userId, customer_id, metric, requestId) logs.
- Information disclosure; 429 body or logs leak current usage/limit; MEDIUM; three-field envelope
  {code,message,requestId} only, no usage numbers; logs omit totals; identifiers in body not URL.
- Denial of service; request flood; MEDIUM; Tier-1 IP throttle + Tier-2 per-api_key_id token
  bucket + 8 KiB body guard.
- Denial of service; FOR UPDATE serializes a hot quota'd bucket; MEDIUM (accepted); lock scoped to
  the quota row so only quota'd buckets serialize; p95 measured under load.
- Elevation of privilege; ingest key calls the admin route; HIGH; scope=='admin' gate -> HTTP 403.
- Elevation of privilege; a key reads/writes another tenant's cap (IDOR/BOLA); HIGH; every query
  filters api_key_id = principal.api_key_id; RLS policy quotas_tenant_isolation via SET LOCAL
  app.current_api_key_id (effective only if the app DB role is a non-owner, else FORCE RLS).

Render this as an OWASP Threat Dragon diagram. Output either (a) valid Threat Dragon JSON
importable at app.threatdragon.com, or (b) a labeled data flow diagram with trust boundaries if
JSON is not feasible. No additional context is available beyond what is in this prompt.
```

## ASVS Compliance

OWASP ASVS 5.0.0. **L1 + L2 are universal** for every triggered chapter; in-scope **L3** is listed
with justification. Requirement IDs are cited per threat in the STRIDE table above.

**Triggered chapters:** V1 (encoding/parameterized SQL), V2 (validation + business-logic limit +
transactional atomicity + anti-automation), V4 (API surface), V6 (API-key authentication), V8
(authorization — the admin gate + tenant isolation; the high-priority IDOR/BOLA chapter), V12 (TLS —
satisfied by existing ALB/RDS TLS, unchanged), V13 (config — docs off in prod, secrets in
manager — existing), V14 (data protection — no sensitive data in URL; non-sensitive classification),
V15 (secure coding — minimal response fields, mass-assignment, safe concurrency), V16 (logging + error
handling).

**`n/a`:** V3 (server-to-server API, no browser HTML/cookies; CORS handled under V4/edge), V5 (no file
handling), V7 (no sessions — stateless API keys), V9 (no JWT/self-contained tokens), V10 (no OAuth/OIDC),
V11 (no **new** crypto surface — existing Argon2id `11.4.2` key hashing and CSPRNG `11.5.1` key
generation are unchanged), V17 (no WebRTC).

**In-scope L3:**
- **V15.4.x — safe concurrency / TOCTOU-atomic check-then-act.** Justification: billing/usage
  integrity is breach-critical for a metering product — "usage never exceeds `L`" is the feature's
  core correctness guarantee, delivered by the `FOR UPDATE` quota-row lock + single-transaction
  check-then-increment.
- **V11.2.4 — constant-time comparison.** Already in scope for the auth verification cache
  (unchanged); noted for continuity.

**Waivers:** none for triggered L1/L2 code/config items (the feature's surface is covered by the
mechanisms above). Chapter `X.1` documentation items are advisory (org-level), not blocking.

## Acceptance criteria trace (PROJECT.md / CLAUDE.md "What done means")

- **Smoke check passes** → ✓ *Backend* / *Infrastructure*: no change to `/health` or app startup; the
  new route mounts on the existing app; deferred DB/Redis init preserved.
- **Security report clean** → ✓ *Threat Model* + *ASVS Compliance* (parameterized SQL, admin gate,
  tenant isolation/RLS, strict-enforcement concurrency, generic error envelope); AC18, AC22.
- **Tests pass at >= 85% coverage** → ✓ *Test strategy* + `acceptance.md` (every AC maps to a named
  test; unit-heavy pyramid, integration for the Postgres-only guarantees).
- **Docs updated for touched directories** → ✓ *Files affected* (system_architecture.md + per-dir
  READMEs + CLAUDE.md).
- **PR description written** → handled by the documentation stage (out of planning's hands; noted).
