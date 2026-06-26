# claude-agentic-workflow

First personal agentic workflow built entirely in Claude Code. A reusable multi-agent
SDLC pipeline (planning → implementation → security → testing → documentation →
deployment, with a debugging loop), tuned for token efficiency on the Pro plan.

## How it's installed: global runtime, per-project config

The pipeline is **installed once at the user level** (`~/.claude/`) and then
**bootstrapped per project** with a single command. You never copy the pipeline
into a project again.

| Lives globally in `~/.claude/` (install once) | Written per project (bootstrap) |
| --- | --- |
| `agents/` — 7 pipeline subagents | `.claude/settings.json` — pipeline permissions (project-scoped) |
| `hooks/` — deterministic gate scripts | `.pipeline/state.json` — retry/state seed |
| `skills/` — 12 global skills | `.claude/skills/` — 2 per-project skill templates |
| `pipeline-templates/` — bootstrap toolkit | `CLAUDE.md`, `PROJECT.md`, `.gitignore` |

This repo is the **source of truth**. Edit `global-agents/`, `global-hooks/`,
`global-skills/`, `global-project-skills/`, or `templates/`, then re-publish.

## One-time install (this machine, or a new machine)

```bash
git clone <this-repo> && cd claude-agentic-workflow
./scripts/install-global.sh        # publishes agents, hooks, skills, templates -> ~/.claude/
# (use `./scripts/install-global.sh dry-run` to preview)
```

Then restart Claude Code so it picks up the new agents/hooks/skills.

## Use the pipeline in any other repo

```bash
cd /path/to/some-other-repo
bash ~/.claude/pipeline-templates/bootstrap-project.sh \
     --start "uvicorn app.main:app" \
     --health "http://localhost:8000/health" \
     --test "pytest --cov=app" \
     --build 'python -c "import app.main"'
```

The flags are optional (they pre-wire the smoke check and CLAUDE.md). Then:

1. Write `PROJECT.md` describing the first feature.
2. Start a Claude Code session in that repo and tell it to run the pipeline from
   planning (it loads the `pipeline-orchestration` skill).

Bootstrap is idempotent and never commits — the deployment agent makes the first commit.

## Why global hooks are safe

Hooks are wired through **agent frontmatter** (`Stop` / `PreToolUse`), so they fire
**only when a pipeline agent is explicitly invoked** — there is no always-on session
hook running in unrelated repos. On top of that:

- Every **ambient** hook (smoke-check, log-run, record-clean, infra-validate) opens
  with `[ -f .pipeline/state.json ] || exit 0` — an instant no-op in any repo that
  hasn't been bootstrapped as a pipeline project.
- The **deployment gate** has no such guard on purpose: outside a bootstrapped
  project its interlock files are absent, so it **fails closed** (blocks the commit).
- The broad command allow-list (git/jq/docker/pytest/…) stays **project-scoped** in
  each repo's `.claude/settings.json`; nothing broad is elevated to global settings.

## Editing the pipeline

Change files under `global-agents/`, `global-hooks/`, `global-skills/`,
`global-project-skills/`, or `templates/`, then re-run `./scripts/install-global.sh`
and restart Claude Code. See `global-skills/README.md` for skill-specific notes.
