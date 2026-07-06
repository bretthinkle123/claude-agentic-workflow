#!/usr/bin/env bash
# loop-guard.sh — the circuit-breaker: reset / tick / cycle-cap / wall-cap / done /
# capped-guard / outside-project no-op.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../helpers/assert.sh"

LG="$HOOKS/loop-guard.sh"
echo "-- loop-guard --"

# A bare pipeline workdir (just .pipeline/state.json, so the guard is armed).
lg_work() { local w; w="$(mktemp -d)"; mkdir -p "$w/.pipeline"; echo '{}' > "$w/.pipeline/state.json"; _WORKDIRS+=("$w"); echo "$w"; }

# reset → running, cycles 0
w="$(lg_work)"; ( cd "$w" && bash "$LG" reset ) >/dev/null 2>&1
assert_json "$w/.pipeline/loop-state.json" '.status' running "reset → status=running"
assert_json "$w/.pipeline/loop-state.json" '.cycles' 0        "reset → cycles=0"

# tick under cap → exit 0, cycles increments
( cd "$w" && bash "$LG" tick ) >/dev/null 2>&1
assert_eq 0 "$?" "tick under cap → exit 0"
assert_json "$w/.pipeline/loop-state.json" '.cycles' 1 "tick → cycles=1"

# cycle cap → exit 2 + capped
w="$(lg_work)"
printf '{"cycles":5,"max_cycles":5,"started_epoch":%s,"max_wall_clock_s":3600,"status":"running"}\n' "$(date -u +%s)" > "$w/.pipeline/loop-state.json"
( cd "$w" && bash "$LG" tick ) >/dev/null 2>&1
assert_eq 2 "$?" "cycles>max → exit 2 (breaker bounded)"
assert_json "$w/.pipeline/loop-state.json" '.status' capped "cycle cap → status=capped"

# wall-clock cap → exit 2 + capped (old started_epoch)
w="$(lg_work)"
printf '{"cycles":1,"max_cycles":5,"started_epoch":1,"max_wall_clock_s":3600,"status":"running"}\n' > "$w/.pipeline/loop-state.json"
( cd "$w" && bash "$LG" tick ) >/dev/null 2>&1
assert_eq 2 "$?" "elapsed>max_wall → exit 2"
assert_json "$w/.pipeline/loop-state.json" '.status' capped "wall cap → status=capped"

# compute-time cap → exit 2 + capped (audit B3): compute_s already near budget, this
# cycle's capped contribution pushes it over.
w="$(lg_work)"; NOW=$(date -u +%s)
printf '{"cycles":1,"max_cycles":5,"started_epoch":%s,"last_tick_epoch":%s,"compute_s":1700,"max_compute_s":1800,"max_cycle_s":600,"max_wall_clock_s":7200,"status":"running"}\n' \
  "$((NOW-600))" "$((NOW-600))" > "$w/.pipeline/loop-state.json"
( cd "$w" && bash "$LG" tick ) >/dev/null 2>&1
assert_eq 2 "$?" "compute_s>max_compute → exit 2 (B3 compute cap)"
assert_json "$w/.pipeline/loop-state.json" '.status' capped "compute cap → status=capped"

# B3 core property: a long HUMAN-WAIT gap does NOT trip the compute budget — the cycle's
# contribution is capped at max_cycle_s, so ~28h of wait counts as at most 600s compute.
w="$(lg_work)"; NOW=$(date -u +%s)
printf '{"cycles":1,"max_cycles":5,"started_epoch":%s,"last_tick_epoch":%s,"compute_s":0,"max_compute_s":1800,"max_cycle_s":600,"max_wall_clock_s":999999,"status":"running"}\n' \
  "$((NOW-100000))" "$((NOW-100000))" > "$w/.pipeline/loop-state.json"
( cd "$w" && bash "$LG" tick ) >/dev/null 2>&1
assert_eq 0 "$?" "100000s human-wait gap → NOT capped (compute contribution capped at 600s)"
assert_json "$w/.pipeline/loop-state.json" '.compute_s' 600 "human-wait gap contributes only max_cycle_s to compute_s"

# done on a running loop → completed + completed_at (G6)
w="$(lg_work)"
printf '{"cycles":2,"max_cycles":5,"status":"running"}\n' > "$w/.pipeline/loop-state.json"
( cd "$w" && bash "$LG" done ) >/dev/null 2>&1
assert_eq 0 "$?" "done → exit 0"
assert_json "$w/.pipeline/loop-state.json" '.status' completed "done → status=completed"
assert_json "$w/.pipeline/loop-state.json" 'has("completed_at")' true "done → completed_at stamped"

# done must NOT overwrite a terminal capped (audit hardening)
w="$(lg_work)"
printf '{"cycles":6,"max_cycles":5,"status":"capped"}\n' > "$w/.pipeline/loop-state.json"
( cd "$w" && bash "$LG" done ) >/dev/null 2>&1
assert_json "$w/.pipeline/loop-state.json" '.status' capped "done on capped → stays capped"

# reset must PRESERVE a prior cap-out in the append-only journal (audit T3). Overwriting
# loop-state.json in place is fine (it's the current-round view), but the cap-out event
# must survive in loop-events.jsonl — the 71-min cap-out was lost precisely this way.
w="$(lg_work)"
printf '{"cycles":6,"max_cycles":5,"started_epoch":1,"status":"capped"}\n' > "$w/.pipeline/loop-state.json"
( cd "$w" && bash "$LG" reset ) >/dev/null 2>&1
assert_json "$w/.pipeline/loop-state.json" '.status' running "reset after cap → new round is running"
assert_eq 1 "$(jq -rs 'map(select(.status=="capped" and .event=="round-reset")) | length' "$w/.pipeline/loop-events.jsonl")" \
  "reset after cap → capped event preserved in loop-events.jsonl (T3)"

# a full lifecycle journals capped/completed too (append-only history)
w="$(lg_work)"
printf '{"cycles":2,"max_cycles":5,"status":"running"}\n' > "$w/.pipeline/loop-state.json"
( cd "$w" && bash "$LG" done ) >/dev/null 2>&1
assert_eq 1 "$(jq -rs 'map(select(.event=="completed")) | length' "$w/.pipeline/loop-events.jsonl")" \
  "done → completed event journaled"

# outside a pipeline project (no state.json) → no-op exit 0
w="$(mktemp -d)"; _WORKDIRS+=("$w")
( cd "$w" && bash "$LG" tick ) >/dev/null 2>&1; assert_eq 0 "$?" "tick outside project → no-op exit 0"
( cd "$w" && bash "$LG" done ) >/dev/null 2>&1; assert_eq 0 "$?" "done outside project → no-op exit 0"

finish loop-guard
