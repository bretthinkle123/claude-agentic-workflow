#!/usr/bin/env bash
# dast-capture.sh — DAST Layer 1 scan launcher (RUNTIME-BOUND; the ZAP half).
#
# Boots an ephemeral instance of the BUILT app, runs OWASP ZAP's PASSIVE baseline scan against it
# (no attack traffic — it crawls + inspects responses: security headers, cookie flags, info leaks,
# TLS/config smells as SERVED), and writes the raw ZAP report to .pipeline/dast-capture.json —
# which dast-review.sh then tallies against the budget (advisory). This is the one place Layer 1
# needs Docker + a running app; it is deliberately opt-in and FAIL-SAFE:
#   * no .pipeline/dast.env (project didn't opt into DAST)      → no-op
#   * Docker not running                                         → surface + no-op (never silent-pass)
# so backend-only-without-HTTP projects and un-provisioned hosts are unaffected. Passive baseline
# only — the authenticated + active-fuzz layers (plan/dast-plan.md Layers 2-3) run in CI against a
# staging env, never here. Runs POST-GREEN (after the loop exits), like design-review's ui-capture.
#
# .pipeline/dast.env (copy from templates/dast.env) declares:
#   DAST_TARGET_URL (required, e.g. http://localhost:8000), DAST_START_CMD (optional; how to boot
#   the app for the scan — leave empty if it is already running), DAST_HEALTH_URL (optional; polled
#   before scanning), DAST_STARTUP_WAIT (optional seconds fallback).
set -uo pipefail
[ -f .pipeline/state.json ] || exit 0
ENVF=.pipeline/dast.env
[ -f "$ENVF" ] || { echo "[dast-capture] no .pipeline/dast.env — DAST not configured for this project (no-op)."; exit 0; }

# Security: dast.env is sourced (arbitrary shell), so — like smoke.env — refuse it if git TRACKS it
# (expected local/untracked; a committed one is code aimed at whoever next runs the pipeline here).
if git ls-files --error-unmatch "$ENVF" >/dev/null 2>&1; then
  echo "[dast-capture] Refusing to source $ENVF: it is tracked by git (expected local/untracked). Skipping DAST." >&2
  exit 0
fi
# shellcheck disable=SC1090
set -a; . "$ENVF"; set +a
: "${DAST_TARGET_URL:=}"; : "${DAST_START_CMD:=}"; : "${DAST_HEALTH_URL:=}"; : "${DAST_STARTUP_WAIT:=5}"
[ -n "$DAST_TARGET_URL" ] || { echo "[dast-capture] dast.env present but DAST_TARGET_URL unset (no-op)."; exit 0; }

if ! docker info >/dev/null 2>&1; then
  echo "[dast-capture] Docker is not running — cannot run the ZAP baseline. Start Docker Desktop, or skip DAST. NOT reporting DAST-clean without it." >&2
  exit 0
fi

# Boot the app if a start command was given; poll health (or wait) before scanning; always tear down.
SRV_PID=""
if [ -n "$DAST_START_CMD" ]; then
  ( eval "$DAST_START_CMD" ) >.pipeline/dast-server.log 2>&1 &
  SRV_PID=$!
  if [ -n "$DAST_HEALTH_URL" ]; then
    for _ in $(seq 1 30); do curl -sf "$DAST_HEALTH_URL" >/dev/null 2>&1 && break; sleep 1; done
  else
    sleep "$DAST_STARTUP_WAIT"
  fi
fi
cleanup() { [ -n "$SRV_PID" ] && kill "$SRV_PID" >/dev/null 2>&1 || true; }
trap cleanup EXIT

# Reachability precheck (host-side, so loopback is correct here — no rewrite). A ZAP scan of a target
# that never came up still writes a near-empty report, which dast-review.sh would read as "within
# budget" — a VACUOUS GREEN on an app that was never actually scanned. So confirm the app answers
# before scanning; if not, skip ZAP entirely (no capture ⇒ dast-review no-ops = honest "not scanned"
# rather than a false clean). This is the DAST counterpart of ui-capture's "NOT reporting clean".
PROBE="${DAST_HEALTH_URL:-$DAST_TARGET_URL}"
if ! curl -sf -m 5 "$PROBE" >/dev/null 2>&1; then
  echo "[dast-capture] target not reachable at $PROBE — the app did not come up. Skipping ZAP; NOT reporting DAST-clean." >&2
  exit 0
fi

# U-14: the health precheck above proves the APP is up, not that the SCAN TARGET is a
# real page. In run 3 DAST_TARGET_URL was the bare root (`/`) while the dashboard lived
# at `/dashboard`; /health answered 200, the precheck passed, and ZAP spidered a 404 —
# "within budget" then certified a scan of nothing. Probe DAST_TARGET_URL ITSELF (the
# spider seed) and record its status. A >=400 seed means the scan won't traverse the
# real surface; dast-review surfaces target_reached:false as a WARN (advisory — never
# blocks; Layer 1 stays advisory). Deterministic: a direct status read, not log parsing.
TARGET_STATUS="$(curl -s -o /dev/null -m 5 -w '%{http_code}' "$DAST_TARGET_URL" 2>/dev/null || echo 000)"
TARGET_REACHED=false
[ "$TARGET_STATUS" -ge 200 ] 2>/dev/null && [ "$TARGET_STATUS" -lt 400 ] 2>/dev/null && TARGET_REACHED=true
printf '{"target_reached":%s,"status":%s,"url":"%s","ran_at":"%s"}\n' \
  "$TARGET_REACHED" "${TARGET_STATUS:-0}" "$DAST_TARGET_URL" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  > .pipeline/dast-target-probe.json
if [ "$TARGET_REACHED" != "true" ]; then
  echo "[dast-capture] WARNING: DAST_TARGET_URL ($DAST_TARGET_URL) returned HTTP $TARGET_STATUS — the spider seed is not a live page. For a served-UI target set DAST_TARGET_URL to the served route (e.g. /dashboard). Scanning anyway; target_reached:false will be flagged." >&2
fi

# The app runs on the HOST; ZAP runs in a CONTAINER, where localhost is the container, not the host.
# Rewrite loopback → host.docker.internal (Docker Desktop resolves it; --add-host maps it on Linux).
SCAN_URL="$DAST_TARGET_URL"
case "$SCAN_URL" in
  *localhost*)  SCAN_URL="${SCAN_URL/localhost/host.docker.internal}" ;;
  *127.0.0.1*)  SCAN_URL="${SCAN_URL/127.0.0.1/host.docker.internal}" ;;
esac

# ZAP writes its -J report into /zap/wrk (mounted from .pipeline), so dast-capture.json lands on the
# host. `pwd -W` + MSYS guards mirror semgrep-scan.sh for Docker Desktop on Git Bash/Windows.
# NOTE: deliberately NOT joined to PIPELINE_EGRESS_NETWORK (the EG default-deny net) — DAST's target
# is the LOCAL host app via host.docker.internal, not an internet host, so that net buys no
# exfiltration protection here and would block the host-gateway route the scan needs.
IMAGE="${ZAP_IMAGE:-ghcr.io/zaproxy/zaproxy:stable}"
WRK="$(cd .pipeline && { pwd -W 2>/dev/null || pwd; })"
echo "[dast-capture] ZAP passive baseline → $SCAN_URL"
MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' docker run --rm \
  --add-host=host.docker.internal:host-gateway \
  -v "${WRK}:/zap/wrk:rw" \
  "$IMAGE" \
  zap-baseline.py -t "$SCAN_URL" -J dast-capture.json -I || true   # ZAP exits 1/2 on findings; advisory ⇒ ignore

if [ -f .pipeline/dast-capture.json ]; then
  echo "[dast-capture] report written → .pipeline/dast-capture.json"
else
  echo "[dast-capture] ZAP produced no report (target unreachable?). Skipping — NOT reporting DAST-clean." >&2
fi
exit 0
