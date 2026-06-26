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

## What "done" means
- Smoke check passes; the feature returns correct output for a sample input.
- Input validation in place; security report clean.
- Tests pass at >= <N>% coverage; docs updated; PR description written.
EOF
  note "[new]  PROJECT.md (stub — describe the first feature here)"
fi

# --- .gitignore (append missing entries) ------------------------------------
GI="$TARGET/.gitignore"
touch "$GI"
added=0
for line in ".pipeline/" ".env" ".envrc" "__pycache__/" "*.pyc" ".venv/" "venv/" "*.tfstate" "*.tfvars"; do
  if ! grep -qxF "$line" "$GI" 2>/dev/null; then
    echo "$line" >> "$GI"
    added=$((added + 1))
  fi
done
note "[gitignore] $added entr$([ "$added" -eq 1 ] && echo y || echo ies) added"

echo ""
echo "Done. Next:"
echo "  1. Write PROJECT.md (the first feature) and fill any <placeholders> in CLAUDE.md."
echo "  2. Start a Claude Code session in this repo and tell it to run the pipeline"
echo "     from planning (it loads the pipeline-orchestration skill)."
echo "  Note: nothing here was committed — the deployment agent makes the first commit."
