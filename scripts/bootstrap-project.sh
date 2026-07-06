#!/usr/bin/env bash
# Prepare the CURRENT repo to run the multi-agent pipeline. Run this from inside a
# freshly cloned/created project. The pipeline's agents, hooks, and skills already
# live globally in ~/.claude/ (published by install-global.sh), so this only writes
# the small per-project files: pipeline permissions, the .pipeline/ state seed, the
# two per-project skill templates, a CLAUDE.md, and .gitignore entries.
#
# Usage (from the target repo root):
#   bash ~/.claude/pipeline-templates/bootstrap-project.sh \
#        [--start "<cmd>"] [--health "<url>"] [--test "<cmd>"] [--build "<cmd>"]
#
# Optional flags pre-wire the smoke check (written to .pipeline/smoke.env, which the
# global smoke-check.sh sources) and fill the matching lines in CLAUDE.md:
#   --start   app start command (e.g. "uvicorn app.main:app")
#   --health  health URL the smoke check probes after the first commit
#   --test    test command (e.g. "pytest --cov=app")
#   --build   import/build check used on the greenfield first run, before any
#             commit exists (e.g. 'python -c "import app.main"'). Set it explicitly
#             for non-src layouts; the hook default ('import src.main') won't match.
#
# Idempotent and non-destructive: existing files are left untouched (so re-running
# never clobbers a CLAUDE.md you've edited or skill placeholders planning has filled).
# Never runs git init/add/commit — scaffolding only.
set -euo pipefail

TEMPLATES="${HOME}/.claude/pipeline-templates"
TARGET="$(pwd)"
START=""; HEALTH=""; TEST=""; BUILD=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --start)  START="$2";  shift 2 ;;
    --health) HEALTH="$2"; shift 2 ;;
    --test)   TEST="$2";   shift 2 ;;
    --build)  BUILD="$2";  shift 2 ;;
    --start=*)  START="${1#*=}";  shift ;;
    --health=*) HEALTH="${1#*=}"; shift ;;
    --test=*)   TEST="${1#*=}";   shift ;;
    --build=*)  BUILD="${1#*=}";  shift ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

# --- preconditions -----------------------------------------------------------
if [[ ! -d "$TEMPLATES" ]]; then
  echo "Error: $TEMPLATES not found. Run install-global.sh from the pipeline repo first." >&2
  exit 1
fi
for d in agents hooks skills; do
  if [[ ! -d "${HOME}/.claude/$d" ]]; then
    echo "Warning: ~/.claude/$d is missing — the pipeline won't resolve $d until you run install-global.sh." >&2
  fi
done

note() { echo "  $1"; }
echo "Bootstrapping pipeline into: $TARGET"

# --- .claude/settings.json (per-project permissions) -------------------------
mkdir -p "$TARGET/.claude"
if [[ -f "$TARGET/.claude/settings.json" ]]; then
  note "[skip] .claude/settings.json already exists"
else
  cp "$TEMPLATES/project-settings.json" "$TARGET/.claude/settings.json"
  note "[new]  .claude/settings.json (pipeline permissions, project-scoped)"
fi

# --- per-project skill templates --------------------------------------------
# test-conventions and semgrep-ruleset-guide carry <PLACEHOLDERS> the planning/
# security agents fill per project, so they are project-local, not global.
mkdir -p "$TARGET/.claude/skills"
for skill_dir in "$TEMPLATES/project-skills/"*/; do
  name="$(basename "$skill_dir")"
  if [[ -d "$TARGET/.claude/skills/$name" ]]; then
    note "[skip] .claude/skills/$name already exists"
  else
    cp -r "$skill_dir" "$TARGET/.claude/skills/$name"
    note "[new]  .claude/skills/$name"
  fi
done

# --- .pipeline/ state seed ---------------------------------------------------
mkdir -p "$TARGET/.pipeline"
if [[ -f "$TARGET/.pipeline/state.json" ]]; then
  note "[skip] .pipeline/state.json already exists"
else
  cp "$TEMPLATES/state.json" "$TARGET/.pipeline/state.json"
  note "[new]  .pipeline/state.json"
fi

# --- .pipeline/smoke.env (smoke-check wiring) --------------------------------
if [[ -n "$START$HEALTH$BUILD" ]]; then
  {
    echo "# Written by bootstrap-project.sh — sourced by the global smoke-check.sh hook."
    [[ -n "$START"  ]] && echo "export SMOKE_START_CMD=\"$START\""
    [[ -n "$HEALTH" ]] && echo "export SMOKE_HEALTH_URL=\"$HEALTH\""
    [[ -n "$BUILD"  ]] && echo "export SMOKE_BUILD_CMD='$BUILD'"
  } > "$TARGET/.pipeline/smoke.env"
  note "[new]  .pipeline/smoke.env (smoke-check target)"
fi

# --- CLAUDE.md ---------------------------------------------------------------
if [[ -f "$TARGET/CLAUDE.md" ]]; then
  note "[skip] CLAUDE.md already exists"
else
  cp "$TEMPLATES/CLAUDE.md" "$TARGET/CLAUDE.md"
  # Fill the smoke-relevant lines when provided (values must not contain | or &).
  if [[ -n "$START" ]]; then
    h="${HEALTH:-<http://localhost:8000/health>}"
    sed -i "s|^- Start:.*|- Start: \`$START\` (smoke check expects HTTP 200 at \`$h\`)|" "$TARGET/CLAUDE.md"
  fi
  if [[ -n "$TEST" ]]; then
    sed -i "s|^- Test:.*|- Test:  \`$TEST\`|" "$TARGET/CLAUDE.md"
  fi
  note "[new]  CLAUDE.md (fill remaining <placeholders>)"
fi

# --- CI merge gate (PR L Layer 2) ---------------------------------------------
# Writes the pipeline-ci workflow + copies the CI-re-runnable check scripts INTO the
# project (scripts/ci/ — committed, human-reviewed, pinned at bootstrap-time version, so
# CI never fetches them remotely). The workflow re-RUNS the objective gates on the merge
# commit; it never re-reads .pipeline/ artifacts. See docs/ci-merge-gate-plan.md.
if [[ -f "$TARGET/.github/workflows/pipeline-ci.yml" ]]; then
  note "[skip] .github/workflows/pipeline-ci.yml already exists"
elif [[ -f "$TEMPLATES/ci/pipeline-ci.yml" ]]; then
  mkdir -p "$TARGET/.github/workflows" "$TARGET/scripts/ci"
  cp "$TEMPLATES/ci/pipeline-ci.yml" "$TARGET/.github/workflows/pipeline-ci.yml"
  # Fill test/build from the same flags that populate smoke.env (values must not contain | or &).
  [[ -n "$TEST"  ]] && sed -i "s|<TEST_CMD>|$TEST|"  "$TARGET/.github/workflows/pipeline-ci.yml"
  [[ -n "$BUILD" ]] && sed -i "s|<BUILD_CMD>|$BUILD|" "$TARGET/.github/workflows/pipeline-ci.yml"
  for s in asvs-sast.sh guard-source-markers.sh lockfile-check.sh store-compliance.sh dast-review.sh; do
    [[ -f "${HOME}/.claude/hooks/$s" ]] && cp "${HOME}/.claude/hooks/$s" "$TARGET/scripts/ci/$s"
  done
  chmod +x "$TARGET/scripts/ci/"*.sh 2>/dev/null || true
  note "[new]  .github/workflows/pipeline-ci.yml + scripts/ci/ (fill remaining <placeholders>; apply the branch-protection checklist in the ci-conventions skill)"
else
  note "[skip] CI template not found in $TEMPLATES/ci — re-run install-global.sh"
fi

# --- PROJECT.md stub ---------------------------------------------------------
if [[ -f "$TARGET/PROJECT.md" ]]; then
  note "[skip] PROJECT.md already exists"
else
  cat > "$TARGET/PROJECT.md" <<'EOF'
# <Project name>

## What this is
<one-paragraph description of the service / app>

## First feature (this build only — keep scope here)
<the single thin slice to build now; e.g. one endpoint + its validation + tests>

## Explicitly out of scope for this build (later features)
<things deliberately deferred so the implementation agent doesn't cap out>

## Stack
<language/runtime, framework, key libs; cloud/auth or "app-only">

## Frontend design source
<!-- OPTIONAL — delete if there is no provided UI design. If you have a Claude Design
     export, a Figma export, or reference screenshots, drop them in a design/ folder and
     fill the line below. The design-spec stage then normalizes it into a human-approved
     .pipeline/design-spec.md and planning REPLICATES the design (as close to 1:1 as the
     platform allows) instead of inventing the UI. No design/ + "none" ⇒ stage skipped. -->
- Design source: <"see design/ (Claude Design export)" | "see design/ (Figma export)" | "see design/screens/ (screenshots)" | "Figma MCP (file <KEY>)" | "none">

## What "done" means
- Smoke check passes; the feature returns correct output for a sample input.
- Input validation in place; security report clean.
- Tests pass at >= <N>% coverage; docs updated; PR description written.
EOF
  note "[new]  PROJECT.md (stub — describe the first feature; set Design source if UI-driven)"
fi

# --- .gitignore (append missing entries) ------------------------------------
# Covers stack-agnostic + Python (the default backend stack) AND the common Node/JS
# build artifacts. The Node entries are added unconditionally, not gated on a
# detected stack: bootstrap runs BEFORE any package.json exists (implementation
# creates it mid-run), so stack detection here would miss it — and an un-ignored
# node_modules/ is catastrophic (thousands of files flood the change-set the pipeline
# hashes and scans, since git ls-files --others --exclude-standard honors .gitignore),
# while these entries cost nothing in a Python project. (dist/ and build/ are also
# standard Python packaging ignores.)
GI="$TARGET/.gitignore"
touch "$GI"
added=0
# The `reports/`, `scratch_*`, `load/results.json` entries (audit E4 / B-N1) keep tool
# output — Stryker mutation reports, security-scan scratch files, load-test result JSON —
# out of the change-set the pipeline hashes and scans. Leaking them into the tree
# previously polluted the review hash and compounded the E1 hash-instability debugging.
for line in ".pipeline/" ".env" ".envrc" "__pycache__/" "*.pyc" ".venv/" "venv/" \
            ".pytest_cache/" ".hypothesis/" ".ruff_cache/" ".coverage" "coverage.json" "htmlcov/" \
            "*.db" "*.sqlite" "*.sqlite3" "*.tfstate" "*.tfvars" \
            "node_modules/" "dist/" "build/" "coverage/" ".stryker-tmp/" "*.tsbuildinfo" "npm-debug.log*" \
            "reports/" "scratch_*" "load/results.json"; do
  if ! grep -qxF "$line" "$GI" 2>/dev/null; then
    echo "$line" >> "$GI"
    added=$((added + 1))
  fi
done
note "[gitignore] $added entr$([ "$added" -eq 1 ] && echo y || echo ies) added"

# --- .gitattributes (cross-machine byte stability for the change-set hash) ----
# Audit E1 completeness: the change-set hash includes `git diff HEAD`, whose bytes
# depend on line-ending normalization. Without a committed policy, a CRLF-checkout
# machine (Windows default `core.autocrlf=true`) and an LF machine produce different
# tracked-file diffs → different hashes → the human approval gate becomes unpassable
# from a differently-configured shell (exactly the E1 failure, tracked-file half).
# Pin `eol=lf` for text so every checkout sees identical bytes, and set the repo-local
# `core.autocrlf=false` as a belt-and-suspenders (guarded: no-op if not yet a git repo).
GA="$TARGET/.gitattributes"
if [[ ! -f "$GA" ]]; then
  printf '* text=auto eol=lf\n' > "$GA"
  note "[new]  .gitattributes (* text=auto eol=lf — cross-machine hash stability)"
else
  note "[skip] .gitattributes already exists"
fi
if git -C "$TARGET" rev-parse --git-dir >/dev/null 2>&1; then
  git -C "$TARGET" config core.autocrlf false
  note "[git] core.autocrlf=false (repo-local; keeps tracked-file bytes stable)"
fi

# --- Claude Code per-project memory ------------------------------------------
# Encode the absolute project path the same way Claude Code does:
#   /c/Users/brett/project  →  c--Users-brett-project  (Windows/Git Bash)
#   /home/brett/project     →  home--brett-project      (Linux/Mac)
# Rule: strip leading /, replace the first / with --, replace remaining / with -.
# On Windows the drive letter c and the colon-then-backslash (c:\) together
# produce the double-dash: c + -- + rest.
encode_path() { printf '%s' "$1" | sed 's|^/||; s|/|--|; s|/|-|g'; }

ENCODED="$(encode_path "$TARGET")"
MEMORY_DIR="${HOME}/.claude/projects/${ENCODED}/memory"

if [[ -f "$MEMORY_DIR/MEMORY.md" ]]; then
  note "[skip] ~/.claude/projects/${ENCODED}/memory/ already exists"
else
  mkdir -p "$MEMORY_DIR"

  cat > "$MEMORY_DIR/MEMORY.md" <<'EOF'
- [Pipeline first-run gotchas](pipeline_first_run.md) — Windows hook setup, plan approval gate, greenfield smoke check, API key, Docker for Semgrep, and deployment scope
EOF

  cat > "$MEMORY_DIR/pipeline_first_run.md" <<'EOF'
---
name: pipeline-first-run
description: "Critical gotchas for the first pipeline run in a new project — communicate these at session start"
metadata:
  type: project
---

## Windows hook risk

Pipeline gates run as `.sh` scripts via Claude Code hooks. On Windows they require Git
Bash on PATH. If hooks silently don't fire (no output in `.pipeline/run-log.jsonl` after
invoking an agent), Git Bash is likely not on the session PATH. Fix: restart Claude Code
from a terminal that has Git Bash on PATH, or verify `$HOME/.claude/hooks/*.sh` are
executable (`chmod +x`).

## Plan approval gate

The implementation agent refuses to start unless `.pipeline/plan-approved` exists. After
the planning agent produces `plan.md` and the human reviews it, create the marker:

```bash
touch .pipeline/plan-approved
```

Do NOT create this marker before reviewing the plan — it is the human checkpoint.

## Greenfield smoke check mode

On the very first run there is no HEAD commit yet, so `git diff HEAD` fails. The smoke
check falls back to a build-check: it runs `SMOKE_BUILD_CMD` (set in
`.pipeline/smoke.env` by bootstrap) instead of starting the app and probing an HTTP
endpoint. Ensure `--build` was passed to `bootstrap-project.sh`, or set
`SMOKE_BUILD_CMD` in `.pipeline/smoke.env` manually before invoking implementation.

## ANTHROPIC_API_KEY requirement

All pipeline agents require `ANTHROPIC_API_KEY` in the environment. If an agent fails to
start with an auth error, export the key in the terminal before launching Claude Code, or
add it to the shell profile.

## Docker for Semgrep

The security agent runs Semgrep via Docker (`~/.claude/hooks/semgrep-scan.sh`). Docker
Desktop must be running before invoking the security stage. If Docker is not running, the
agent surfaces the error rather than skipping the scan silently.

## Deployment scope

The deployment agent commits the reviewed change, pushes to GitHub, and opens a PR. It
does NOT run `terraform apply`, database migrations, app deploys, or any post-merge CI
steps. Those happen outside the pipeline after the PR is merged. See
`docs/pipeline-deployment-targets.md` for CI/CD patterns to wire up after merge.
EOF

  note "[new]  ~/.claude/projects/${ENCODED}/memory/ (first-run gotchas pre-loaded)"
fi

echo ""
echo "Done. Next:"
echo "  1. Write PROJECT.md (the first feature) and fill any <placeholders> in CLAUDE.md."
echo "  2. Building a UI from a design? Put the Claude Design / Figma export or screenshots"
echo "     in a design/ folder and set 'Design source:' in PROJECT.md — the design-spec stage"
echo "     then replicates it. (Live Figma instead of an export: see docs/pipeline-mcp-config.md.)"
echo "  3. Start a Claude Code session in this repo and tell it to run the pipeline"
echo "     from planning (it loads the pipeline-orchestration skill)."
echo "  Note: nothing here was committed — the deployment agent makes the first commit."
