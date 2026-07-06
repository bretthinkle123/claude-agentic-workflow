#!/usr/bin/env bash
# dast-review.sh — DAST Layer 1 budget-compare logic (the deterministic half).
# dast-review.sh reads a raw ZAP report (dast-capture.json, produced by the runtime-bound
# dast-capture.sh) + a per-severity budget and writes an ADVISORY dast-review.json listing every
# severity band over budget. The ZAP scan itself is runtime-bound (Docker) and not exercised here;
# this proves the tally/budget math, the ZAP string-typed count/riskcode coercion, and the no-op paths.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../helpers/assert.sh"

CHECK="$HOOKS/dast-review.sh"
echo "-- dast-review (DAST Layer 1 budget) --"

# Run dast-review.sh in a throwaway workdir with a given capture (+ optional budget).
#   review <capture-json|__none__> <budget-json|''> <jq-on-output>  → echoes the jq result
review() {
  local cap="$1" bud="$2" q="$3" w; w="$(mktemp -d)"; _WORKDIRS+=("$w")
  ( cd "$w"
    mkdir -p .pipeline; echo '{}' > .pipeline/state.json
    [ "$cap" != "__none__" ] && printf '%s' "$cap" > .pipeline/dast-capture.json
    [ -n "$bud" ] && printf '%s' "$bud" > .pipeline/dast-budget.json
    bash "$CHECK" ) >/dev/null 2>&1
  jq -rc "$q" "$w/.pipeline/dast-review.json" 2>/dev/null
}

# ZAP-shaped report: riskcode + count are STRINGS (3=high,2=medium,1=low,0=info).
CAP_OVER='{"site":[{"@name":"http://host.docker.internal:8000","alerts":[{"name":"CSP Not Set","riskcode":"3","count":"2"},{"name":"MIME Sniffing","riskcode":"1","count":"5"},{"name":"Info Leak","riskcode":"0","count":"9"}]}]}'
CAP_OK='{"site":[{"@name":"http://host.docker.internal:8000","alerts":[{"name":"MIME Sniffing","riskcode":"1","count":"3"},{"name":"Info Leak","riskcode":"0","count":"4"}]}]}'
CAP_MULTISITE='{"site":[{"@name":"a","alerts":[{"name":"CSP Not Set","riskcode":"3","count":"1"}]},{"@name":"b","alerts":[{"name":"CSP Not Set","riskcode":"3","count":"2"}]}]}'

# High (2) exceeds default cap 0 → one band flagged; low (5<20) and info (9<100) do not.
assert_eq 1 "$(review "$CAP_OVER" '' '.over_budget | length')" "one severity band over budget"
assert_eq "high" "$(review "$CAP_OVER" '' '.over_budget[0].severity')" "the over-budget band is high"
assert_eq 2 "$(review "$CAP_OVER" '' '.over_budget[0].count')" "high count summed from the string field"
assert_eq "CSP Not Set" "$(review "$CAP_OVER" '' '.over_budget[0].alerts[0]')" "the offending alert is named"
assert_eq 5 "$(review "$CAP_OVER" '' '.alerts_by_severity.low')" "low count tallied (string coerced)"
# Clean capture (nothing over its cap) → within_budget, always advisory.
assert_eq "true" "$(review "$CAP_OK" '' '.within_budget')" "under-cap capture → within_budget=true"
assert_eq "advisory" "$(review "$CAP_OK" '' '.status')" "status is always advisory (never a gate)"
assert_eq 0 "$(review "$CAP_OK" '' '.over_budget | length')" "clean capture flags nothing"
# Budget override: raise the high cap to 5 → 2 highs no longer over budget.
assert_eq "true" "$(review "$CAP_OVER" '{"high":5,"medium":5,"low":20,"informational":100}' '.within_budget')" "raised high cap suppresses the flag"
# Multi-site aggregation: counts sum across sites (1+2=3 high) → still over cap 0.
assert_eq 3 "$(review "$CAP_MULTISITE" '' '.alerts_by_severity.high')" "high count sums across sites"
# No capture at all → no-op: no dast-review.json written (empty output).
assert_eq "" "$(review __none__ '' '.status')" "no dast-capture.json → no-op (no output file)"
# Malformed capture → clean no-op: never emit an invalid dast-review.json for docs to choke on.
assert_eq "" "$(review 'not json at all' '' '.status')" "malformed dast-capture.json → no-op (no invalid output file)"

finish dast-review
