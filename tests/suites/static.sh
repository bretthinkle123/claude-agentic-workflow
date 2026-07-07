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

# Committed executable bits. The repo is authored on Windows (core.fileMode=false), where
# a script committed 0644 looks fine locally but a fresh Linux checkout gets "Permission
# denied" on any DIRECT invocation — the deployment gate then blocks a green state (found
# by eval.yml's first CI run: every gate-passes assertion failed on the runner only).
NOEXEC="$(cd "$REPO_ROOT" && git ls-files -s | grep -E '\.sh$' | grep -v '^100755' | awk '{print $4}')"
assert_eq "" "$NOEXEC" "every committed .sh has the executable bit (100755) — Windows fileMode regression guard"

# U-10: the finding ledger exists and every table row carries a non-empty action (an
# escape with no decision is itself a defect). Rows are `| … | action |`; the action is
# the last cell. Scan the seed tables for any row whose final cell is blank.
LEDGER="$REPO_ROOT/docs/finding-ledger.md"
if [ -f "$LEDGER" ]; then
  _ok "finding-ledger.md exists (U-10)"
  # Data rows: start with '| R' (the seed ids) — assert the last pipe-cell is non-empty.
  BLANK_ACTIONS="$(grep -E '^\| R[0-9]' "$LEDGER" | awk -F'|' '{a=$(NF-1); gsub(/^[ \t]+|[ \t]+$/,"",a); if (a=="") print}')"
  assert_eq "" "$BLANK_ACTIONS" "every finding-ledger row has a non-empty action (U-10)"
else
  _no "docs/finding-ledger.md is missing (U-10)"
fi

# U-23: the agent-eval corpus is well-formed — every planted-defect dir has an
# expected-findings.json manifest (the deterministic contract the runner asserts against).
EVAL_DIR="$REPO_ROOT/tests/agent-evals"
if [ -d "$EVAL_DIR" ]; then
  MISSING_MANIFEST=""
  for d in "$EVAL_DIR"/*/; do
    [ -d "$d" ] || continue
    [ -f "${d}expected-findings.json" ] || MISSING_MANIFEST="$MISSING_MANIFEST ${d##*agent-evals/}"
  done
  assert_eq "" "$MISSING_MANIFEST" "every tests/agent-evals/<case>/ has an expected-findings.json (U-23)"
fi

finish static
