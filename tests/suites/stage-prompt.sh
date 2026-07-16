#!/usr/bin/env bash
# stage-prompt.sh — proves the prompt/context registry (global-hooks/stage-prompt.sh)
# emits the right agent + a prompt whose slots are filled DETERMINISTICALLY from
# .pipeline/* state (feature slug, the failing security conjunct's specifics, the failing
# test's names/criteria) — never a model paraphrase.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../helpers/assert.sh"

HOOK="$HOOKS/stage-prompt.sh"
echo "-- stage-prompt (deterministic context registry) --"
assert_exit 0 "hook parses (bash -n)" bash -n "$HOOK"

# a workdir with a .pipeline/ holding the given state.json feature slug.
mkp() { local w; w="$(mktemp -d)"; _WORKDIRS+=("$w"); mkdir -p "$w/.pipeline"; printf '{"feature":"%s"}' "${1:-myfeat}" > "$w/.pipeline/state.json"; echo "$w"; }
# run stage-prompt for <workdir> <action>, return the value of field <KEY>.
field() { PIPELINE_DIR="$1/.pipeline" bash "$HOOK" "$2" 2>/dev/null | grep -m1 -E "^$3=" | sed -E "s/^$3=//"; }

# ── agent + prompt basics ─────────────────────────────────────────────────────────
w="$(mkp myfeat)"
assert_eq "planning"      "$(field "$w" run:planning AGENT)"        "run:planning → planning agent"
assert_match "$(field "$w" run:planning PROMPT)" 'Plan myfeat'      "planning prompt fills the feature slug"
assert_eq "plan-audit"    "$(field "$w" run:plan-audit AGENT)"      "run:plan-audit → plan-audit agent"
assert_eq "planning"      "$(field "$w" run:planning-revision AGENT)" "revision → planning agent"
assert_match "$(field "$w" run:planning-revision PROMPT)" 'Revise'  "revision prompt says Revise"
assert_eq "security"      "$(field "$w" run:security AGENT)"        "run:security → security agent"
assert_match "$(field "$w" run:security PROMPT)" 'scanned_change_hash' "security prompt asks for scanned_change_hash"
assert_eq "testing"       "$(field "$w" run:testing AGENT)"         "run:testing → testing agent"
assert_eq "documentation" "$(field "$w" run:documentation AGENT)"   "run:documentation → documentation agent"
assert_eq "deployment"    "$(field "$w" run:deployment AGENT)"      "run:deployment → deployment agent"

# implementation: single-shot vs per-task (tasks.md present)
assert_eq "Implement .pipeline/plan.md." "$(field "$w" run:implementation PROMPT)" "implementation single-shot when no tasks.md"
: > "$w/.pipeline/tasks.md"
assert_match "$(field "$w" run:implementation PROMPT)" 'per-task'  "implementation prompt switches to per-task with tasks.md"

# ── debugging payloads filled from state (the showcase) ───────────────────────────
w="$(mkp)"; printf '{"status":"clean","osv_max_cvss":7.5,"input_surface":{"uncontrolled":["POST /pay"]},"data_surface":{"unprotected":["users.ssn"]},"asvs":{"l1_l2_missing":["V2.1.1"],"l3_in_scope_missing":[]}}' > "$w/.pipeline/security-status.json"
assert_eq "debugging" "$(field "$w" run:debugging:security:cve-cvss-7.5 AGENT)" "security-conjunct → debugging agent"
assert_match "$(field "$w" run:debugging:security:cve-cvss-7.5 PROMPT)" 'CVSS 7.5'  "cve payload carries the CVSS from state"
assert_match "$(field "$w" run:debugging:security:input-surface PROMPT)" 'POST /pay' "input-surface payload carries the uncontrolled route from state"
assert_match "$(field "$w" run:debugging:security:data-surface PROMPT)"  'users.ssn' "data-surface payload carries the unprotected field from state"
assert_match "$(field "$w" run:debugging:security:asvs-unreconciled PROMPT)" 'V2.1.1' "asvs payload carries the missing requirement from state"
assert_match "$(field "$w" run:debugging:smoke PROMPT)" 'Smoke check failed' "smoke debugging payload"

w="$(mkp)"; printf '{"status":"fail","failures":[{"name":"test_checkout_race"}]}' > "$w/.pipeline/test-results.json"
assert_match "$(field "$w" run:debugging:test PROMPT)" 'test_checkout_race' "debugging:test names the failing test from state"
w="$(mkp)"; printf '{"status":"pass","criteria_covered":{"by_id":[{"id":"AC1","covered":true},{"id":"AC7","covered":false}]}}' > "$w/.pipeline/test-results.json"
assert_match "$(field "$w" run:debugging:test PROMPT)" 'AC7' "debugging:test names the uncovered criterion from state"

# ── non-agent directives ──────────────────────────────────────────────────────────
w="$(mkp)"
assert_match "$(field "$w" checkpoint:plan DIRECTIVE)"   'approve-plan.sh'   "checkpoint:plan directive"
assert_match "$(field "$w" checkpoint:diff DIRECTIVE)"   'approve-diff.sh'   "checkpoint:diff directive"
assert_match "$(field "$w" mark:loop-completed DIRECTIVE)" 'loop-guard.sh done' "mark:loop-completed directive"
assert_match "$(field "$w" stop:capped DIRECTIVE)"       'CAP'               "stop:capped directive"
assert_match "$(field "$w" error:not-bootstrapped DIRECTIVE)" 'bootstrap'    "error directive"

# ── unknown token is a hard error (fail closed) ───────────────────────────────────
assert_exit 2 "unknown action → exit 2" env PIPELINE_DIR="$w/.pipeline" bash "$HOOK" run:bogus

finish stage-prompt
