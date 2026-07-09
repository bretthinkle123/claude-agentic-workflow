# Debug notes — GET /v1/usage/export

## 2026-07-09 — AC16 export p95 blow-up at the 100,000-row cap (remediation)

### Finding (testing gate, AC16)
`GET /v1/usage/export` p95 at the 100k-row cap measured **25,210 ms** (testing's
independent re-measure) / earlier **~9.8 s** (implementation's measure) against
the plan's **proposed 500 ms** target — 20–50x over. Implementation's disclosure
attributed it to "per-row Python CSV encoding overhead, not DB time".

### Reproduced first (before touching anything)
Ran `tests/integration/test_usage_export_perf.py` (real Postgres testcontainer,
in-process ASGI, 100,000 rows). Baseline p95 this session (the test's scratch
measurement file): **10,720.92 ms**, `meets_documented_budget: false`. Reproduced.
(The gap vs testing's 25,210 ms is host load/hardware; both are 20–50x over.)

### Root cause — measured, not assumed (the disclosure was only partly right)
I profiled each layer of the path in isolation (scratch benchmarks, 100k rows):

| Layer measured in isolation | time |
|---|---|
| Pure CSV encoding (escape+format+writerow, no I/O) | ~360 ms |
| ...of which `escape_csv_text_cell`'s per-char generator + `_is_safe_character` + `ord()` | ~2.4M genexpr / 2.2M `ord` calls — the encoding hot spot |
| Real `stream_export_csv` async generator consumed directly (fake in-mem DB) | ~387 ms |
| Through a **bare** StreamingResponse + ASGITransport (no middleware, fake DB) | ~441 ms |
| Real DB server-side cursor draining 100k rows (no CSV, no HTTP), default fetch | ~1,014 ms |
| ...same, with `yield_per=5000` | ~609 ms |
| Full real `stream_export_csv` on the real DB, **minimal** Starlette app (no middleware) | ~1,644 ms |
| ...the same path with **4 nested pass-through `BaseHTTPMiddleware`** layers added | **~6,944 ms** |

The server-side `request.completed` log confirmed the handler *returns* in 16–94 ms;
the ~10 s is spent **after** the handler returns, in the streaming phase.

**The dominant cost is the CHUNK-PER-ROW streaming pattern, not encoding.** The
generator did `yield _drain(buffer)` **per row** → 100,001 chunks at the cap. The
app stack (`src/main.py`) has **four nested Starlette `BaseHTTPMiddleware`**
subclasses (`RequestContextMiddleware`, `SecurityHeadersMiddleware`,
`BodySizeLimitMiddleware`, `Tier1EdgeThrottleMiddleware`).
`BaseHTTPMiddleware` re-pumps **every** streamed chunk through its own anyio
memory-object-stream; with 4 nested layers, all 100k tiny chunks traverse 4
anyio hops each, with async scheduling per hop. Cost ≈ (chunk count × middleware
layers), so it exploded at the cap. Encoding (~360 ms) and DB drain (~1 s) were
secondary. The implementation's disclosure conflated the fast COUNT + bounded
sort (genuinely fast) with the row-*drain* + per-chunk-fan-out cost.

### Fix — minimal, localized, WITHIN the human-approved design
Server-side cursor, pre-flight COUNT, 100k cap, and OWASP formula-escape
semantics all preserved. Three complementary in-scope optimizations:

1. **`src/services/usage_export_service.py` — batch rows per chunk** (`_ROWS_PER_CHUNK
   = 1000`) instead of one chunk per row. Header still yielded first as its own
   chunk (AC12 empty-result / AC9 first-bytes). At the cap this is ~101 chunks,
   not 100,001 — still genuinely streamed, still constant memory (buffer holds ≤
   one batch). **Primary lever.**
2. **`src/api/csv_export.py` — precompiled escape.** Replaced the per-character
   Python strip loop in `escape_csv_text_cell` with a C-level `str.translate`
   deletion table. Semantics **identical** (verified 0 mismatches across all
   codepoints 0x00–0x11F and lead/mid combos vs. the old logic, and by the
   unchanged AC10 tests). Encoding 360 → 246 ms.
3. **`src/repositories/usage_repo.py` — `yield_per=5000`** on the `session.stream()`
   server-side cursor. Tunes how many rows are fetched per round-trip; does NOT
   abandon the cursor. Controlled tight-loop DB drain 1,014 → 609 ms; memory
   still bounded (≤ one batch buffered client-side).

### Proven
- **Regression test (fails-before / passes-after):**
  `tests/test_usage_export_service.py::test_stream_export_csv_batches_rows_into_few_chunks`
  — a 5,000-row export must arrive in < 500 chunks (batched) **and** > 1 chunk
  (still streamed), with byte-identical CSV. Per-row impl produced 5,001 chunks
  (**fails**); batched impl produces 6 (**passes**). Fails-before confirmed via a
  scratch reproduction of the per-row logic (real tree never reverted);
  passes-after **12/12** consecutive runs (deterministic, no DB/timing).
- **No suite regressions:** `test_csv_export.py` + `test_usage_export_service.py`
  + `test_schemas_usage_export.py` = **37 passed**; `test_usage_export_endpoint.py`
  + `test_usage_export_perf.py` = **20 passed** (AC2/AC5–AC13/AC17/AC19/AC20/AC22
  incl. AC9 streaming-multiple-chunks and AC10 formula-escape all green with
  batching + the escape refactor).

### Before / after p95 at the 100,000-row cap (real perf test, full app stack)
- **BEFORE:** 10,720.92 ms (this session) / 25,210 ms (testing's independent measure)
- **AFTER (all 3 opts):** ~1.4 s median, ~2.0 s p95 — the 2-sample perf test
  recorded 1,454.93 ms (batching+escape) and 2,042.80 ms (all 3); a stable
  10-sample re-measure through a 4-`BaseHTTPMiddleware` stack gave
  **min 1,139 ms / median 1,374 ms / p95 2,073 ms**. Net: **~7–17x faster**, and
  the chunk-per-row anti-pattern is eliminated.

### Best achieved STILL exceeds 500 ms — budget decision escalates to the human
Even after this genuine optimization pass, p95 (~1.4–2.0 s) remains above the
plan's **proposed** 500 ms. The remainder is dominated by **irreducible work
within the approved design**:
- Draining 100k rows over the async **server-side cursor**: ~0.6 s even at
  `yield_per=5000`. A buffered `fetchall` (which would ABANDON the mandated
  constant-memory cursor) was ~0.32 s — so the cursor floor is already ≥0.6 s.
- Python-level CSV encoding of 100k rows × 4 cells: ~0.25 s.
- Even the theoretical floor that DISCARDS the cursor (fetchall 0.32 s + encoding
  0.25 s ≈ 0.57 s) is already over 500 ms; with the mandated cursor it is ~0.85–1.0 s.

**500 ms is not achievable at the 100k-row cap within the approved design**
(server-side cursor + per-row stdlib `csv` + streaming through the
`BaseHTTPMiddleware` stack). Per the task constraint I did **not** weaken AC16 or
fabricate a pass — the perf test still asserts correctness and records the real
p95 (`meets_documented_budget: false`). The budget-number decision (plan Open
Question 1) is the human's: confirming 500 ms as binding at the 100k cap would
require a **redesign** (e.g. C-accelerated/precomputed CSV materialization, or a
lower row cap, or moving the export off the `BaseHTTPMiddleware` request path) —
that is a planning-escalation question, not a patch. This remediation delivers
the ~7–17x reduction and removes the pathological anti-pattern; the residual
gap to 500 ms is the escalation.

### Dead ends / notes
- First hypotheses (encoding-only; ASGI-framing-only) were **wrong** in
  isolation — each was < 0.5 s alone. The amplifier was the middleware × chunk
  count interaction, invisible unless the full middleware stack is in the path
  (minimal-app benchmark showed only ~1.6 s; the 4-layer benchmark reproduced ~7 s;
  the real app with real per-chunk middleware work + Argon2 auth reproduced ~10 s).
