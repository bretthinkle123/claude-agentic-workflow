#!/usr/bin/env bash
# ui-capture.sh — FE Layer 4 capture launcher (RUNTIME-BOUND; the browser half).
#
# Renders each declared screen of the BUILT UI with Playwright, diffs it against its baseline
# (the design, or an approved golden), runs axe for a11y, and writes .pipeline/ui-capture.json —
# which design-review-check.sh then compares against the budget (advisory). This is the one place
# the pipeline needs a browser; it is deliberately opt-in and FAIL-SAFE:
#   * no .pipeline/ui.env (project didn't declare a servable UI)  → no-op
#   * Node / Playwright not installed                            → surface + no-op (never silent-pass)
# so backend-only projects and un-provisioned hosts are unaffected. Requires, once per project:
#   npm i -D playwright pixelmatch pngjs @axe-core/playwright && npx playwright install chromium
#
# .pipeline/ui.env (copy from templates/ui.env) declares:
#   UI_START_CMD, UI_BASE_URL, UI_SCREENS="name:/route …", UI_BASELINE_DIR (PNGs named <name>.png)
set -uo pipefail
[ -f .pipeline/state.json ] || exit 0
ENVF=.pipeline/ui.env
[ -f "$ENVF" ] || { echo "[ui-capture] no .pipeline/ui.env — UI capture not configured for this project (no-op)."; exit 0; }
# shellcheck disable=SC1090
set -a; . "$ENVF"; set +a
: "${UI_BASE_URL:=}"; : "${UI_SCREENS:=}"; : "${UI_START_CMD:=}"; : "${UI_BASELINE_DIR:=design/baseline}"
[ -n "$UI_BASE_URL" ] && [ -n "$UI_SCREENS" ] || { echo "[ui-capture] ui.env present but UI_BASE_URL/UI_SCREENS unset (no-op)."; exit 0; }

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if ! command -v node >/dev/null 2>&1; then
  echo "[ui-capture] Node.js not found — cannot run the browser capture. Install Node + Playwright (see the hook header) or skip FE Layer 4. NOT reporting design-clean without it." >&2
  exit 0
fi
if ! node -e 'require.resolve("playwright")' >/dev/null 2>&1; then
  echo "[ui-capture] Playwright not installed. Run: npm i -D playwright pixelmatch pngjs @axe-core/playwright && npx playwright install chromium — then re-run. (no-op for now)" >&2
  exit 0
fi

# Start the app (if a start command was given), wait for it to answer, capture, then stop it.
SRV_PID=""
if [ -n "$UI_START_CMD" ]; then
  ( eval "$UI_START_CMD" ) >/.pipeline/ui-server.log 2>&1 &
  SRV_PID=$!
  for _ in $(seq 1 30); do curl -sf "$UI_BASE_URL" >/dev/null 2>&1 && break; sleep 1; done
fi

node "$HOOK_DIR/ui-capture.mjs"; rc=$?

[ -n "$SRV_PID" ] && kill "$SRV_PID" >/dev/null 2>&1 || true
exit 0
