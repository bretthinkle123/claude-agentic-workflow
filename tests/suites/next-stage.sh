#!/usr/bin/env bash
# next-stage.sh — proves the DETERMINISTIC transition function (global-hooks/next-stage.sh)
# maps every .pipeline/* state to the correct next action, and that its GREEN decision
# cannot drift from the deploy gate (it reuses the canonical predicates).
#
# Two parts:
#   (A) a state→action matrix (fresh throwaway .pipeline/ per row).
#   (B) drift guards: the driver's security predicate is byte-identical to
#       loop-exit-invariant.sh's SEC_PREDICATE, and it consumes loop-exit-predicate.jq.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../helpers/assert.sh"

HOOK="$HOOKS/next-stage.sh"
H="deadbeefcafe0000"                 # the "current" change-set hash for this run
export PIPELINE_CHANGE_HASH="$H"
echo "-- next-stage (deterministic transition function) --"

assert_exit 0 "hook parses (bash -n)" bash -n "$HOOK"

# run next-stage in a workdir, echo its action token.
ns() { ( cd "$1" && bash "$HOOK" ); }
# fresh workdir with an empty .pipeline/.
newp() { local w; w="$(mktemp -d)"; _WORKDIRS+=("$w"); mkdir -p "$w/.pipeline"; echo "$w"; }

# ── file adders (operate on <workdir> ) ───────────────────────────────────────────
add_state()    { printf '{"debug_retry_count":{"sanity":0,"remediation":0},"max_retries":3}' > "$1/.pipeline/state.json"; }
add_plan()     { echo "# plan"       > "$1/.pipeline/plan.md"; echo "# acceptance" > "$1/.pipeline/acceptance.md"; }
add_plan_rev() { printf '# plan\n\n## Revision notes\naddressed the material flags\n' > "$1/.pipeline/plan.md"; echo "# acceptance" > "$1/.pipeline/acceptance.md"; }
add_audit()    { printf -- '---\nrevision_recommended: %s\n---\n# audit\n' "$2" > "$1/.pipeline/plan-audit.md"; }
add_approved() { : > "$1/.pipeline/plan-approved"; }
add_smoke()    { printf '{"status":"%s"}' "$2" > "$1/.pipeline/smoke-status.json"; }
add_sec()      { jq "${2:-.}"                       "$FIXTURE/security-status.json" > "$1/.pipeline/security-status.json"; }  # green fixture, no scanned hash ⇒ fresh
add_sec_stale(){ jq '.scanned_change_hash="STALE0"' "$FIXTURE/security-status.json" > "$1/.pipeline/security-status.json"; }
add_test()     { jq --arg h "$H" "${2:-.} | .tested_change_hash=\$h" "$FIXTURE/test-results.json" > "$1/.pipeline/test-results.json"; }  # fresh green
add_test_stale(){ jq '.tested_change_hash="STALE0"' "$FIXTURE/test-results.json" > "$1/.pipeline/test-results.json"; }
add_loop()     { printf '{"status":"%s"}' "$2" > "$1/.pipeline/loop-state.json"; }
touchf()       { : > "$1/.pipeline/$2"; }

# a workdir advanced to "just entering the loop" (plan approved, smoke green).
loopbase() { local w; w="$(newp)"; add_state "$w"; add_plan "$w"; add_audit "$w" false; add_approved "$w"; add_smoke "$w" pass; echo "$w"; }
# a workdir at loop-GREEN (fresh green security + test, loop stamped completed).
postgreen(){ local w; w="$(loopbase)"; add_sec "$w"; add_test "$w"; add_loop "$w" completed; echo "$w"; }

row() { assert_eq "$2" "$(ns "$3")" "$1"; }

# ── (A) state → action matrix ─────────────────────────────────────────────────────
w="$(newp)";                                              row "no state.json"                 "error:not-bootstrapped" "$w"
w="$(newp)"; add_state "$w";                              row "only state → planning"         "run:planning"           "$w"
w="$(newp)"; add_state "$w"; add_plan "$w";              row "plan, no audit → plan-audit"   "run:plan-audit"         "$w"
w="$(newp)"; add_state "$w"; add_plan "$w"; add_audit "$w" true;  row "audit wants revision → revise" "run:planning-revision" "$w"
w="$(newp)"; add_state "$w"; add_plan_rev "$w"; add_audit "$w" true; row "revision done → plan checkpoint" "checkpoint:plan" "$w"
w="$(newp)"; add_state "$w"; add_plan "$w"; add_audit "$w" false; row "audit clean, no approval → checkpoint" "checkpoint:plan" "$w"
w="$(newp)"; add_state "$w"; add_plan "$w"; add_audit "$w" false; add_approved "$w"; row "approved, no smoke → implementation" "run:implementation" "$w"
w="$(loopbase)"; add_smoke "$w" fail;                    row "smoke fail → sanity debugging"  "run:debugging:smoke"    "$w"

# loop routing
w="$(loopbase)";                                         row "no security → security"        "run:security"           "$w"
w="$(loopbase)"; add_sec_stale "$w";                    row "security stale → re-scan"      "run:security"           "$w"
w="$(loopbase)"; add_sec "$w" '.status="issues-found"'; row "security issues → debug"       "run:debugging:security:status-issues-found" "$w"
w="$(loopbase)"; add_sec "$w" '.osv_max_cvss=7.5';      row "clean+High CVE → debug conjunct" "run:debugging:security:cve-cvss-7.5" "$w"
w="$(loopbase)"; add_sec "$w" '.input_surface.uncontrolled=["POST /x"]'; row "uncontrolled input → debug" "run:debugging:security:input-surface" "$w"
w="$(loopbase)"; add_sec "$w";                          row "security green, no test → testing" "run:testing"        "$w"
w="$(loopbase)"; add_sec "$w"; add_test_stale "$w";     row "test stale → re-test"          "run:testing"            "$w"
w="$(loopbase)"; add_sec "$w"; add_test "$w" '.status="fail"'; row "test fail → debug"       "run:debugging:test"     "$w"
w="$(loopbase)"; add_sec "$w"; add_test "$w" '.criteria_covered.covered=(.criteria_covered.total-1)'; row "criteria incomplete → debug" "run:debugging:test" "$w"

# GREEN → completion → docs → checkpoint → deploy
w="$(loopbase)"; add_sec "$w"; add_test "$w"; add_loop "$w" running; row "both green, loop running → stamp done" "mark:loop-completed" "$w"
w="$(postgreen)";                                        row "green+stamped, no pr → docs"   "run:documentation"      "$w"
w="$(postgreen)"; touchf "$w" pr-description.md;         row "pr written, no approval → checkpoint" "checkpoint:diff" "$w"
w="$(postgreen)"; touchf "$w" pr-description.md; touchf "$w" diff-approved; row "approved → deployment" "run:deployment" "$w"

# advisory conditional stages (opt-in env files)
w="$(postgreen)"; touchf "$w" ui.env;                   row "ui.env present → design-review" "run:design-review"     "$w"
w="$(postgreen)"; touchf "$w" dast.env;                 row "dast.env present → dast"        "run:dast"               "$w"

# circuit-breaker terminal beats a fully-green state
w="$(postgreen)"; touchf "$w" pr-description.md; touchf "$w" diff-approved; add_loop "$w" capped; row "capped beats green → stop" "stop:capped" "$w"

# ── (B) drift guards: GREEN decision can't diverge from the gate ───────────────────
NS="$HOOK"; INV="$REPO_ROOT/tests/suites/loop-exit-invariant.sh"
sec_ns="$(grep -m1 -E "^SEC_PRED=" "$NS" | sed -E "s/^SEC_PRED=//")"
sec_inv="$(grep -m1 -E "^SEC_PREDICATE=" "$INV" | sed -E "s/^SEC_PREDICATE=//")"
assert_eq "$sec_inv" "$sec_ns" "next-stage SEC_PRED ≡ loop-exit-invariant SEC_PREDICATE (no security drift)"
assert_exit 0 "next-stage consumes the canonical loop-exit-predicate.jq" grep -q "loop-exit-predicate.jq" "$NS"

# ── (C) vocabulary ≡ : every action next-stage emits is handled by stage-prompt, and the
#        SKILL wires both hooks as the driver. Adding an action to one side alone breaks this.
SP="$HOOKS/stage-prompt.sh"
SKILL="$REPO_ROOT/global-skills/pipeline-orchestration/SKILL.md"
# static tokens next-stage.sh must be able to emit (dynamic run:debugging:security:* checked by prefix)
for tok in run:planning run:plan-audit run:planning-revision run:implementation \
           run:debugging:smoke run:debugging:test run:security run:testing \
           run:documentation run:deployment run:design-review run:dast \
           checkpoint:plan mark:loop-completed stop:capped error:not-bootstrapped; do
  assert_exit 0 "next-stage can emit '$tok'"       grep -qF "\"$tok\"" "$NS"
  assert_exit 0 "stage-prompt handles '$tok'"      env PIPELINE_DIR="$(newp)/.pipeline" bash "$SP" "$tok"
done
assert_exit 0 "next-stage emits run:debugging:security:<conjunct>" grep -q "run:debugging:security:" "$NS"
assert_exit 0 "stage-prompt handles run:debugging:security:*"      env PIPELINE_DIR="$(newp)/.pipeline" bash "$SP" run:debugging:security:cve-cvss-8.1
assert_exit 0 "SKILL wires next-stage.sh as the driver"           grep -q "next-stage.sh" "$SKILL"
assert_exit 0 "SKILL wires stage-prompt.sh as the driver"         grep -q "stage-prompt.sh" "$SKILL"

# ── (D) PUBLISHED-LAYOUT regression (F1) ──────────────────────────────────────────
# The hook must resolve its canonical GREEN predicate when copied to a hooks-only dir
# with NO sibling tests/ — exactly how install-global publishes it to ~/.claude/hooks/.
# A tests/-relative default previously made `jq -f` fail on every test-results.json in a
# live run, mis-routing a fully-GREEN state to run:debugging:test (loop wedged). The suite
# couldn't catch it because it runs from the repo where that path resolves; this copies the
# published fileset (hook + compute-change-hash + loop-exit-predicate.jq) and asserts green.
simhooks="$(mktemp -d)"; _WORKDIRS+=("$simhooks")
cp "$HOOKS/next-stage.sh" "$HOOKS/compute-change-hash.sh" "$HOOKS/loop-exit-predicate.jq" "$simhooks/"
w="$(postgreen)"; touchf "$w" pr-description.md; touchf "$w" diff-approved
got="$( cd "$w" && PIPELINE_CHANGE_HASH="$H" bash "$simhooks/next-stage.sh" )"
assert_eq "run:deployment" "$got" "published layout (no sibling tests/): full-green state → deployment, not debugging"

finish next-stage
