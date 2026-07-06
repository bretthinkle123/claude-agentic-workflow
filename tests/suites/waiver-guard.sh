#!/usr/bin/env bash
# waiver-guard.sh — Option B: security waivers are human-owned.
#  (1) guard-approval-markers.sh blocks a subagent Bash WRITE to .pipeline/waivers.json
#      (reads pass through, so the security agent can still honor waivers).
#  (2) deployment-gate.sh refuses to honor any waiver CLAIMED in security-status.json
#      (osv_waiver / asvs.waivers) that has no matching human record in .pipeline/waivers.json,
#      so the agent cannot self-waive to go green.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../helpers/assert.sh"

GUARD="$HOOKS/guard-approval-markers.sh"
GATE="$HOOKS/deployment-gate.sh"
echo "-- waiver-guard (Option B) --"

# (1) guard blocks agent writes to waivers.json; passes reads. Feed a PreToolUse payload.
guard_rc() { printf '{"tool_input":{"command":%s}}' "$(jq -Rn --arg c "$1" '$c')" | bash "$GUARD" >/dev/null 2>&1; echo $?; }
assert_eq 2 "$(guard_rc 'echo x > .pipeline/waivers.json')" "guard blocks redirection into waivers.json"
assert_eq 2 "$(guard_rc 'tee .pipeline/waivers.json < x')"  "guard blocks tee into waivers.json"
assert_eq 2 "$(guard_rc 'mv t .pipeline/waivers.json')"     "guard blocks mv onto waivers.json"
assert_eq 0 "$(guard_rc 'jq . .pipeline/waivers.json')"     "guard passes reading waivers.json (jq)"
assert_eq 0 "$(guard_rc 'cat .pipeline/waivers.json')"      "guard passes reading waivers.json (cat)"

# (2) gate cross-check. gate_case <want> <desc> <security-mutation> [waivers.json contents]
gate_case() {
  local want="$1" desc="$2" smut="$3" wj="${4:-}"
  local w; w="$(mk_fixture)"
  [ -n "$smut" ] && jq_edit "$w/.pipeline/security-status.json" "$smut"
  [ -n "$wj" ] && printf '%s' "$wj" > "$w/.pipeline/waivers.json"
  ( cd "$w" && bash "$GATE" ) >/dev/null 2>&1
  assert_eq "$want" "$?" "$desc"
}

# OSV: a High CVE lifted by a waiver the agent claimed but no human recorded → block.
gate_case 2 "osv High + claimed waiver, no waivers.json → block" \
  '.osv_max_cvss=7.5 | .osv_waiver={id:"GHSA-x",reason:"r",approved_by:"a"}' ''
gate_case 2 "osv High + claimed waiver not in waivers.json → block" \
  '.osv_max_cvss=7.5 | .osv_waiver={id:"GHSA-x",reason:"r",approved_by:"a"}' '{"osv":[{"id":"OTHER"}],"asvs":[]}'
gate_case 0 "osv High + claimed waiver matched in waivers.json → pass" \
  '.osv_max_cvss=7.5 | .osv_waiver={id:"GHSA-x",reason:"r",approved_by:"a"}' '{"osv":[{"id":"GHSA-x"}],"asvs":[]}'

# ASVS: a claimed waiver with no human record → block; recorded → pass.
gate_case 2 "asvs waiver claimed, no waivers.json → block"           '.asvs.waivers=["6.3.3"]' ''
gate_case 0 "asvs waiver claimed + matched in waivers.json → pass"   '.asvs.waivers=["6.3.3"]' '{"osv":[],"asvs":[{"id":"6.3.3"}]}'

# Backward compat: no claimed waivers + no waivers.json → pass (the common case).
gate_case 0 "no claimed waivers, no waivers.json → pass" '' ''

finish waiver-guard
