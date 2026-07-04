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

# Perf-scenario disclosure (WS3-3): perf ran but scenario undisclosed → block.
gate_case 2 "perf ran + scenario=null → block (WS3-3)" '.perf.scenario=null'
# ...but perf off (n/a) never requires a scenario.
gate_case 0 "perf n/a + scenario=null → pass"          '.perf.status="n/a" | .perf.scenario=null'

# Security not clean — mutate the security artifact directly (not test-results).
sec_case() {
  local w; w="$(mk_fixture)"
  jq_edit "$w/.pipeline/security-status.json" '.status="issues-found"'
  ( cd "$w" && bash "$GATE" ) >/dev/null 2>&1
  assert_eq 2 "$?" "security-status.status=issues-found → block"
}
sec_case

# CVE-severity floor (audit B6): a High/Critical OSV finding blocks even when clean,
# unless an explicit waiver is recorded.
sec_mut_case() {
  local want="$1" desc="$2" mut="$3" wj="${4:-}"
  local w; w="$(mk_fixture)"
  jq_edit "$w/.pipeline/security-status.json" "$mut"
  # Optional human waivers.json (Option B — a claimed osv/asvs waiver is only honored if recorded).
  [ -n "$wj" ] && printf '%s' "$wj" > "$w/.pipeline/waivers.json"
  ( cd "$w" && bash "$GATE" ) >/dev/null 2>&1
  assert_eq "$want" "$?" "$desc"
}
sec_mut_case 2 "clean + osv_max_cvss=7.5, no waiver → block (B6)" '.osv_max_cvss=7.5'
sec_mut_case 0 "clean + osv_max_cvss=6.9 (below floor) → pass"     '.osv_max_cvss=6.9'

# ASVS reconciliation floor: status left "clean" but asvs.reconciled=false must still block
# (the deterministic backstop — an unmet code/config L1/L2 item can't slip past as green).
sec_mut_case 2 "clean + asvs.reconciled=false → block (ASVS)" '.asvs.reconciled=false'
sec_mut_case 0 "clean + asvs.reconciled=true → pass"          '.asvs.reconciled=true'
sec_mut_case 0 "clean + no asvs field → pass (backward compat)" 'del(.asvs)'
# B6 waiver now requires a human record in waivers.json (Option B): a bare claimed waiver blocks,
# a human-recorded one lifts the floor.
sec_mut_case 2 "clean + osv 7.5 + claimed waiver, no human record → block" '.osv_max_cvss=7.5 | .osv_waiver={id:"GHSA-x",reason:"dev-only",approved_by:"human"}'
sec_mut_case 0 "clean + osv 7.5 + human-recorded waiver → pass"            '.osv_max_cvss=7.5 | .osv_waiver={id:"GHSA-x",reason:"dev-only",approved_by:"human"}' '{"osv":[{"id":"GHSA-x"}],"asvs":[]}'

# Input-surface reconciliation floor (input-controls plan): an uncontrolled input source blocks.
sec_mut_case 2 "clean + uncontrolled input source → block"         '.input_surface.uncontrolled=["POST /transfers"]'
sec_mut_case 0 "clean + input_surface reconciled ([]) → pass"      '.input_surface={declared:2,implemented:2,uncontrolled:[],reconciled:true}'

# Source-marker guard (audit E3): a reverted/do-not-commit marker in the change set
# blocks. The gate runs in a non-git fixture dir, so exercise the guard on an untracked
# source file by making the workdir a throwaway git repo with the fixture + a marked file.
marker_case() {
  local w; w="$(mktemp -d)"; _WORKDIRS+=("$w")
  ( cd "$w"
    git init -q; git config user.email a@b.c; git config user.name t
    printf '.pipeline/\n' > .gitignore; git add .gitignore; git commit -qm base
    mkdir -p .pipeline && cp "$FIXTURE"/* .pipeline/
    printf 'function pay(){ /* TEMP-REVERT: restore SAVEPOINT */ return 1; }\n' > pay.js
  ) >/dev/null 2>&1
  # Approve the current (marked) tree so the human-approval gate is not what blocks —
  # we want to prove the MARKER blocks, independently.
  local h; h="$(cd "$w" && bash "$HOOKS/compute-change-hash.sh")"
  jq -nc --arg h "$h" '{approved_change_hash:$h}' > "$w/.pipeline/diff-approved"
  ( cd "$w" && bash "$GATE" ) >/dev/null 2>&1
  assert_eq 2 "$?" "TEMP-REVERT marker in changed source → block (E3)"
}
marker_case

# Documentation missing.
prdesc_case() {
  local w; w="$(mk_fixture)"
  rm -f "$w/.pipeline/pr-description.md"
  ( cd "$w" && bash "$GATE" ) >/dev/null 2>&1
  assert_eq 2 "$?" "missing pr-description.md → block"
}
prdesc_case

# Mutation scope-pairing (WS3-1): a deploy-only honesty check. Write a test-quality.json
# into the fixture workdir and assert the gate blocks only a FALSE completeness claim.
qual_case() {
  local want="$1" desc="$2" tq="$3"
  local w; w="$(mk_fixture)"
  printf '%s\n' "$tq" > "$w/.pipeline/test-quality.json"
  ( cd "$w" && bash "$GATE" ) >/dev/null 2>&1
  assert_eq "$want" "$?" "$desc"
}
qual_case 2 "quality_ok=true + scope⊂configured, no waiver → block (WS3-1)" \
  '{"quality_ok":true,"mutation":{"configured_scope":["a.ts","b.ts"],"scope":["a.ts"]}}'
qual_case 0 "quality_ok=true + scope==configured → pass" \
  '{"quality_ok":true,"mutation":{"configured_scope":["a.ts","b.ts"],"scope":["a.ts","b.ts"]}}'
qual_case 0 "quality_ok=false + scope⊂configured → pass (honest advisory)" \
  '{"quality_ok":false,"mutation":{"configured_scope":["a.ts","b.ts"],"scope":["a.ts"]}}'
qual_case 0 "quality_ok=true + scope⊂configured + waiver → pass" \
  '{"quality_ok":true,"quality_waiver":{"id":"Q1","reason":"services suite too slow","approved_by":"human"},"mutation":{"configured_scope":["a.ts","b.ts"],"scope":["a.ts"]}}'
# Green fixture has no test-quality.json at all → the check no-ops (already asserted by
# the green-fixture pass above); confirm an empty-mutation quality file is also fine.
qual_case 0 "no configured_scope recorded → pass (backward compatible)" \
  '{"quality_ok":true,"mutation":{"scope":["a.ts"]}}'

finish gate
