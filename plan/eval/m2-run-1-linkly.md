# M2 test plan — "Linkly" evaluation run

> Purpose: drive the pipeline end-to-end on one realistic greenfield feature that triggers as many
> conditional paths as possible, so we can evaluate the *actual quality* of what it generates (not
> just the design). Run this in a **throwaway repo**, then paste the evidence bundle (bottom) back
> into a session in `claude-agentic-workflow`.
>
> Why "Linkly": a tiny URL-shortener API hits the migration round-trip mode (5c), property/fuzz mode
> (5d), concurrency/idempotency mode (5e), perf-budget mode (5f), the security migration scan, the
> auth conventions + STRIDE, and logging conventions — a near-complete trigger sweep in one feature.
>
> **Important design fact this plan relies on:** the pipeline does **not commit** during the run.
> Bootstrap commits nothing; the *deployment* agent makes the first commit (optional, last step). So
> every artifact you care about — generated app code and tests — lives in the **working tree,
> uncommitted**, and the smoke check runs in **greenfield mode** (a build/import check, not an HTTP
> probe) the whole time. The evidence collector and instructions below are built around that.

---

## 0. Prerequisites (one-time, on this machine)

```bash
jq --version            # required by deployment-gate / loop-guard / record-clean
docker info             # required by semgrep-scan.sh + trivy-scan.sh (Docker Desktop running)
python --version        # 3.11+ ; the default backend stack
git --version
gh auth status          # only needed if you run the OPTIONAL deployment step

# ANTHROPIC_API_KEY must be set in the environment the agents run in (bootstrap's first-run
# memory flags this). In an authenticated Claude Code session this is normally already handled.
```

Publish the **current** pipeline source to `~/.claude` (PR E was never installed — do this first):

```bash
cd /c/Users/brett/OneDrive/Documents/GitHub/claude-agentic-workflow
bash scripts/install-global.sh          # no-arg = actually publish ('dry-run' is the arg that previews)
bash scripts/list-skills.sh             # sanity: secrets-management=on-demand, test-conventions=PRELOAD
```

If it reports collisions, read the message before using `--force`.

---

## 1. Create + bootstrap the throwaway repo (do NOT commit)

```bash
cd /c/Users/brett          # anywhere OUTSIDE the pipeline repo
mkdir linkly && cd linkly
git init
python -m venv .venv && source .venv/Scripts/activate   # Git Bash on Windows; deps install here

# Bootstrap writes per-project files AND pre-wires the smoke check to match the spec below
# (src/ layout, /health route). --build is what the greenfield import-check actually runs.
bash ~/.claude/pipeline-templates/bootstrap-project.sh \
  --start  "python -m uvicorn src.main:app --host 0.0.0.0 --port 8000" \
  --health "http://localhost:8000/health" \
  --test   "pytest --cov=src" \
  --build  'python -c "import src.main"'
```

**Do not `git commit`.** Staying uncommitted keeps smoke in greenfield/build-check mode (the
intended first-run behavior) and matches how the pipeline expects to operate until deployment. The
deployment agent (optional, last step) makes the first commit.

---

## 2. Write the feature spec

Bootstrap created a `PROJECT.md` **stub** — replace its contents with **exactly** this (it states a
perf budget, an auth requirement, a migration-bearing data model, an idempotent write, and a
validation contract — the five triggers — and pins the `src/` layout + `/health` route so the smoke
defaults align):

```markdown
# Linkly — minimal URL shortener API

## What this is
A small HTTP API that creates short codes for URLs and redirects them. Greenfield. Backend only.

## First feature (this build only)
1. `POST /links` — create a short link. **Requires authentication.** Body: `{ "url": "<https url>" }`.
   Returns `{ "code": "<6-char base62>", "short_url": "<host>/<code>" }`.
   - **Idempotent:** with an `Idempotency-Key` header, repeating the same key+body returns the same
     code and creates exactly one row (no duplicate links).
2. `GET /{code}` — public, no auth. 302-redirect to the original URL; 404 if unknown.
3. `GET /health` — liveness, no auth.

## Data
- A `links` table: `id`, `code` (unique), `url`, `owner`, `idempotency_key` (nullable, unique per
  owner), `created_at`. Provisioned via a **database migration** (not auto-create).

## Validation contract
- `url` must be a syntactically valid `http(s)` URL ≤ 2048 chars; reject otherwise (422).
- `code` is base62, exactly 6 chars; the encode/decode of an id must round-trip.

## Auth
- Simple **bearer API key** behind an auth facade (no external IdP for this build — keep it
  self-contained). `owner` is derived from the key. Protect `POST /links` only.

## Stack
- Python 3.11, **FastAPI**, SQLAlchemy + **Alembic** migrations, SQLite for local/scratch.
- **Layout: `src/main.py` exposes `app`** (so `import src.main` and `/health` match the smoke check).
- Tests: pytest (+ Hypothesis for property tests); load via k6 or Locust.

## Non-functional / acceptance
- **Performance budget:** `GET /{code}` p95 < 50 ms under 100 req/s on a warm local instance.
- All inputs validated; no secrets in source; structured logs for create/redirect events.

## Explicitly out of scope (later)
- No frontend, no cloud infra (`infra/`), no Dockerfile, no real IdP, no analytics.

## What "done" means
- Smoke (build/import) passes; security report clean; tests pass at >= 80% coverage with the
  resilience/perf modes recorded; docs + PR description written.
```

---

## 3. Drive the pipeline (open Claude Code IN the linkly repo)

Start a Claude Code session **inside `linkly`** and kick it off:

> **Invoke the `pipeline-orchestration` skill** and act as the orchestrator. Build the feature in
> `PROJECT.md`. Run **planning** (write `.pipeline/plan.md` *and* `.pipeline/acceptance.md`,
> including the STRIDE threat model and the perf budget as an acceptance criterion) → **plan-audit**,
> apply the one conditional revision if `revision_recommended` is true, then **stop** and show me
> `plan.md` + `plan-audit.md`. Do not start implementation until I `touch .pipeline/plan-approved`.

Then proceed through the stages, honoring every checkpoint. Manual orchestrator chores the skill
requires (do these yourself if the session doesn't):

```bash
# after you approve the plan:
touch .pipeline/plan-approved
# after implementation's smoke passes, BEFORE the security/testing loop — arm the breaker:
bash ~/.claude/hooks/loop-guard.sh reset
```

| Stage | What to watch |
|---|---|
| planning → plan-audit | Did planning put the **perf budget in `acceptance.md` as a criterion**? A migration plan? STRIDE with *named* mechanisms? Did plan-audit flag anything **material** (→ one revision)? |
| implementation (single-shot) | Stop hook fires `smoke-check.sh` → **greenfield build/import check** `python -c "import src.main"` (NOT an HTTP probe). If it fails on missing deps, `pip install -r requirements.txt` in the venv and note that it didn't self-install. Any sanity-debugging loop? |
| security | Did **semgrep + osv** run? (no `infra/` → no Checkov; no Dockerfile → no Trivy — expected, note it.) `critical_count`? Did the **migration down-path scan** flag anything? |
| testing | **The key evidence.** Did 5c/5d/5e/5f fire? Are the `resilience`/`perf` blocks populated? Is `criteria_covered` complete (incl. the perf criterion)? |
| GREEN gate | Deterministic `jq`. How many `loop-guard` cycles? Did it cap out? |
| documentation | README + `pr-description.md` + `review-manifest.json` |
| deployment | **OPTIONAL** — needs a GitHub remote + `gh auth`. Skip for a pure quality eval (it only adds the commit/PR mechanics). If you run it, it makes the first commit. |

**If a gate won't go green, do NOT fix it by hand** — note exactly where and why; let `loop-guard`
cap it. The friction *is* the data.

---

## 4. What to evaluate as you watch (the questions M2 exists to answer)

1. **Are the generated tests rigorous or shallow?** Open them. Does the idempotency test fire
   *concurrent* requests and assert one row, or just call the endpoint twice in sequence? Does the
   property test *generate* inputs or hard-code three examples? Does the perf test *measure* p95, or
   stub it? *(The #1 hypothesis: shallow tests pass a green gate.)*
2. **Did every trigger mode actually fire** (5c/5d/5e/5f), or silently no-op when it shouldn't?
3. **Is `criteria_covered` honest** — does the perf budget really ride it, and would an unmet budget
   have blocked?
4. **How much did it loop / cost** — cycles, wall-clock, any cap-out, any manual rescue.
5. **Did the code meet the spec** — real auth guard on POST, a migration with a *working* down-path,
   idempotency enforced at the DB (unique constraint) — or plausible-but-wrong?

---

## 5. Collect the evidence bundle (run in the linkly repo when the run ends)

Captures the **working tree** (most generated code is uncommitted — that's expected). Paste this
whole block into Git Bash inside `linkly`; it writes `m2-evidence.md`.

```bash
OUT=m2-evidence.md
prune='-type d ( -name .git -o -name .venv -o -name venv -o -name __pycache__ -o -name node_modules ) -prune'
{
  echo "# M2 evidence bundle — $(date -u +%FT%TZ)"
  echo
  echo "## git status (generated code is UNCOMMITTED by design)"; echo '```'
  git status --porcelain 2>/dev/null; echo '```'
  echo
  echo "## working-tree file list"; echo '```'
  find . $prune -o -type f -print | sort; echo '```'
  echo
  echo "# ===== .pipeline interlock artifacts ====="
  for f in plan.md plan-audit.md acceptance.md security-report.md security-status.json \
           test-results.json review-manifest.json pr-description.md state.json loop-state.json \
           smoke-status.json; do
    echo; echo "## .pipeline/$f"; echo '```'
    if [ -f ".pipeline/$f" ]; then cat ".pipeline/$f"; else echo "(absent — note why)"; fi
    echo '```'
  done
  echo; echo "## .pipeline/run-log.jsonl"; echo '```'; cat .pipeline/run-log.jsonl 2>/dev/null; echo '```'
  echo
  echo "# ===== GENERATED CODE + TESTS (working tree, full text — the key evidence) ====="
  find . $prune -o -type f \( -name '*.py' -o -name '*.js' -o -name '*.ts' -o -name '*.sql' \
        -o -name 'requirements*.txt' -o -name 'pyproject.toml' -o -name 'locustfile*' \
        -o -name '*.k6.js' \) -print | sort | while read -r fpath; do
    echo; echo "## $fpath"; echo '```'; cat "$fpath"; echo '```'
  done
} > "$OUT"
echo "Wrote $OUT — $(wc -l < "$OUT") lines."
```

Optional run-log digest:
```bash
bash ~/.claude/pipeline-templates/run-log-digest.sh 2>/dev/null || true
```

---

## 6. What to paste back into the `claude-agentic-workflow` session

Give me **two things**:

**(A) The evidence bundle** — the contents of `m2-evidence.md` (paste or attach). If it's very large,
the must-haves in priority order: `test-results.json`, the **generated test files**, `plan.md` +
`acceptance.md`, `security-status.json`, the **implementation source**, and `run-log.jsonl`.

**(B) This filled-in run report:**

```
## M2 run report — Linkly

Stack chosen by planning: [framework + ORM + migration tool + test libs + load runner]
Reached a GREEN gate?            [yes / no — if no, where it stuck + exact gate message]
Remediation cycles used:         [n]  | wall-clock: [approx]  | loop-guard cap hit? [y/n]
Manual interventions:            [none / list each — what you did by hand and why]
                                 (incl. did you have to pip install deps for smoke/tests?)

Trigger modes — fired correctly?
  5c migration round-trip:    [fired / no-op / wrong — note]
  5d property/fuzz:           [fired / no-op / wrong — note]
  5e concurrency/idempotency: [fired / no-op / wrong — note]
  5f perf budget:             [fired / no-op / wrong — note]
  security migration scan:    [ran / didn't — note]

Test rigor (your eyeball, before I see them):
  Idempotency test really concurrent + asserts one row?   [y/n — detail]
  Property test really generates inputs?                   [y/n]
  Perf test really measures p95 vs budget (or stub)?       [y/n]
  Any test that would pass even if the code were broken?   [list]

Implementation correctness (spot check):
  Auth guard actually enforced on POST /links?            [y/n]
  Migration has a working down-path (not just upgrade)?   [y/n]
  Idempotency enforced at the DB (unique constraint)?     [y/n]

Your gut: where it impressed you, where it disappointed.
  [free text — trust your read]
```

With (A) + (B) I can grade the real output against every claim in `../pipeline-june-analysis.md`,
populate the empty **§8 "observed failures,"** and design **M1 (the quality-grading gate)** against
the *actual* failure modes instead of my guesses.

---

## Notes / variants (optional, later runs)
- **Container variant (cheap, high value):** add a `Dockerfile` to a second run to exercise PR E's
  new **Trivy** scan (Docker already required). The single best add-on since it tests W3 directly.
- **Infra variant:** add an `infra/` Terraform dir to trigger Checkov + the IaC scale-primitive
  review (needs Terraform installed).
- **Firebase auth variant:** swap the API-key auth for the default Firebase path to exercise
  `auth-patterns` fully (needs a Firebase project — not self-contained).
