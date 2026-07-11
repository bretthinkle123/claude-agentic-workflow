#!/bin/bash
# dast-review.sh — DAST Layer 1 budget compare (deterministic; the testable half).
#
# The runtime-heavy scan (boot the app, run OWASP ZAP's passive baseline against it) is done by
# dast-capture.sh and written to .pipeline/dast-capture.json (a raw ZAP JSON report). THIS hook is
# pure jq: it tallies that report's alerts by severity and compares them against the project's
# budget (.pipeline/dast-budget.json — a per-severity cap on how many findings may ship), then
# writes an **advisory** .pipeline/dast-review.json listing anything over budget.
#
# ADVISORY, never a gate: a passive DAST baseline is a signal, not a deploy-blocker (it can
# false-positive on framework defaults, and it runs post-GREEN outside the security loop). The
# deploy-side teeth stay the pre-merge scanners + human diff review; documentation surfaces this in
# the PR. No deploy-gate / loop-exit reads it → zero loop-exit-invariant churn. Absent capture ⇒
# no-op (Docker not provisioned, no dast.env, or a non-HTTP project) — exactly like the design-review
# / egress / asvs-sast signal hooks. The gating layers (authenticated + active fuzzing) live in CI
# against staging (plan/dast-plan.md Layers 2-3), not here.
set -uo pipefail
[ -f .pipeline/state.json ] || exit 0             # ambient no-op outside a bootstrapped project
command -v jq >/dev/null 2>&1 || exit 0
CAP=.pipeline/dast-capture.json
[ -f "$CAP" ] || exit 0                            # no scan ⇒ nothing to review ⇒ no-op
jq -e . "$CAP" >/dev/null 2>&1 || exit 0           # malformed report ⇒ no-op (never emit an invalid review file)
OUT=.pipeline/dast-review.json
BUDGET=.pipeline/dast-budget.json

# Per-severity caps with safe defaults if the project shipped none. ZAP riskcode →
# 3 high, 2 medium, 1 low, 0 informational. A High is worth surfacing loudly (cap 0);
# lower severities carry framework noise, so their caps are generous by default.
budget_json='{"high":0,"medium":5,"low":20,"informational":100}'
[ -f "$BUDGET" ] && budget_json="$(jq -c '.' "$BUDGET" 2>/dev/null || echo "$budget_json")"

# ZAP baseline JSON shape: {"site":[{"@name":URL,"alerts":[{"name","riskcode":"0|1|2|3","count":"N"}]}]}
# riskcode + count are STRINGS in ZAP's report — coerce with tonumber. Sum count per severity across
# every site; list the distinct alert names that pushed a severity over its cap.
# U-14: fold in the target-reachability probe dast-capture writes. A false there means the
# spider seeded on a non-page (bare root when the UI is at /dashboard), so a within-budget
# verdict scanned nothing real — surfaced as a WARN below, still advisory (never a gate).
# Read the sidecar into a variable (default {} when absent — backward compatible).
probe_json='{}'
if [ -f .pipeline/dast-target-probe.json ] && jq -e . .pipeline/dast-target-probe.json >/dev/null 2>&1; then
  probe_json="$(jq -c '.' .pipeline/dast-target-probe.json)"
fi
jq -n --slurpfile cap "$CAP" --argjson b "$budget_json" --argjson probe "$probe_json" --arg t "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
  ({"3":"high","2":"medium","1":"low","0":"informational"}) as $sevmap
  | [ $cap[0].site // [] | .[] | .alerts // [] | .[]
      | {sev: ($sevmap[(.riskcode|tostring)] // "informational"),
         name: (.name // .alert // "unnamed"),
         count: ((.count // "0") | tonumber? // 0)} ] as $alerts
  | ($cap[0].site // [] | (.[0]."@name" // null)) as $target
  | (["high","medium","low","informational"] | map({(.): 0}) | add) as $zero
  | ($alerts | reduce .[] as $a ($zero; .[$a.sev] += $a.count)) as $by_sev
  | [ (["high","medium","low","informational"][]) as $s
      | ($by_sev[$s]) as $n | ($b[$s] // 0) as $capn
      | select($n > $capn)
      | {severity: $s, count: $n, budget: $capn,
         alerts: ($alerts | map(select(.sev == $s) | .name) | unique)} ] as $over
  | ({"target_reached": true} + ($probe // {})) as $p
  | {status: "advisory",
     ran_at: $t,
     target: $target,
     target_reached: ($p.target_reached),
     target_status: ($p.status // null),
     alerts_by_severity: $by_sev,
     over_budget: $over,
     within_budget: (($over | length) == 0)}
' > "$OUT"

OVER=$(jq '.over_budget | length' "$OUT" 2>/dev/null || echo 0)
REACHED=$(jq -r '.target_reached' "$OUT" 2>/dev/null || echo true)
if [ "$REACHED" = "false" ]; then
  echo "[dast-review] ADVISORY: DAST target was NOT reached (HTTP $(jq -r '.target_status // "?"' "$OUT")) — the passive scan did not traverse the real page; treat 'within budget' as uninformative. Set DAST_TARGET_URL to the served route. Surface in the PR (advisory). See $OUT." >&2
fi
if [ "${OVER:-0}" -gt 0 ]; then
  HI=$(jq -r '[.over_budget[] | select(.severity=="high")] | length' "$OUT" 2>/dev/null || echo 0)
  echo "[dast-review] ADVISORY: $OVER severity band(s) over budget (${HI} at HIGH) — surface in the PR (advisory, non-blocking). See $OUT." >&2
elif [ "$REACHED" != "false" ]; then
  echo "[dast-review] within budget (target: $(jq -r '.target // "n/a"' "$OUT"))."
fi
exit 0
