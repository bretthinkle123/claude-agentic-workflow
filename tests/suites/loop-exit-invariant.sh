#!/usr/bin/env bash
# loop-exit-invariant.sh — the no-drift guard between the orchestrator's GREEN
# condition and deployment-gate.sh. The loop must never exit GREEN on a state the
# gate would then reject (deadlock before deploy), so the two must be equivalent.
#
# Strategy: hold pr-description present + a clean (non-git) tree so the gate's other
# two checks pass, then vary tests/security/criteria/perf. Assert:
#     deployment-gate.sh exit==0   ⟺   (security clean) AND (canonical loop-exit predicate)
# across a matrix. Plus a substring check that the orchestration SKILL still carries
# the perf-pairing fragments (catches a gate edit not mirrored into the SKILL).
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../helpers/assert.sh"

GATE="$HOOKS/deployment-gate.sh"
SKILL="$REPO_ROOT/global-skills/pipeline-orchestration/SKILL.md"
echo "-- loop-exit ≡ gate --"

# Evaluate the harness's canonical GREEN predicate for a given workdir.
# GREEN := security-status.status=="clean" AND loop-exit-predicate(test-results)==true
pred_green() {
  local w="$1"
  local sec; sec="$(jq -r '.status' "$w/.pipeline/security-status.json" 2>/dev/null)"
  [ "$sec" = "clean" ] || { echo no; return; }
  if jq -e -f "$LOOP_EXIT_PREDICATE" "$w/.pipeline/test-results.json" >/dev/null 2>&1; then echo yes; else echo no; fi
}

# One matrix row: apply a test-results mutation ('' = none) and/or a security
# mutation, then assert gate verdict == predicate verdict.
row() {
  local desc="$1" tmut="${2:-}" smut="${3:-}"
  local w; w="$(mk_fixture)"
  [ -n "$tmut" ] && jq_edit "$w/.pipeline/test-results.json" "$tmut"
  [ -n "$smut" ] && jq_edit "$w/.pipeline/security-status.json" "$smut"

  ( cd "$w" && bash "$GATE" ) >/dev/null 2>&1
  local rc=$?
  local gate_pass="no"; [ "$rc" -eq 0 ] && gate_pass="yes"
  local pred_pass; pred_pass="$(pred_green "$w")"
  assert_eq "$pred_pass" "$gate_pass" "gate ⟺ loop-exit: $desc (pred=$pred_pass gate=$gate_pass)"
}

row "green (all pass)"                       ''                                          ''
row "tests fail"                             '.status="fail"'                            ''
row "criteria incomplete"                    '.criteria_covered.covered=(.criteria_covered.total-1)' ''
row "perf F1 (measured tput null)"           '.perf.measured.throughput_rps=null'        ''
row "perf n/a short-circuit"                 '.perf.status="n/a" | .perf.measured.throughput_rps=null' ''
row "security not clean"                     ''                                          '.status="issues-found"'

# Drift guard: the orchestration SKILL must still carry the perf-pairing clause.
if grep -qF 'perf.budget.throughput_rps==null or .perf.measured.throughput_rps!=null' "$SKILL"; then
  _ok "SKILL carries the perf-pairing throughput fragment"
else
  _no "SKILL missing the perf-pairing throughput fragment (gate/loop drift?)"
fi
if grep -qF 'perf.budget.p95_ms==null' "$SKILL"; then
  _ok "SKILL carries the perf-pairing p95 fragment"
else
  _no "SKILL missing the perf-pairing p95 fragment (gate/loop drift?)"
fi

finish loop-exit-invariant
