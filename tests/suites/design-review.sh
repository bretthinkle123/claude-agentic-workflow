#!/usr/bin/env bash
# design-review.sh — FE Layer 4 budget-compare logic (the deterministic half).
# design-review-check.sh reads a ui-capture.json (produced by the Playwright capture) + a budget
# and writes an ADVISORY design-review.json listing over-budget screens. The Playwright capture
# itself is runtime-bound and not exercised here; this proves the budget math + the no-op path.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../helpers/assert.sh"

CHECK="$HOOKS/design-review-check.sh"
echo "-- design-review (FE Layer 4 budget) --"

# Run design-review-check.sh in a throwaway workdir with a given capture (+ optional budget).
#   review <capture-json|__none__> <budget-json|''> <jq-on-output>  → echoes the jq result
review() {
  local cap="$1" bud="$2" q="$3" w; w="$(mktemp -d)"; _WORKDIRS+=("$w")
  ( cd "$w"
    mkdir -p .pipeline; echo '{}' > .pipeline/state.json
    [ "$cap" != "__none__" ] && printf '%s' "$cap" > .pipeline/ui-capture.json
    [ -n "$bud" ] && printf '%s' "$bud" > .pipeline/design-budget.json
    bash "$CHECK" ) >/dev/null 2>&1
  jq -rc "$q" "$w/.pipeline/design-review.json" 2>/dev/null
}

CAP_OVER='{"screens":[{"name":"login","diff_pct":5.0,"a11y":{"critical":0,"serious":0}},{"name":"home","diff_pct":0.5,"a11y":{"critical":1}}]}'
CAP_OK='{"screens":[{"name":"login","diff_pct":0.5,"a11y":{"critical":0,"serious":0,"moderate":1}}]}'

# visual: login drifted 5% > default 2% tolerance → flagged; home 0.5% → not.
assert_eq 1 "$(review "$CAP_OVER" '' '.visual_over_budget | length')" "one screen over visual tolerance"
assert_eq "login" "$(review "$CAP_OVER" '' '.visual_over_budget[0].name')" "the drifted screen is named"
# a11y: home has 1 critical, budget critical=0 → flagged.
assert_eq 1 "$(review "$CAP_OVER" '' '.a11y_over_budget | length')" "one a11y critical breach"
assert_eq "critical" "$(review "$CAP_OVER" '' '.a11y_over_budget[0].severity')" "the a11y breach severity is critical"
# within budget → clean advisory
assert_eq "true" "$(review "$CAP_OK" '' '.within_budget')" "clean capture → within_budget=true"
assert_eq "advisory" "$(review "$CAP_OK" '' '.status')" "status is always advisory (never a gate)"
# per-screen budget override: raise login tolerance to 10% → 5% drift no longer flagged
assert_eq 0 "$(review "$CAP_OVER" '{"visual":{"default_tolerance_pct":2.0,"per_screen":{"login":10.0}},"a11y":{"critical":5}}' '.visual_over_budget | length')" "per-screen tolerance override suppresses the flag"
# no capture at all → no-op: no design-review.json written (empty output)
assert_eq "" "$(review __none__ '' '.status')" "no ui-capture.json → no-op (no output file)"

finish design-review
