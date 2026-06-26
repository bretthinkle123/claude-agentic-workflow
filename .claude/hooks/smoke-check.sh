#!/bin/bash
# Confirms the app boots and responds (default: Python backend). Always runs,
# zero LLM cost. Fill START_CMD / HEALTH_URL from CLAUDE.md's Start: line, or
# export the SMOKE_* env vars.

START_CMD="${SMOKE_START_CMD:-python -m uvicorn src.main:app --host 0.0.0.0 --port 8000}"
HEALTH_URL="${SMOKE_HEALTH_URL:-http://localhost:8000/health}"
STARTUP_WAIT="${SMOKE_STARTUP_WAIT:-5}"

# Greenfield bootstrap: before the project's first commit there is no stable
# runtime target yet — implementation scaffolds /health during this first pass,
# so failing on a /health route that doesn't exist would be dishonest. Detect the
# bootstrap deterministically by the absence of any commit (no HEAD); a build/import
# check is the right signal until then. After the first commit exists (the deployment
# agent makes it), the runtime check below applies on every later run. Override the
# build command with SMOKE_BUILD_CMD if `python -c "import src.main"` isn't right.
if ! git rev-parse --verify -q HEAD >/dev/null 2>&1; then
  echo "[smoke-check] No commit yet — running build/import check (greenfield bootstrap)."
  ${SMOKE_BUILD_CMD:-python -c "import src.main"} || exit 2
  exit 0
fi

echo "[smoke-check] Starting application..."
$START_CMD &
APP_PID=$!
trap 'kill "$APP_PID" 2>/dev/null' EXIT
sleep "$STARTUP_WAIT"

if curl -sf "$HEALTH_URL" > /dev/null 2>&1; then
  echo "[smoke-check] PASS — $HEALTH_URL responded 200"
  exit 0
else
  echo "[smoke-check] FAIL — $HEALTH_URL did not respond" >&2
  exit 2
fi
