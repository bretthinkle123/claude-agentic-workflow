#!/usr/bin/env bash
# asvs.sh — ASVS 5.0.0 enforcement wiring.
#
# Two things this guards:
#  (1) DRIFT — the deep checklist the security agent reads in step 6g must exist,
#      be referenced by the exact path security.md uses, and still cover all 17
#      chapters. A renamed/truncated checklist would silently break 6g.
#  (2) ENFORCEMENT — two nets: an unmet code/config L1/L2 item is a critical
#      (→ status:"issues-found" → gate blocks), AND the deploy gate + loop-exit
#      independently block on `.asvs.reconciled==false` (the deterministic backstop,
#      so a status:"clean" that contradicts an unreconciled ASVS state can't slip).
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../helpers/assert.sh"

echo "-- asvs (ASVS 5.0.0 enforcement) --"

CHECKLIST="$REPO_ROOT/global-skills/stride-threat-model-template/asvs-5.0-checklist.md"
SECURITY="$REPO_ROOT/global-agents/security.md"
STRIDE_SKILL="$REPO_ROOT/global-skills/stride-threat-model-template/SKILL.md"

# --- (1) Drift guards --------------------------------------------------------
[ -f "$CHECKLIST" ] && ok=0 || ok=1
assert_eq 0 "$ok" "asvs-5.0-checklist.md exists (security 6g reads it)"

grep -q 'skills/stride-threat-model-template/asvs-5.0-checklist.md' "$SECURITY" && ok=0 || ok=1
assert_eq 0 "$ok" "security.md 6g references the checklist by its published path"

missing=""
for n in $(seq 1 17); do
  grep -qE "^### V$n " "$CHECKLIST" || missing="$missing V$n"
done
assert_eq "" "$missing" "checklist covers all 17 chapters (V1-V17)"

grep -q 'BLOCKING' "$CHECKLIST" && grep -qE 'L1 \+ L2' "$CHECKLIST" && ok=0 || ok=1
assert_eq 0 "$ok" "checklist states the L1/L2-universal + code/config-BLOCKING policy"

# security.md 6g is the ENFORCING version and emits the asvs reconciliation object.
grep -q 'ENFORCING' "$SECURITY" && grep -q 'l1_l2_missing' "$SECURITY" \
  && grep -q 'reconciled' "$SECURITY" && ok=0 || ok=1
assert_eq 0 "$ok" "security.md 6g is enforcing + emits asvs{l1_l2_missing,reconciled}"

grep -q '## ASVS Compliance' "$STRIDE_SKILL" && ok=0 || ok=1
assert_eq 0 "$ok" "planning skill emits a '## ASVS Compliance' block"

# --- (2) Enforcement rides the existing status gate --------------------------
# Green fixture carries a reconciled asvs block + clean status → gate passes.
w="$(mk_fixture)"
assert_json "$w/.pipeline/security-status.json" '.asvs.reconciled' 'true' "fixture asvs.reconciled=true"
assert_json "$w/.pipeline/security-status.json" '(.asvs.l1_l2_missing|length)' '0' "fixture asvs.l1_l2_missing empty"
( cd "$w" && bash "$HOOKS/deployment-gate.sh" ) >/dev/null 2>&1
assert_eq 0 "$?" "green fixture (asvs reconciled, status clean) → gate pass"

# Net 1 — an unmet L1/L2 code/config item (e.g. IDOR authz 8.2.2) is a critical → the agent
# writes status:"issues-found" → the deploy gate blocks.
w2="$(mk_fixture)"
jq_edit "$w2/.pipeline/security-status.json" \
  '.asvs.l1_l2_missing=["8.2.2"] | .asvs.reconciled=false | .critical_count=1 | .status="issues-found"'
( cd "$w2" && bash "$HOOKS/deployment-gate.sh" ) >/dev/null 2>&1
assert_eq 2 "$?" "unmet L1/L2 (8.2.2) → critical → status issues-found → gate blocks"

# Net 2 (the deterministic backstop / the fixed hole) — even if status is left "clean",
# asvs.reconciled=false must block on its own.
w3="$(mk_fixture)"
jq_edit "$w3/.pipeline/security-status.json" '.asvs.reconciled=false'   # status stays "clean"
( cd "$w3" && bash "$HOOKS/deployment-gate.sh" ) >/dev/null 2>&1
assert_eq 2 "$?" "status left clean but asvs.reconciled=false → gate blocks (backstop)"

# Backward compat — a security-status with no asvs field at all still passes.
w4="$(mk_fixture)"
jq_edit "$w4/.pipeline/security-status.json" 'del(.asvs)'
( cd "$w4" && bash "$HOOKS/deployment-gate.sh" ) >/dev/null 2>&1
assert_eq 0 "$?" "no asvs field → gate passes (backward compatible)"

finish asvs
