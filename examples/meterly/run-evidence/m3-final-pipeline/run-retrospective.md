# Pipeline run retrospective — Meterly feature 1 (2026-07-06)

Written by the orchestrator session for a follow-up session tasked with **updating the
pipeline based on this run's feedback**. Everything referenced is on disk in this repo
folder or under `~/.claude/`. The pipeline definition itself lives in:
`~/.claude/hooks/*.sh` (gates/telemetry), `~/.claude/agents/*.md` (stage agents),
`~/.claude/skills/pipeline-orchestration/` (the orchestrator contract),
`~/.claude/pipeline-templates/` (bootstrap + summaries), and per-project scaffold copied
into `scripts/ci/` + `.github/workflows/` at bootstrap.

## Outcome

- PR #1 opened: https://github.com/bretthinkle123/meterly-pipeline-test/pull/1
  (commit `faabe9d`, branch `feature/usage-metering-ingest`, 140 files, 14,131 insertions).
- All deterministic gates passed; both human checkpoints exercised (plan, diff).
- Human approved the diff **as-is**, deferring 10 verified code-review findings (below).

## Per-stage machine summary

Quoted from `.pipeline/run-summary.json` (regenerated 2026-07-06T21:25:10Z, all 8 stages;
per-line detail in `.pipeline/run-log.jsonl`, 20 lines):

| stage | invocations | caps | model | last_status |
|---|---|---|---|---|
| planning | 1 | 0 | opus | pass |
| plan-audit | 1 | 0 | sonnet | pass |
| implementation | 5 | 3 | sonnet | pass |
| debugging | 3 | 1 | opus | pass |
| security | 3 | 0 | opus | clean |
| testing | 3 | 1 | sonnet | pass |
| documentation | 2 | 1 | haiku | pass |
| deployment | 2 | 1 | sonnet | pass |

Totals: 20 log lines, **7 capped lines**, 0 loop-cap events, `first_pass_clean: false`.
Loop (`.pipeline/loop-state.json`): GREEN in **3 of 5 cycles**, compute 1218s/1800s,
status `completed`. Two remediation passes used (of 3 budgeted): starlette CVE bump,
rate-limit `get_logger` NameError.

## Pipeline-engineering feedback (the actionable part)

Ordered by how much each cost this run.

1. **Agent maxTurns caps are the dominant friction.** 7 of 20 log lines are cap-outs;
   implementation alone capped 3× (each resume = cache-cold re-read + orchestrator
   babysitting). Greenfield first features are much bigger than the caps assume.
   Options: raise maxTurns for implementation/testing; or make the agents checkpoint +
   self-summarize before the cap; or split implementation into app/infra sub-passes.
   The `log-run.sh <stage> "" capped` + SendMessage-resume protocol worked well as
   recovery — the cost is the repeated cold context, not lost work.

2. **`bootstrap-project.sh` wrote a self-breaking `SMOKE_BUILD_CMD`.** It emitted
   `SMOKE_BUILD_CMD='python -c "import src.main"'` but `smoke-check.sh` expands it
   **unquoted**, so the nested quotes word-split → `SyntaxError`. Also `python` on bare
   PATH wasn't the project venv. Fix candidates: bootstrap should emit space-free,
   venv-explicit, `-m`-module commands (the working form:
   `.venv/Scripts/python.exe -m scripts.smoke_import_check`), or smoke-check.sh should
   `eval` the command instead of word-splitting. This cost one full implementation
   resume cycle to diagnose.

3. **`guard-source-markers.sh` false-positives on its own scaffold.** The repo copies
   (`scripts/ci/guard-source-markers.sh`, `pipeline-ci.yml` step name) spell the marker
   literals in comments/docs and tripped the global Stop hook. Fixed this run by
   rewording prose (regex untouched, regression-verified). Durable fix: the template
   scaffold in `~/.claude/pipeline-templates/ci/` should ship with non-matching prose,
   or the guard should self-exclude its own definition files by path.

4. **The security stage reported `clean` twice, then /code-review found 10 CONFIRMED
   bugs.** Classes the scanners structurally missed: deploy-topology bugs (Tier-1
   throttle keyed on ALB node IP — no proxy-header trust; `/health/ready` not
   throttle-exempt while being the ALB probe path), DB-privilege semantics (RLS ENABLE
   without FORCE + app-role table ownership = inert backstop; append-only declared but
   UPDATE/DELETE granted), async-runtime hazards (Argon2id and boto3 sync on the event
   loop), contract-vs-implementation drift (secrets facade promises rotation re-fetch;
   engine never re-resolves; Sentry scrubber misses query_string). Suggestion: add these
   as named checks to the security agent's reconciliation step or to
   api-edge-conventions/data-protection-conventions acceptance criteria — they are
   checkable by inspection, no scanner needed. The multi-angle /code-review pre-step
   earned its cost; consider promoting parts of it earlier (post-implementation).

5. **Security stage path-handling bug (first pass):** it wrote `semgrep.json` into a
   literal `C:/Users/.../scratchpad/...` directory tree **in the repo root** (untracked
   junk, nearly committed; the debugging agent removed it). Second pass routed temp
   output correctly after being told. Worth a hard rule in the security agent prompt:
   raw scanner output goes to `.pipeline/` or OS temp, verify no tree writes.

6. **`criteria_covered` denominator honesty:** testing recorded `covered: 24, total: 24`
   while its own `by_id` marks AC20 `covered: false` (reason: "security agent's
   deliverable"). The numbers passed the deterministic gate on a judgment call. The
   contract should say explicitly how out-of-suite criteria are counted (e.g. a
   `delegated: security` flag that the gate accepts) so the arithmetic can't be quietly
   generous.

7. **Loop wall-clock budget (7200s) is tight when agents cap out:** cycle 3 started at
   6223s/7200s. Cap-resume overhead eats the budget that was sized for clean cycles.
   Either exclude human-wait/resume time from the wall clock or size it to the cap
   behavior observed here.

8. **AC-PERF needed orchestrator improvisation.** Testing initially punted on the 500
   req/s load run ("no k6 available"); it succeeded when explicitly told to run
   grafana/k6 via Docker against testcontainers. Bake that recipe into test-conventions
   so perf criteria are attempted by default. Result on this host: throughput 497.75
   req/s (meets ≥475), POST p95 75.47ms (misses <50ms; shared-Docker-host caveat), GET
   p95 13.19ms (meets). The gate checks measurement *completeness*, not the perf
   verdict, so this shipped with the miss disclosed in the PR — by design, but confirm
   that's the intended semantics.

9. **Approval-marker guard blocks the orchestrator too** (`touch .pipeline/plan-approved`
   denied). Correct behavior, but the orchestration skill text says the orchestrator
   records markers on "continue" — align the doc with reality: the human runs `touch`/
   `approve-diff.sh` in a TTY themselves.

10. **Minor telemetry quirks:** deployment log lines carry `files_changed: 0` and the
    `feature` field flips from `main` to the branch name mid-run (branch created at
    deployment), splitting the feature's identity across lines. `run-summary.sh` had to
    be re-run manually after documentation/deployment (it was generated at loop-GREEN,
    step 4c, before two stages had run — consider a second stamp after deployment).

## The 10 deferred code-review findings (all verifier-CONFIRMED)

Shipped as-is by human decision; these are the follow-up backlog. Full context in the PR
body and the session memory (`feature1_shipped_findings.md`).

1. `alembic/versions/0001_create_api_keys_and_events.py:66` — RLS backstop inert:
   ENABLE (not FORCE) + app role owns tables (alembic/env.py uses the app credential);
   owners bypass non-FORCE RLS. Integration RLS test passes vacuously.
2. `src/api/middleware.py:118` — Tier-1 throttle keys on `request.client.host` = ALB
   node IP (no `--forwarded-allow-ips`/ProxyHeadersMiddleware anywhere): all clients
   share one bucket per node; one attacker 429s every tenant pre-auth.
3. `src/api/middleware.py:68` — body cap reads only Content-Length; chunked
   Transfer-Encoding bypasses the 8 KiB limit → unbounded buffering/OOM.
4. `src/auth/api_key.py:70` — Argon2id verify (64 MiB, time_cost=3) runs sync on the
   event loop on every cache miss; likely primary cause of the p95 miss.
5. `src/config/secrets.py:80` — sync boto3 `get_secret_value` on the event loop, lazy on
   first request, default 60s timeouts → whole-worker freeze, ALB flapping risk.
6. `src/auth/rate_limit.py:157` (mirrored middleware.py:126) — fail-open on blanket
   `except Exception` (any persistent error silently disables limiting);
   `rate_limit_per_sec > 0` validated nowhere. (Sub-claim refuted: a zero-limit key
   fails CLOSED — Lua 1/0=inf, allowed=0.)
7. `src/observability/sentry.py:21` — before_send scrubs headers/body but not
   query_string/url → GET /v1/usage leaks customer_id PII to Sentry on any unhandled
   exception.
8. `src/db/session.py:32` — DB URL resolved once at engine creation, no re-resolution
   hook; contradicts the secrets facade's rotation contract → post-rotation auth
   failures until redeploy.
9. `infra/modules/data/main.tf:84` — events declared append-only (STRIDE R1) but app
   role granted UPDATE/DELETE; no REVOKE/trigger anywhere.
10. `src/api/middleware.py:91` — `_TIER1_EXEMPT_PATHS` exempts `/health` but not
    `/health/ready` (the ALB target + canary probe path); combined with #2 an attacker
    can 429 the probes → target drain.

Below-cap verified extras: no CHECK constraint enforcing hour-alignment on
`window_start`; `_require_authenticated_and_throttled` copy-pasted across both route
files; error envelope hand-built in 3 places; `pool_pre_ping` round-trip per checkout;
INSERT+rollup mergeable into one CTE (saves a round-trip); misleading middleware-order
comment in `src/main.py:72` (actual order is correct). Refuted (don't chase): 500s DO
pass back through the header middleware; CWD-relative `alembic.ini` is safe in the
shipped container (WORKDIR /app); zero-limit keys fail closed. Conventions: CLAUDE.md:18
references `docs/pipeline-deployment-targets.md`, which does not exist in the tree.

## Artifact map (all on disk, `.pipeline/` is gitignored but readable locally)

- `.pipeline/run-log.jsonl`, `run-summary.json`, `loop-state.json` — telemetry
- `.pipeline/plan.md`, `acceptance.md`, `plan-audit.md` — planning artifacts (also
  archived in `docs/decisions/main/`)
- `.pipeline/security-report.md`, `security-status.json` — final clean scan
- `.pipeline/test-results.json`, `test-quality.json` — 83/83, 89.82% lines, perf block
- `.pipeline/debug-notes.md` — both remediation root-causes + evidence
- `.pipeline/pr-description.md`, `review-manifest.json`, `diff-approved` — review chain
- `.pipeline/surface-delta.md` — implementation's STRIDE delta notes
- Session memory (shared with any window opening this folder):
  `~/.claude/projects/c--Users-brett-OneDrive-Documents-GitHub-meterly-pipeline-test/memory/`
