# Debug notes

## 2026-07-06 — Remediation: starlette CVEs (deploy-gating, CVSS 7.5)

**Role:** remediation (security critical finding). **Retry counter:** remediation 0 → 1 (of 3).

**Finding (reproduced):** `.pipeline/osv.json` and the security report flag
`starlette 0.41.3` (poetry.lock) with 10 CVEs, four HIGH / CVSS 7.5
(GHSA-7f5h-v6xp-fcq8, GHSA-82w8-qh3p-5jfq, GHSA-wqp7-x3pw-xc5r, PYSEC-2026-249).
`osv_max_cvss = 7.5` trips the deploy gate's deterministic `>= 7.0` floor (no
waiver), blocking deploy even though app code scanned clean. Confirmed the pinned
version by reading the lock and the OSV output before touching anything.

**Root cause:** `starlette 0.41.3` is a transitive dependency pinned in range by
`fastapi 0.115.6` (`starlette>=0.40.0,<0.42.0`). The vulnerable ASGI library
itself is the defect; nothing in Meterly's code is wrong. All ten CVEs are fixed
in `starlette 1.3.1` (per the report's fixed-in table). Because fastapi caps the
starlette range, starlette cannot move without fastapi moving too.

**Compatibility investigation (evidence):** queried the index and the PyPI JSON
metadata for fastapi's starlette constraint across versions:
- fastapi 0.132.0 → `starlette<1.0.0` (excludes 1.3.1)
- fastapi **0.133.0** → `starlette>=0.40.0` (first release to lift the `<1.0.0`
  cap; admits 1.3.1)
- fastapi 0.135.0+ → `starlette>=0.46.0`; latest 0.139.0 → `starlette>=0.46.0`
Chose the **minimal** compatible pair — fastapi 0.133.0 + starlette 1.3.1 — to
keep behavioral drift small rather than jumping to fastapi 0.139.0. Only other
starlette constraint in the lock is an extras ref `>=0.19.1`, satisfied by 1.3.1.

**Fix:** `pyproject.toml` — bumped `fastapi 0.115.6 → 0.133.0`, added exact pin
`starlette = "1.3.1"` (exact-pin house style). Re-resolved with
`poetry lock`, synced the venv with `poetry sync`
(fastapi 0.115.6→0.133.0, starlette 0.41.3→1.3.1; pulled in transitive
annotated-doc 0.0.4, typing-inspection 0.4.2). Left `pytest 8.3.4` untouched
(dev-only, non-gating, per task). No application/source code changed.

**Proof (fails-before / passes-after):** added `tests/test_dependency_pins.py`, a
security-regression guard asserting installed `starlette >= 1.3.1` (CVE-clearing
floor) and `fastapi >= 0.133.0` (admits it). Ran it against the pre-upgrade venv
→ **both failed** (0.41.3 < 1.3.1; 0.115.6 < 0.133.0). After the upgrade →
**both pass**. Full suite: 48 → 50 tests, green on 4 consecutive runs (18s each) —
deterministic, no async/event-loop regression from the starlette 0.x→1.x major.
Smoke check (`~/.claude/hooks/smoke-check.sh`, greenfield import path) → exit 0,
`.pipeline/smoke-status.json` = `pass`.

**Dead ends / notes:** poetry was not on PATH; located it at
`~/AppData/Roaming/Python/Python310/Scripts/poetry.exe` (2.4.1, bound to the
in-project `.venv`). Observed benign `StarletteDeprecationWarning`s for renamed
status constants (`HTTP_413_REQUEST_ENTITY_TOO_LARGE`,
`HTTP_422_UNPROCESSABLE_ENTITY`) at `src/main.py:21` — the old names still work in
1.3.1, so this is not a break. Renaming them is a future-hardening chore, left out
of this fix to avoid unrelated source churn.

## 2026-07-06 — Remediation: Tier-2 rate limiter NameError (missing get_logger import)

**Role:** remediation (failing test). **Retry counter:** remediation 1 → 2 (of 3).

**Finding (reproduced):** `.pipeline/test-results.json` flagged two failing
integration tests — `tests/integration/test_rate_limit.py::test_two_principals_sharing_one_ip_get_independent_buckets`
and `::test_one_principal_across_two_ips_still_shares_one_bucket`. Ran them before
touching anything and observed the exact failure: `NameError: name 'get_logger'
is not defined` raised from `src/auth/rate_limit.py:163` inside
`enforce_tier2_rate_limit`. The Tier-2 dependency is invoked from
`src/api/routes/usage.py`, so the NameError propagates as an unhandled 500 —
every Tier-2 429 (and the Redis-outage fail-open branch at line 157) is silently
converted to a 500, defeating rate limiting (AC14/AC16).

**Root cause #1 (the reported bug):** `enforce_tier2_rate_limit` calls
`get_logger(service="meterly").warning(...)` at two sites (line 157 fail-open,
line 163 429-deny) but the module never imported the logging facade. Every
sibling module (`src/services/*`, `src/api/*`, `src/auth/__init__.py`) does
`from src.logging import get_logger`; `rate_limit.py` alone omitted it.

**Fix #1:** added `from src.logging import get_logger` to the module imports
(one line, matching the house convention). No call-site or behavioral change —
the existing inline `get_logger(...)` calls now resolve.

**Root cause #2 (unmasked by the fix):** with the NameError gone, the 429 path
worked, but `test_one_principal_across_two_ips_still_shares_one_bucket` then
failed *deterministically* when run in the same session as the sibling test
(passed 8/8 in isolation, failed 6/6 together). Diagnosed via captured request
logs: the second test's *first* request (api_key_id=1) returned 429
"tier2_bucket_exhausted". Cause: `truncate_tables` truncates Postgres with
`RESTART IDENTITY`, so `api_keys.id` (the Tier-2 bucket key) resets to 1 each
test, but the session-scoped Redis was never flushed — the first test's exhausted
`ratelimit:tier2:1` bucket leaked into the next test. A test-isolation defect in
the fixture, not production code (the limiter correctly keys on api_key_id).

**Fix #2:** `tests/integration/conftest.py` — `truncate_tables` now also
`flushdb()`s Redis per test (added `redis_url` dep), mirroring the DB truncate so
bucket state is isolated per test. Aligns with the fixture's stated intent
("each test starts from a clean, empty schema").

**Proof (fails-before / passes-after):**
- Reported tests: reproduced the NameError before the fix; after Fix #1 + Fix #2
  both pass, and the full `test_rate_limit.py` file passes deterministically 6/6
  consecutive runs (was 6/6 failing on the isolation bug before Fix #2).
- New regression test `tests/test_rate_limit_fail_open.py::test_tier2_fails_open_and_logs_when_redis_backend_is_unavailable`
  covers the *fail-open* branch (line 157) that no existing test drove: mocks the
  Tier-2 limiter to raise, asserts `enforce_tier2_rate_limit` returns None (fails
  open) without raising. Fails-before demonstrated in the scratchpad (removed
  `get_logger` from the module namespace to recreate the pre-fix state → NameError,
  never by reverting the tracked file); passes-after with the import in place.
- Full suite `.venv/Scripts/python.exe -m pytest tests/ -q` → **77 passed** (76
  prior + 1 new regression test), 0 failed.
- Smoke check `~/.claude/hooks/smoke-check.sh` → exit 0 (greenfield import path).

**Dead ends / notes:** the initial combined run showed the isolation failure as a
one-off (looked like timing), but re-running the file 6× proved it deterministic —
worth the extra runs before declaring flaky-vs-real. Pre-existing benign
`StarletteDeprecationWarning`s (renamed status constants at `src/main.py:21`) are
unrelated and untouched.
