#!/usr/bin/env bash
# record-clean.sh — resets state.json.debug_retry_count to zero iff BOTH gate reports
# are clean/passing; no-op otherwise. Never touches loop-state.json.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../helpers/assert.sh"

RC="$HOOKS/record-clean.sh"
echo "-- record-clean --"

# Fixture workdir with the retry counters pre-loaded non-zero so a reset is visible.
rc_work() {
  local w; w="$(mk_fixture)"
  jq_edit "$w/.pipeline/state.json" '.debug_retry_count = {"sanity":2,"remediation":1}'
  echo "$w"
}

# both gates clean → counters reset to zero
w="$(rc_work)"
( cd "$w" && bash "$RC" ) >/dev/null 2>&1
assert_json "$w/.pipeline/state.json" '.debug_retry_count.sanity'      0 "both clean → sanity reset to 0"
assert_json "$w/.pipeline/state.json" '.debug_retry_count.remediation' 0 "both clean → remediation reset to 0"

# tests not passing → NO reset
w="$(rc_work)"
jq_edit "$w/.pipeline/test-results.json" '.status="fail"'
( cd "$w" && bash "$RC" ) >/dev/null 2>&1
assert_json "$w/.pipeline/state.json" '.debug_retry_count.sanity' 2 "tests fail → counters NOT reset"

# security not clean → NO reset
w="$(rc_work)"
jq_edit "$w/.pipeline/security-status.json" '.status="issues-found"'
( cd "$w" && bash "$RC" ) >/dev/null 2>&1
assert_json "$w/.pipeline/state.json" '.debug_retry_count.remediation' 1 "security not clean → counters NOT reset"

# outside a pipeline project → no-op exit 0
w="$(mktemp -d)"; _WORKDIRS+=("$w")
( cd "$w" && bash "$RC" ) >/dev/null 2>&1; assert_eq 0 "$?" "outside project → no-op exit 0"

finish record-clean
