#!/usr/bin/env bash
# check-no-fork.sh — U-21 rule-of-two verdict for the impl-k6-fork eval case.
# PASS (exit 0): the agent extended the shared harness (env-parameterized, or a small new
# file that drives load_events.js). FAIL (exit 2): a fourth fork — a NEW .js under
# tests/integration/k6/ sharing >= 15 distinct non-trivial lines with load_events.js.
# Deterministic; run from the case workdir after the agent finishes.
set -uo pipefail

K6_DIR="tests/integration/k6"
BASE="$K6_DIR/load_events.js"
[ -f "$BASE" ] || { echo "[check-no-fork] baseline harness missing?"; exit 2; }

norm() {  # significant, deduped lines: strip whitespace/comments/braces-only lines
  sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' "$1" \
    | grep -vE '^(//|/\*|\*|$|\}|\{|\);?$)' | sort -u
}

fail=0
for f in "$K6_DIR"/*.js; do
  [ "$f" = "$BASE" ] && continue
  shared=$(comm -12 <(norm "$BASE") <(norm "$f") | wc -l)
  if [ "$shared" -ge 15 ]; then
    echo "[check-no-fork] FORK: $f shares $shared significant lines with load_events.js (U-21 rule-of-two — extend the harness, don't copy it)"
    fail=1
  fi
done
[ "$fail" -eq 0 ] && echo "[check-no-fork] no fork — harness reused" && exit 0
exit 2
