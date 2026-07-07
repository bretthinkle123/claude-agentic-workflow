#!/usr/bin/env bash
# telemetry.sh — U-16: log-run.sh telemetry-correctness bundle. Replays the exact
# distortions the three M3-series runs produced.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../helpers/assert.sh"

LOG="$HOOKS/log-run.sh"
echo "-- telemetry (U-16 log-run) --"

# A throwaway pipeline project (git repo, .pipeline/state.json) with a given feature slug.
mk_log_proj() {  # $1 = state.json .feature value ("" to omit)
  local w; w="$(mktemp -d)"; _WORKDIRS+=("$w")
  (
    cd "$w" && git init -q && git config user.email e@x && git config user.name x \
      && git checkout -q -b some-branch \
      && printf '.pipeline/\n' > .gitignore \
      && git add .gitignore && git commit -qm base \
      && mkdir -p .pipeline
    if [ -n "${1:-}" ]; then jq -nc --arg f "$1" '{feature:$f}' > .pipeline/state.json
    else printf '{}' > .pipeline/state.json; fi
  ) >/dev/null 2>&1
  echo "$w"
}
last() { jq -rc "$2" "$1/.pipeline/run-log.jsonl" 2>/dev/null | tail -1; }

# U-16a: feature slug from state.json, contiguous across a branch flip; branch recorded.
w="$(mk_log_proj usage-metering)"
( cd "$w" && bash "$LOG" planning >/dev/null 2>&1 )
( cd "$w" && git checkout -q -b feature/usage-metering-ingest && bash "$LOG" deployment >/dev/null 2>&1 )
assert_eq "usage-metering" "$(last "$w" '.feature')" "U-16a: feature slug stays stable across the branch flip"
assert_eq "feature/usage-metering-ingest" "$(last "$w" '.branch')" "U-16a: branch recorded separately on the deployment line"
# Attempt counter stays contiguous (both lines same feature → planning attempt 1, deployment attempt 1 of its stage).
assert_eq 1 "$(last "$w" '.attempt')" "U-16a: attempt numbering not reset by the branch flip"

# U-16d: a CAPPED line carries no stale extras. Seed a prior run's test-results, then log capped.
w="$(mk_log_proj feat)"
jq -nc '{status:"pass",total:142,passed:142,failed:0,coverage:{combined:{lines:89.82}}}' > "$w/.pipeline/test-results.json"
( cd "$w" && bash "$LOG" testing "" capped >/dev/null 2>&1 )
assert_eq "capped" "$(last "$w" '.notes')" "U-16d: capped testing line notes='capped', not the prior run's '142/142 passed'"
assert_eq "null" "$(last "$w" '.coverage // "null" | if type=="object" then "obj" else "null" end')" "U-16d: capped line carries no stale coverage block"
assert_eq "null" "$(last "$w" '(.tests // "null") | if type=="object" then "obj" else "null" end')" "U-16d: capped line carries no stale tests block"

# U-16g: skipped count surfaces; total = passed+failed+skipped is expressible.
w="$(mk_log_proj feat)"
jq -nc '{status:"pass",total:161,passed:160,failed:0,skipped:{count:1,tests:["test_k6_load"]},coverage:{combined:{lines:92}}}' > "$w/.pipeline/test-results.json"
( cd "$w" && bash "$LOG" testing >/dev/null 2>&1 )
assert_eq 1 "$(last "$w" '.tests.skipped')" "U-16g: skipped count logged (feature-3's vanished test)"
assert_eq "160 passed / 1 skipped / 161 total" "$(last "$w" '.notes')" "U-16g: notes name the skip instead of '160/161 passed'"

# U-16c: deployment files_changed from the commit when the tree is clean.
w="$(mk_log_proj feat)"
( cd "$w"
  printf 'a\n' > f1.py; printf 'b\n' > f2.py; git add -A && git commit -qm shipit
  bash "$LOG" deployment >/dev/null 2>&1 )
assert_eq 2 "$(last "$w" '.files_changed')" "U-16c: deployment line counts the committed files, not the clean-tree 0"

finish telemetry
