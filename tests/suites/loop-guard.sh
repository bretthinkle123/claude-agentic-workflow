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

# outside a pipeline project (no state.json) → no-op exit 0
w="$(mktemp -d)"; _WORKDIRS+=("$w")
( cd "$w" && bash "$LG" tick ) >/dev/null 2>&1; assert_eq 0 "$?" "tick outside project → no-op exit 0"
( cd "$w" && bash "$LG" done ) >/dev/null 2>&1; assert_eq 0 "$?" "done outside project → no-op exit 0"

finish loop-guard
