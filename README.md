# claude-agentic-workflow

A reusable multi-agent SDLC pipeline built entirely in Claude Code. Ten specialized
subagents (an optional design-spec stage → planning → plan-audit → implementation →
security → testing → documentation → deployment, with a debugging loop, plus a standalone
read-only triage agent) handle one stage each. Tuned for token efficiency on the Pro plan.

## How it works: global runtime, per-project config

The pipeline is **installed once at the user level** (`~/.claude/`) then **bootstrapped
into each project** in seconds with one command. You never copy agents, hooks, or skills
into a project.

| This repo (source of truth) | Published to `~/.claude/` once | Written per project by bootstrap |
| --- | --- | --- |
| `global-agents/` — 10 pipeline subagents (incl. conditional design-spec + standalone triage) | `~/.claude/agents/` | `.claude/settings.json` |
| `global-hooks/` — gate/telemetry/scanner scripts | `~/.claude/hooks/` | `.pipeline/state.json` |
| `global-skills/` — global skills | `~/.claude/skills/` | `.pipeline/smoke.env` |
| `global-project-skills/` — project skill templates | `~/.claude/pipeline-templates/project-skills/` | `.claude/skills/` |
| `templates/` — CLAUDE.md, settings, state, mcp.json, ui/dast opt-ins + budgets, renovate.json, `ci/` workflow chain (incl. dast-staging) | `~/.claude/pipeline-templates/` | `CLAUDE.md`, `PROJECT.md`, `.gitignore`, `.github/workflows/`, `scripts/ci/` |

Edit files in their repo source directory, then re-run `install-global.sh` to publish.

## One-time install (this machine, or a new machine)

```bash
git clone <this-repo> && cd claude-agentic-workflow
./scripts/install-global.sh            # publish agents, hooks, skills, templates -> ~/.claude/
# ./scripts/install-global.sh dry-run  # preview what would change
# ./scripts/install-global.sh --force  # overwrite any colliding files
```

Restart Claude Code after installing so it picks up the new agents, hooks, and skills.

## Bootstrap the pipeline into any repo

Run this from the root of the target project (not this repo):

```bash
bash ~/.claude/pipeline-templates/bootstrap-project.sh \
     --start  "uvicorn app.main:app" \
     --health "http://localhost:8000/health" \
     --test   "pytest --cov=app" \
     --build  'python -c "import app.main"'
```

All flags are optional — they pre-wire the smoke check and fill the matching lines in
`CLAUDE.md`. The script creates the following (skipping any that already exist):

| Created file | Purpose |
| --- | --- |
| `.claude/settings.json` | Pipeline command allow-list, project-scoped |
| `.claude/skills/` — all project-skill templates | `test-conventions` + `semgrep-ruleset-guide` carry `<placeholders>` planning/security fill; the rest (the iOS/`design-system-conventions` set + the `app-store`/`google-play`-submission skills) load on-demand |
| `.pipeline/state.json` | Retry counters and stage-state seed |
| `.pipeline/smoke.env` | Smoke-check env vars (only written when `--start`/`--health`/`--build` are passed) |
| `CLAUDE.md` | Per-project conventions and run commands — fill remaining `<placeholders>` |
| `PROJECT.md` | Feature-scope stub — **write this before starting the pipeline** |
| `.gitignore` | Appends entries for `.pipeline/`, `.env`, `*.tfstate`, etc. |

Bootstrap is idempotent — re-running never clobbers files you have already edited.
It never runs `git` — the deployment agent makes the pipeline's first and only commit.

**After bootstrapping:**

1. Fill in `PROJECT.md` — describe the first feature, the stack, and what "done" looks like.
2. Fill any remaining `<placeholders>` in `CLAUDE.md`.
3. Open a Claude Code session in that repo and tell it to run the pipeline from planning.
   It loads the `pipeline-orchestration` skill automatically and drives each stage.

## Why global hooks are safe

Hooks fire only when a pipeline agent is explicitly invoked (wired via each agent's `Stop`
and `PreToolUse` frontmatter). Beyond that:

- Every ambient hook (`smoke-check.sh`, `log-run.sh`, `record-clean.sh`,
  `infra-validate.sh`) opens with `[ -f .pipeline/state.json ] || exit 0` — an instant
  no-op in any repo that hasn't been bootstrapped as a pipeline project.
- The **deployment gate** has no such guard on purpose: if the interlock files are absent
  it **fails closed** (blocks the commit).
- The broad command allow-list (git, jq, docker, pytest, …) stays **project-scoped** in
  `.claude/settings.json` — nothing broad is elevated to global settings, so unrelated
  Claude Code sessions on this machine are unaffected.

## Propagating a pipeline update to active projects

When you push changes to this repo and want target projects (e.g. `photography-editor-guide`) to use them:

**Step 1 — Publish to `~/.claude/`** (from this repo):
```bash
./scripts/install-global.sh
```
This covers all agent, hook, skill, and template changes. Target projects reference `~/.claude/` directly, so they get the update immediately — no per-project step needed for these files.

**Step 2 — Restart Claude Code / IDE**
New agents and hooks don't hot-reload. Restart so Claude picks up the updated global files.

**Step 3 — Re-run bootstrap in each target project** (only needed if `templates/project-settings.json` or `scripts/bootstrap-project.sh` changed):
```bash
# From inside the target project repo:
bash ~/.claude/pipeline-templates/bootstrap-project.sh
```
Bootstrap is idempotent — it only writes files that don't already exist. This means an existing `.claude/settings.json` won't be overwritten. If the settings template changed, diff it manually:
```bash
diff .claude/settings.json ~/.claude/pipeline-templates/project-settings.json
```
Merge in any missing `allowedTools` entries by hand.

> **Quick check:** If your PR only touched `global-agents/`, `global-hooks/`, or `global-skills/`, Step 1 + 2 is all you need. Step 3 is only for template or script changes.

## Editing the pipeline

Change files under `global-agents/`, `global-hooks/`, `global-skills/`,
`global-project-skills/`, or `templates/`, then re-run `./scripts/install-global.sh`
and restart Claude Code.

- `global-skills/README.md` — how to add or update a skill

## Documentation map

- **`docs/system_architecture.md`** — the current-state reference: every file, its role, the data flow.
- **`docs/pipeline-changelog.md`** — what shipped, by design unit (PR A–K, Track 2 L–P, side-tracks), and why.
- **`docs/pr-history.md`** — the same history PR-by-PR, with a by-concept summary.
- **`docs/roadmap.md`** — forward-looking only: open items, deferred workstreams, standing cadences.
- **`docs/pipeline-threat-model.md`** — STRIDE over the engine itself.
- **Reference companions** — `docs/pipeline-alternatives.md` (non-default stacks), `docs/pipeline-deployment-targets.md` (post-merge CI/CD), `docs/pipeline-mcp-config.md` (MCP wiring).
- **`plan/`** — the tracked plan archive (historical PR plans, run plans, audits — incl. the ~2,900-line `plan/agentic-pipeline-plan.md` design log); `plans/` is gitignored scratch for new drafts (convention: `plan/README.md`).
- **`tests/`** — the deterministic eval harness (`bash tests/run-eval.sh`), also the CI merge gate.
