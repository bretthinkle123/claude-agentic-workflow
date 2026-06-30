#!/bin/bash
# Circuit-breaker for the orchestrator-driven post-approval loop (PR C).
#
# The orchestrator calls this ONCE at the top of every full
# `security ⇄ debugging ⇄ testing` cycle to get a deterministic go/no-go BEFORE
# spending another round. It bounds the WHOLE feature by cycle count and wall-clock.
#
# CRITICAL — independence from record-clean.sh: the loop budget lives in its own
# file, `.pipeline/loop-state.json`, and is reset ONLY by an explicit `reset` at
# feature start. record-clean.sh resets the per-cycle `debug_retry_count` in
# state.json on every clean pass; if the breaker shared those counters, a
# transiently-clean cycle would refill the budget and grant fresh retries forever.
# Keeping the budget in a separate file is what makes the cap bound the whole feature.
#
# Cap-out is a TERMINAL human-stop: exit 2 means STOP the loop and escalate to a
# human. The orchestrator must not auto-clear it — a human checkpoint is a hard stop.
#
# Usage:
#   loop-guard.sh reset    # once at feature start (after plan-approved), before the loop
#   loop-guard.sh          # "tick": increment the cycle, check caps; exit 0 = go, 2 = stop
#   loop-guard.sh status   # print the current budget (read-only); exit 0
#
# Config (env override, with defaults). An optional `.pipeline/loop.env` is sourced
# if present (same pattern as smoke.env):
#   LOOP_MAX_CYCLES  (default 5)     max full remediation cycles per feature
#   LOOP_MAX_WALL_S  (default 3600)  max wall-clock seconds across the loop
set -euo pipefail

# Pipeline-project guard: no-op outside a bootstrapped pipeline project (no counters
# to keep). Mirrors the ambient Stop hooks so it never fires in an unrelated repo.
[ -f .pipeline/state.json ] || exit 0

LOOP_STATE=".pipeline/loop-state.json"
# shellcheck disable=SC1091
[ -f .pipeline/loop.env ] && . .pipeline/loop.env
MAX_CYCLES="${LOOP_MAX_CYCLES:-5}"
MAX_WALL_S="${LOOP_MAX_WALL_S:-3600}"
NOW=$(date -u +%s)
NOW_ISO=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# Fail CLOSED if jq is missing: without it the breaker cannot evaluate the budget,
# and continuing to loop blind is the unsafe outcome — stop and escalate.
if ! command -v jq >/dev/null 2>&1; then
  echo "[loop-guard] jq not found on PATH — cannot evaluate the loop budget. STOP the loop and escalate to a human." >&2
  exit 2
fi

init_state() {
  jq -nc --argjson now "$NOW" --arg iso "$NOW_ISO" \
    --argjson maxc "$MAX_CYCLES" --argjson maxw "$MAX_WALL_S" \
    '{cycles:0, max_cycles:$maxc, started_epoch:$now, started_at:$iso,
      max_wall_clock_s:$maxw, status:"running"}' > "$LOOP_STATE"
}

mark_capped() {
  local tmp; tmp=$(mktemp)
  jq '.status="capped"' "$LOOP_STATE" > "$tmp" && mv "$tmp" "$LOOP_STATE"
}

case "${1:-tick}" in
  reset)
    init_state
    echo "[loop-guard] reset — budget: ${MAX_CYCLES} cycles / ${MAX_WALL_S}s wall-clock"
    exit 0
    ;;

  status)
    if [ ! -f "$LOOP_STATE" ]; then
      echo "[loop-guard] no loop in progress (run 'loop-guard.sh reset' at feature start)"
      exit 0
    fi
    CYCLES=$(jq -r '.cycles' "$LOOP_STATE")
    STARTED=$(jq -r '.started_epoch' "$LOOP_STATE")
    STATUS=$(jq -r '.status' "$LOOP_STATE")
    echo "[loop-guard] cycle ${CYCLES}/${MAX_CYCLES}, elapsed $((NOW - STARTED))s/${MAX_WALL_S}s, status=${STATUS}"
    exit 0
    ;;

  tick|"")
    [ -f "$LOOP_STATE" ] || init_state
    tmp=$(mktemp)
    jq '.cycles += 1' "$LOOP_STATE" > "$tmp" && mv "$tmp" "$LOOP_STATE"
    CYCLES=$(jq -r '.cycles' "$LOOP_STATE")
    STARTED=$(jq -r '.started_epoch' "$LOOP_STATE")
    ELAPSED=$(( NOW - STARTED ))

    if [ "$CYCLES" -gt "$MAX_CYCLES" ]; then
      mark_capped
      echo "[loop-guard] CAP HIT: ${CYCLES} cycles exceeds max ${MAX_CYCLES}. STOP the loop and escalate to a human — do not auto-clear; run documentation/deployment only after a human resolves it." >&2
      exit 2
    fi
    if [ "$ELAPSED" -gt "$MAX_WALL_S" ]; then
      mark_capped
      echo "[loop-guard] CAP HIT: elapsed ${ELAPSED}s exceeds max ${MAX_WALL_S}s. STOP the loop and escalate to a human." >&2
      exit 2
    fi

    echo "[loop-guard] cycle ${CYCLES}/${MAX_CYCLES} ok (elapsed ${ELAPSED}s/${MAX_WALL_S}s) — continue"
    exit 0
    ;;

  *)
    echo "Usage: loop-guard.sh [reset|tick|status]" >&2
    exit 2
    ;;
esac
