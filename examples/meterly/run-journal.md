# M3 run journal — Meterly (greenfield test #3)

Friction log + evidence journal per `docs/m3-validation-run-plan.md` § Instrumentation.
Rules: timestamp every manual intervention; quote evidence inline (paths, numbers, failing
output) the moment it's observed; commit + push this file after every entry. Quantitative
report numbers come from `run-summary.json` / `run-log-digest.sh`, never hand-written (B7 rule).
This journal lives in the ENGINE repo (not the throwaway repo) so it never pollutes the
run's change-set hash and survives repo teardown.

---

## Entry 0 — 2026-07-06 — pre-flight / bootstrap (operator setup, not pipeline friction)

- Engine published to `~/.claude` via `install-global.sh` at SHA `43859c25b2254f7bf43c5bf552f6d9213b8d9c90`
  (post-#33: CQ + DAST L2–L4 + STORE SC-6/7/9). **Restart Claude Code before the run session.**
- Throwaway repo created: `bretthinkle123/meterly-pipeline-test` (private, created empty — no
  auto-README, per F2).
- Cloned to `c:\Users\brett\OneDrive\Documents\GitHub\meterly-pipeline-test`; bootstrap ran clean:
  `.claude/settings.json`, 8 project skills, `.pipeline/state.json`, `smoke.env`
  (start=`uvicorn src.main:app --port 8000`, health=`/health`, test=`pytest --cov=src --cov-branch`,
  build=`python -c "import src.main"`), CLAUDE.md, `.github/workflows/` (pipeline-ci + M/N/P/DAST
  chain), `scripts/ci/`, renovate.json, 28 gitignore entries, `.gitattributes`, per-project memory.
- PROJECT.md written verbatim from the plan (under-specified items intentionally omitted — see
  plan § run discipline).
- Nothing committed in the throwaway repo — the deployment agent makes the first commit
  (greenfield discipline).
- Branch protection: NOT yet configured (no commits exist). Apply the `ci-conventions`
  branch-protection checklist after the first PR opens.

## Phase A — (entries start when the run session starts)
