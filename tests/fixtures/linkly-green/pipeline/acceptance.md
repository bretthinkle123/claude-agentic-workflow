---
feature: "Linkly — minimal URL shortener API (first feature)"
source_of_truth: "PROJECT.md"
criteria_total: 18
derived: false   # criteria are taken from PROJECT.md explicit requirements + "What done means"
---

# Acceptance criteria — Linkly URL shortener API (first feature)

Each row is the downstream definition-of-done. Implementation builds to this file;
testing maps each ID to a test (`criteria_covered`); plan-audit flags any untraced
criterion. "How verified" names a concrete test, endpoint behavior, or mechanism.

| ID | Criterion | File / layer | How verified |
|---|---|---|---|
| AC1 | `import src.main` succeeds and exposes `app`; `GET /health` returns `200 {"status":"ok"}` with no auth. | `src/main.py`, `src/api/health.py` | Smoke check (`import src.main` + HTTP 200 at `/health`); `tests/integration/test_links_api.py::test_health_ok`. |
| AC2 | `POST /links` with a valid bearer key and `{"url": "<https url>"}` returns `201` and `{"code":"<6 base62>","short_url":"<base_url>/<code>"}`. | `src/api/links.py`, `src/api/schemas.py`, `src/domain/service.py` | `tests/integration/test_links_api.py::test_create_link_happy_path` (asserts 201, 6-char base62 code, short_url shape). |
| AC3 | `POST /links` without a valid `Authorization: Bearer <key>` returns `401` and creates no row. | `src/auth/facade.py`, `src/api/deps.py`, `src/api/links.py` | `tests/integration/test_links_api.py::test_create_requires_auth`; `tests/unit/test_auth_facade.py` (missing/malformed/unknown → 401). |
| AC4 | `GET /{code}` for a known code returns a `302` redirect with `Location` = the stored URL. | `src/api/links.py`, `src/data/repository.py` | `tests/integration/test_links_api.py::test_redirect_known_code` (asserts 302 + Location). |
| AC5 | `GET /{code}` for an unknown (well-formed) code returns `404`. | `src/api/links.py`, `src/domain/service.py` | `tests/integration/test_links_api.py::test_redirect_unknown_code_404`. |
| AC6 | `url` must be a syntactically valid `http(s)` URL ≤ 2048 chars; otherwise `422` (invalid scheme, non-URL, or > 2048 all rejected) and no row created. | `src/api/schemas.py` (`CreateLinkRequest`) | `tests/unit/test_schemas_validation.py` (http/https valid; `javascript:`/`ftp:`/non-URL → 422; 2049-char → 422). |
| AC7 | `code` is base62 and exactly 6 chars; a malformed code path is rejected `422` before any DB lookup. | `src/api/links.py` path contract | `tests/unit/test_schemas_validation.py::test_code_path_contract`; integration `test_redirect_malformed_code_422`. |
| AC8 | base62 `encode`/`decode` round-trips: `decode(encode(n)) == n` for all `n` in `[0, 62^6)`. | `src/domain/codec.py` | `tests/property/test_codec_roundtrip.py` (Hypothesis over the id range). |
| AC9 | `encode_id(id)` produces exactly 6 base62 characters for ids in the supported range. | `src/domain/codec.py` | `tests/unit/test_codec.py::test_encode_id_width` + property assertion in `tests/property/test_codec_roundtrip.py`. |
| AC10 | Idempotency: same `Idempotency-Key` + same body returns the **same** `code` and creates **exactly one** row. | `src/domain/service.py`, `UNIQUE(owner, idempotency_key)` (migration 0001) | `tests/integration/test_idempotency_api.py::test_same_key_same_body_one_row` (asserts identical code + row count == 1). |
| AC11 | Idempotency: same key + **different** body returns `409` and does not overwrite the original link. | `src/domain/service.py`, `src/api/links.py` | `tests/integration/test_idempotency_api.py::test_same_key_different_body_409`. |
| AC12 | No `Idempotency-Key` header → unkeyed creates are allowed and produce distinct rows (NULL keys don't collide). | `src/data/models.py`, migration 0001 (nullable key) | `tests/integration/test_idempotency_api.py::test_no_key_distinct_rows`. |
| AC13 | Concurrency: N identical `POST /links` (same key+body) fired concurrently still yield exactly one row and one code (IntegrityError-loser re-reads). | `src/data/repository.py`, `src/domain/service.py` | `tests/resilience/test_concurrency_idempotency.py` (asyncio.gather of N requests; assert single row/code). |
| AC14 | The `links` schema (`id`, `code` UNIQUE, `url`, `owner`, `idempotency_key` nullable + UNIQUE per owner, `created_at`) is provisioned by an **Alembic migration**, never `metadata.create_all`; migration is reversible. | `alembic/versions/0001_create_links_table.py`, `alembic/env.py` | `tests/resilience/test_migration_roundtrip.py` (`upgrade head → downgrade base → upgrade head`; asserts table + both unique indexes present after upgrade, absent after downgrade). |
| AC15 | Structured logs are emitted for create and redirect events with 5W+H fields; the raw API key, raw `owner`, and target `url` never appear in any log. | `src/logging/__init__.py`, `src/logging/middleware.py`, `src/api/links.py` | `tests/unit/test_logging_redaction.py` (capture logs: assert `link.create`/`link.redirect` events present with `owner_hash`/`code`/`requestId`; assert no `authorization`, raw key, or `url` in output). |
| AC16 | No secrets in source: API keys are read only through the `config.py` facade from env bootstrap inputs; no key literal, no committed `.env`; `.env.example` holds names only. | `src/config.py`, `.env.example` | Security report (no hardcoded-secret findings); `tests/unit/test_auth_facade.py` loads keys via the facade only. |
| AC17 | Tests pass with **combined coverage ≥ 80%** lines over `src/`; security report clean (no High/critical findings). | whole `src/` tree; `.pipeline/security-report.md` | `pytest --cov=src` combined ≥ 80%; security agent report shows clean. |
| AC18 (perf) | **Performance budget:** `GET /{code}` p95 **< 50 ms** under **100 req/s** on a warm local instance. | `src/api/links.py` redirect path, `UNIQUE(code)` index, SQLite WAL (`src/data/database.py`) | `tests/perf/redirect_smoke.js` (k6) or Locust driving 100 rps; record p95 vs 50 ms budget in `test-results.json.perf`. |

## Notes
- AC1 satisfies the smoke/build gate; AC17 + AC18 are the "resilience/perf modes
  recorded" part of PROJECT.md "What done means."
- AC18 is the explicit performance budget; because it is an acceptance criterion it
  rides `criteria_covered` and the deploy gate (testing's performance mode measures
  against it).
- Out-of-scope items (frontend, infra, Dockerfile, real IdP, analytics, gateway rate
  limiting, production Secrets Manager) are intentionally absent and are recorded as
  accepted risks / Open questions in `plan.md`, not as acceptance criteria.
