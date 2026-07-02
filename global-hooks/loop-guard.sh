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
#   loop-guard.sh done     # on GREEN loop-exit: stamp a terminal status="completed"
#                          # (the counterpart to the cap-out "capped"; without it the
#                          #  file is left "running" after a successful run — see F6)
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
LOOP_EVENTS=".pipeline/loop-events.jsonl"
# shellcheck disable=SC1091
[ -f .pipeline/loop.env ] && . .pipeline/loop.env
MAX_CYCLES="${LOOP_MAX_CYCLES:-5}"
# Compute-time budget (audit B3) is the PRIMARY time bound: it sums per-cycle durations
# but caps each cycle's contribution at MAX_CYCLE_S, so time spent BLOCKED ON A HUMAN
# (e.g. waiting at the diff-review checkpoint) between two ticks doesn't inflate it. The
# trial's 71-min "wall-clock" trip was mostly human-wait + cap/resume overhead, not
# runaway compute — this bounds the compute, not the latency. Wall-clock stays as a
# generous ABSOLUTE backstop for a genuinely stuck loop.
MAX_COMPUTE_S="${LOOP_MAX_COMPUTE_S:-1800}"
MAX_CYCLE_S="${LOOP_MAX_CYCLE_S:-600}"
MAX_WALL_S="${LOOP_MAX_WALL_S:-7200}"
NOW=$(date -u +%s)
NOW_ISO=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# Fail CLOSED if jq is missing: without it the breaker cannot evaluate the budget,
# and continuing to loop blind is the unsafe outcome — stop and escalate.
if ! command -v jq >/dev/null 2>&1; then
  echo "[loop-guard] jq not found on PATH — cannot evaluate the loop budget. STOP the loop and escalate to a human." >&2
  exit 2
fi

# Append-only loop history (audit T3). Every round's terminal state is journaled to
# loop-events.jsonl so a `reset` can NEVER erase a prior cap-out — the single most
# important loop event in the audited run (a 71-min cap-out) was lost precisely because
# `reset` overwrote loop-state.json in place. loop-state.json remains the current-round
# view; loop-events.jsonl is the durable record.
archive_event() {
  # $1 = event kind (round-reset|capped|completed). Snapshots the CURRENT loop-state
  # (if any) as one JSONL line with the event kind + a wall-clock stamp. Best-effort:
  # never fatal (a journaling failure must not break the breaker).
  [ -f "$LOOP_STATE" ] || return 0
  jq -c --arg ev "$1" --arg iso "$NOW_ISO" \
    '. + {event:$ev, archived_at:$iso}' "$LOOP_STATE" >> "$LOOP_EVENTS" 2>/dev/null || true
}

init_state() {
  jq -nc --argjson now "$NOW" --arg iso "$NOW_ISO" \
    --argjson maxc "$MAX_CYCLES" --argjson maxw "$MAX_WALL_S" \
    --argjson maxcomp "$MAX_COMPUTE_S" --argjson maxcyc "$MAX_CYCLE_S" \
    '{cycles:0, max_cycles:$maxc, started_epoch:$now, started_at:$iso,
      max_wall_clock_s:$maxw, compute_s:0, last_tick_epoch:$now,
      max_compute_s:$maxcomp, max_cycle_s:$maxcyc, status:"running"}' > "$LOOP_STATE"
}

mark_capped() {
  local tmp; tmp=$(mktemp)
  jq '.status="capped"' "$LOOP_STATE" > "$tmp" && mv "$tmp" "$LOOP_STATE"
  archive_event capped
}

mark_done() {
  local tmp; tmp=$(mktemp)
  jq --arg iso "$NOW_ISO" '.status="completed" | .completed_at=$iso' "$LOOP_STATE" > "$tmp" && mv "$tmp" "$LOOP_STATE"
  archive_event completed
}

case "${1:-tick}" in
  reset)
    # Journal the outgoing round BEFORE overwriting it, so a prior cap-out/completion
    # survives the reset (audit T3 — reset used to clobber loop-state.json in place).
    archive_event round-reset
    init_state
    echo "[loop-guard] reset — budget: ${MAX_CYCLES} cycles / ${MAX_COMPUTE_S}s compute (per-cycle cap ${MAX_CYCLE_S}s) / ${MAX_WALL_S}s wall-clock backstop"
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
    # Report against the caps this loop was armed with (stored at reset), so the
    # display matches what the breaker actually enforces — not a since-changed env.
    MAX_CYCLES=$(jq -r "(.max_cycles // $MAX_CYCLES)" "$LOOP_STATE")
    MAX_WALL_S=$(jq -r "(.max_wall_clock_s // $MAX_WALL_S)" "$LOOP_STATE")
    echo "[loop-guard] cycle ${CYCLES}/${MAX_CYCLES}, elapsed $((NOW - STARTED))s/${MAX_WALL_S}s, status=${STATUS}"
    exit 0
    ;;

  tick|"")
    [ -f "$LOOP_STATE" ] || init_state
    STARTED=$(jq -r '.started_epoch' "$LOOP_STATE")
    # Enforce the caps the loop was ARMED with (persisted in loop-state.json at
    # reset) rather than the ambient env, so the budget can't silently change
    # mid-feature if LOOP_MAX_* differs between reset and a later tick. Fall back to
    # the env/default only for a pre-existing state file that predates these fields.
    MAX_CYCLES=$(jq -r "(.max_cycles // $MAX_CYCLES)" "$LOOP_STATE")
    MAX_WALL_S=$(jq -r "(.max_wall_clock_s // $MAX_WALL_S)" "$LOOP_STATE")
    MAX_COMPUTE_S=$(jq -r "(.max_compute_s // $MAX_COMPUTE_S)" "$LOOP_STATE")
    MAX_CYCLE_S=$(jq -r "(.max_cycle_s // $MAX_CYCLE_S)" "$LOOP_STATE")
    LAST_TICK=$(jq -r "(.last_tick_epoch // .started_epoch)" "$LOOP_STATE")

    # Compute-time accounting (audit B3): this cycle's duration is NOW - last tick, but
    # its CONTRIBUTION to the compute budget is capped at MAX_CYCLE_S so a long human-wait
    # between ticks doesn't count as compute. Accumulate, then stamp cycles + compute_s +
    # last_tick_epoch in one write.
    GAP=$(( NOW - LAST_TICK )); [ "$GAP" -lt 0 ] && GAP=0
    CONTRIB=$GAP; [ "$CONTRIB" -gt "$MAX_CYCLE_S" ] && CONTRIB=$MAX_CYCLE_S
    tmp=$(mktemp)
    jq --argjson now "$NOW" --argjson contrib "$CONTRIB" \
      '.cycles += 1 | .compute_s = ((.compute_s // 0) + $contrib) | .last_tick_epoch = $now' \
      "$LOOP_STATE" > "$tmp" && mv "$tmp" "$LOOP_STATE"
    CYCLES=$(jq -r '.cycles' "$LOOP_STATE")
    COMPUTE_S=$(jq -r '.compute_s' "$LOOP_STATE")
    ELAPSED=$(( NOW - STARTED ))

    if [ "$CYCLES" -gt "$MAX_CYCLES" ]; then
      mark_capped
      echo "[loop-guard] CAP HIT: ${CYCLES} cycles exceeds max ${MAX_CYCLES}. STOP the loop and escalate to a human — do not auto-clear; run documentation/deployment only after a human resolves it." >&2
      exit 2
    fi
    if [ "$COMPUTE_S" -gt "$MAX_COMPUTE_S" ]; then
      mark_capped
      echo "[loop-guard] CAP HIT: compute ${COMPUTE_S}s exceeds max ${MAX_COMPUTE_S}s (human-wait excluded). STOP the loop and escalate to a human." >&2
      exit 2
    fi
    if [ "$ELAPSED" -gt "$MAX_WALL_S" ]; then
      mark_capped
      echo "[loop-guard] CAP HIT: wall-clock ${ELAPSED}s exceeds backstop ${MAX_WALL_S}s. STOP the loop and escalate to a human." >&2
      exit 2
    fi

    echo "[loop-guard] cycle ${CYCLES}/${MAX_CYCLES} ok (compute ${COMPUTE_S}s/${MAX_COMPUTE_S}s, wall ${ELAPSED}s/${MAX_WALL_S}s) — continue"
    exit 0
    ;;

  done)
    # Terminal GREEN-exit stamp. The orchestrator calls this ONCE, right after the
    # run-to-condition loop exits GREEN and before documentation, so loop-state.json
    # reflects a completed run instead of being left "running" (F6). Idempotent and
    # non-fatal: a missing state file (no loop was run) just no-ops with exit 0 — it
    # must never block the GREEN→documentation handoff. Only cap-out (exit 2) is a
    # hard human-stop; "completed" is the normal successful terminal state.
    if [ ! -f "$LOOP_STATE" ]; then
      echo "[loop-guard] no loop state to finalize (nothing to do)"
      exit 0
    fi
    # Never overwrite a terminal cap-out. A `capped` loop is a hard human-stop that
    # never reaches GREEN, so the orchestrator should not call `done` after one — but
    # guard anyway so a stray call can't erase the cap-out signal. Non-blocking (exit 0):
    # `done` must never break the handoff, and the `capped` status already governs.
    if [ "$(jq -r '.status // "running"' "$LOOP_STATE")" = "capped" ]; then
      echo "[loop-guard] loop is 'capped' (cap-out human-stop) — leaving it; not stamping completed." >&2
      exit 0
    fi
    mark_done
    echo "[loop-guard] loop finalized — status=completed"
    exit 0
    ;;

  *)
    echo "Usage: loop-guard.sh [reset|tick|status|done]" >&2
    exit 2
    ;;
esac
