#!/usr/bin/env bash
# static.sh — guards the "edited an agent/hook" case with no fixtures:
#   1. every global-hooks/*.sh parses (bash -n)
#   2. every hooks/<name>.sh referenced in an agent's frontmatter actually exists
#   3. the gate's perf predicate and the canonical loop-exit predicate compile
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../helpers/assert.sh"

echo "-- static --"

# 1. Every hook parses.
for h in "$HOOKS"/*.sh; do
  assert_exit 0 "bash -n $(basename "$h")" bash -n "$h"
done

# 2. Every hook an agent wires (Stop / PreToolUse) resolves to a real file. Catches a
#    rename/typo like the new stamp-ran-at.sh wiring pointing at a missing script.
refs="$(grep -rhoE 'hooks/[a-z0-9-]+\.sh' "$REPO_ROOT"/global-agents/*.md | sort -u)"
for r in $refs; do
  base="${r#hooks/}"
  if [ -f "$HOOKS/$base" ]; then _ok "agent hook ref resolves: $base"; else _no "agent hook ref MISSING: $base"; fi
done

# 3. The two deterministic predicates compile against null input (syntax check).
GATE_PERF_PRED='if (.perf.status // "n/a") == "n/a" then "ok"
  elif (.perf.budget.p95_ms != null and .perf.measured.p95_ms == null) then "p95_ms"
  elif (.perf.budget.throughput_rps != null and .perf.measured.throughput_rps == null) then "throughput_rps"
  else "ok" end'
assert_exit 0 "gate perf predicate compiles" jq -n "$GATE_PERF_PRED"
# The canonical loop-exit predicate file is the source of truth for the invariant suite.
assert_exit 0 "loop-exit-predicate.jq compiles" jq -n -f "$LOOP_EXIT_PREDICATE"

# Optional: shellcheck if the environment has it (skipped cleanly otherwise).
if command -v shellcheck >/dev/null 2>&1; then
  for h in "$HOOKS"/*.sh; do
    assert_exit 0 "shellcheck $(basename "$h")" shellcheck -S error "$h"
  done
else
  _ok "shellcheck not installed — skipped (optional)"
fi

finish static
