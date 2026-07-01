#!/usr/bin/env bash
# gate.sh — deployment-gate.sh against the golden green fixture + one-field mutations.
# Runs in a mktemp workdir outside any git repo, so the gate's currency check
# self-skips (verified) and we assert the tests/criteria/perf/security/pr-desc checks.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../helpers/assert.sh"

GATE="$HOOKS/deployment-gate.sh"
echo "-- gate --"

# Run the gate in a fixture workdir after applying an optional jq mutation to
# test-results.json. Usage: gate_after <want-exit> "<desc>" [jq-mutation|'' ] [extra-cmd...]
gate_case() {
  local want="$1" desc="$2" mut="${3:-}"
  local w; w="$(mk_fixture)"
  [ -n "$mut" ] && jq_edit "$w/.pipeline/test-results.json" "$mut"
  ( cd "$w" && bash "$GATE" ) >/dev/null 2>&1
  assert_eq "$want" "$?" "$desc"
}

# Green fixture passes every check.
gate_case 0 "green fixture → pass (exit 0)" ''

# Tests not passing.
gate_case 2 "test-results.status=fail → block" '.status="fail"'

# Acceptance criteria not fully covered.
gate_case 2 "criteria covered<total → block" '.criteria_covered.covered = (.criteria_covered.total - 1)'

# Perf criterion-completeness (F1): a declared budget dim with a null measured value.
gate_case 2 "perf F1: measured.throughput_rps=null → block" '.perf.measured.throughput_rps = null'

# ...but perf mode off (n/a) short-circuits even with null measured (no false block).
gate_case 0 "perf status=n/a + null measured → pass" '.perf.status="n/a" | .perf.measured.throughput_rps=null'

# Security not clean — mutate the security artifact directly (not test-results).
sec_case() {
  local w; w="$(mk_fixture)"
  jq_edit "$w/.pipeline/security-status.json" '.status="issues-found"'
  ( cd "$w" && bash "$GATE" ) >/dev/null 2>&1
  assert_eq 2 "$?" "security-status.status=issues-found → block"
}
sec_case

# Documentation missing.
prdesc_case() {
  local w; w="$(mk_fixture)"
  rm -f "$w/.pipeline/pr-description.md"
  ( cd "$w" && bash "$GATE" ) >/dev/null 2>&1
  assert_eq 2 "$?" "missing pr-description.md → block"
}
prdesc_case

finish gate
