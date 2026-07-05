#!/bin/bash
# design-review-check.sh — FE Layer 4 budget compare (deterministic; the testable half).
#
# The runtime-heavy capture (render the built screens with Playwright, diff each against its
# baseline, run axe for a11y) is done by ui-capture.sh and written to .pipeline/ui-capture.json.
# THIS hook is pure jq: it compares that capture against the project's budget
# (.pipeline/design-budget.json — visual per-screen tolerance + a11y violation caps) and writes an
# **advisory** .pipeline/design-review.json listing anything over budget.
#
# ADVISORY, never a gate: visual pixel-diff is too brittle to block on (and design content must not
# gate — the human design-approved checkpoint is the teeth). documentation surfaces this in the PR;
# no deploy-gate / loop-exit reads it. Absent capture ⇒ no-op (no Playwright provisioned, or a
# non-UI project) — exactly like the egress/asvs-sast signal hooks.
set -uo pipefail
[ -f .pipeline/state.json ] || exit 0            # ambient no-op outside a bootstrapped project
command -v jq >/dev/null 2>&1 || exit 0
CAP=.pipeline/ui-capture.json
[ -f "$CAP" ] || exit 0                            # no capture ⇒ nothing to review ⇒ no-op
OUT=.pipeline/design-review.json
BUDGET=.pipeline/design-budget.json

# Budget with safe defaults if the project shipped none.
budget_json='{"visual":{"default_tolerance_pct":2.0,"per_screen":{}},"a11y":{"critical":0,"serious":0,"moderate":5,"minor":50}}'
[ -f "$BUDGET" ] && budget_json="$(jq -c '.' "$BUDGET" 2>/dev/null || echo "$budget_json")"

jq -n --slurpfile cap "$CAP" --argjson b "$budget_json" --arg t "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
  ($cap[0].screens // []) as $screens
  | ($b.visual.default_tolerance_pct // 2.0) as $deftol
  # visual: any screen whose diff_pct exceeds its per-screen tolerance (or the default)
  | [ $screens[] | . as $s
      | ($b.visual.per_screen[$s.name] // $deftol) as $tol
      | select(($s.diff_pct // 0) > $tol)
      | {name: $s.name, diff_pct: ($s.diff_pct // 0), tolerance: $tol} ] as $visual_over
  # a11y: for each screen, any severity whose count exceeds the budget for that severity
  | [ $screens[] | . as $s
      | (["critical","serious","moderate","minor"][]) as $sev
      | ($s.a11y[$sev] // 0) as $n | ($b.a11y[$sev] // 0) as $cap
      | select($n > $cap)
      | {name: $s.name, severity: $sev, count: $n, budget: $cap} ] as $a11y_over
  | {status: "advisory",
     ran_at: $t,
     screens_reviewed: ($screens | length),
     visual_over_budget: $visual_over,
     a11y_over_budget: $a11y_over,
     within_budget: (($visual_over | length) == 0 and ($a11y_over | length) == 0)}
' > "$OUT"

OVERV=$(jq '.visual_over_budget | length' "$OUT" 2>/dev/null || echo 0)
OVERA=$(jq '.a11y_over_budget | length'  "$OUT" 2>/dev/null || echo 0)
if [ "${OVERV:-0}" -gt 0 ] || [ "${OVERA:-0}" -gt 0 ]; then
  echo "[design-review] ADVISORY: $OVERV screen(s) over visual tolerance, $OVERA a11y budget breach(es) — surface in the PR (advisory, non-blocking). See $OUT." >&2
else
  echo "[design-review] within budget ($(jq -r '.screens_reviewed' "$OUT") screen(s) reviewed)."
fi
exit 0
