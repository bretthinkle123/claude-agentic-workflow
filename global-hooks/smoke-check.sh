#!/bin/bash
# Confirms the app boots and responds (default: Python backend). Always runs,
# zero LLM cost. Fill START_CMD / HEALTH_URL from CLAUDE.md's Start: line, or
# export the SMOKE_* env vars.

# Pipeline-project guard: this hook is installed globally (~/.claude/hooks/) and
# fires when the implementation agent stops. No-op in any repo that has not been
# bootstrapped as a pipeline project (no .pipeline/state.json), so it never runs
# build/import checks or writes .pipeline/ files in unrelated repos.
[ -f .pipeline/state.json ] || exit 0

# Per-project smoke wiring: bootstrap-project.sh writes the project's start/health/
# build commands here (the hook is global, so it can't be edited per project).
# Optional — without it the Python defaults below apply.
#
# SECURITY: this file is `source`d, so it runs arbitrary shell. bootstrap-project.sh
# gitignores .pipeline/, keeping smoke.env a LOCAL, untracked file. We refuse to
# source it if git tracks it — that only happens when a cloned project deliberately
# committed one, i.e. an attempt to run code on whoever next runs the pipeline here.
# shellcheck disable=SC1091
if [ -f .pipeline/smoke.env ]; then
  if git ls-files --error-unmatch .pipeline/smoke.env >/dev/null 2>&1; then
    echo "[smoke-check] Refusing to source .pipeline/smoke.env: it is tracked by git (expected local/untracked). Ignoring it." >&2
  else
    . .pipeline/smoke.env
  fi
fi

START_CMD="${SMOKE_START_CMD:-python -m uvicorn src.main:app --host 0.0.0.0 --port 8000}"
HEALTH_URL="${SMOKE_HEALTH_URL:-http://localhost:8000/health}"
STARTUP_WAIT="${SMOKE_STARTUP_WAIT:-5}"

# Records the smoke result so downstream telemetry (log-run.sh) can attribute a
# real pass/fail to the implementation stage instead of defaulting to "pass".
# Written on every exit path; status is always a controlled "pass"/"fail" literal.
write_smoke_status() {
  mkdir -p .pipeline
  printf '{"status":"%s","ran_at":"%s"}\n' "$1" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    > .pipeline/smoke-status.json
}

# Greenfield bootstrap: before the project's first commit there is no stable
# runtime target yet — implementation scaffolds /health during this first pass,
# so failing on a /health route that doesn't exist would be dishonest. Detect the
# bootstrap deterministically by the absence of any commit (no HEAD); a build/import
# check is the right signal until then. After the first commit exists (the deployment
# agent makes it), the runtime check below applies on every later run. Override the
# build command with SMOKE_BUILD_CMD if `python -c "import src.main"` isn't right.
#
# U-04: commands run via `bash -c` — the M3 run's SMOKE_BUILD_CMD carried nested
# quotes (the form bootstrap's own docs recommended) and the old unquoted `$VAR`
# expansion word-split them into a SyntaxError, costing an implementation resume
# cycle. The greenfield default is resolved into a variable FIRST: nesting the
# ${VAR:-…} default inside the bash -c string would re-introduce the quoting bug.
if ! git rev-parse --verify -q HEAD >/dev/null 2>&1; then
  echo "[smoke-check] No commit yet — running build/import check (greenfield bootstrap)."
  BUILD_CMD="${SMOKE_BUILD_CMD:-python -c \"import src.main\"}"
  if bash -c "$BUILD_CMD"; then
    write_smoke_status pass
    exit 0
  else
    write_smoke_status fail
    exit 2
  fi
fi

echo "[smoke-check] Starting application..."
# U-04: `exec` is load-bearing — without it $APP_PID is the wrapper shell, the
# EXIT-trap kills the wrapper, and the real server orphans and holds the port for
# every subsequent smoke run.
bash -c "exec $START_CMD" &
APP_PID=$!
trap 'kill "$APP_PID" 2>/dev/null' EXIT
sleep "$STARTUP_WAIT"

if curl -sf "$HEALTH_URL" > /dev/null 2>&1; then
  echo "[smoke-check] PASS — $HEALTH_URL responded 200"
  write_smoke_status pass
  exit 0
else
  echo "[smoke-check] FAIL — $HEALTH_URL did not respond" >&2
  write_smoke_status fail
  exit 2
fi
