#!/usr/bin/env bash
# Zero-LLM digest of .pipeline/run-log.jsonl — read-only operator tooling, never a
# gate. Summarizes per-stage model/status/retries, the coverage.combined trend, the
# realized test shape, and flags an inverted pyramid. Deterministic (jq + shell).
#
# Usage:
#   run-log-digest.sh [path/to/run-log.jsonl]     # default: .pipeline/run-log.jsonl
#
# Published to ~/.claude/pipeline-templates/ by install-global.sh, so from any
# bootstrapped project:  bash ~/.claude/pipeline-templates/run-log-digest.sh
set -euo pipefail

LOG="${1:-.pipeline/run-log.jsonl}"

if ! command -v jq >/dev/null 2>&1; then
  echo "run-log-digest: jq not found on PATH." >&2
  exit 1
fi
if [ ! -f "$LOG" ]; then
  echo "run-log-digest: no run log at $LOG" >&2
  exit 1
fi

LINES=$(grep -c . "$LOG" || true)
echo "== Pipeline run-log digest =="
echo "Source: $LOG   (${LINES} entries)"
echo

echo "-- Per-stage (chronological) --"
echo "ts                    feature              stage           model    status        retries  files"
jq -r '
  [ (.ts // "?"), (.feature // "?"), (.stage // "?"), (.model // "?"),
    (.status // "?"), ((.retries // 0)|tostring), ((.files_changed // 0)|tostring) ]
  | @tsv' "$LOG" \
  | awk -F'\t' '{printf "%-21s %-20s %-15s %-8s %-13s %-8s %s\n", $1,$2,$3,$4,$5,$6,$7}'
echo

echo "-- combined-coverage trend (testing stages: lines/branches/functions) --"
HAS_TESTING=$(jq -rs 'map(select(.stage=="testing")) | length' "$LOG")
if [ "${HAS_TESTING:-0}" -eq 0 ]; then
  echo "  (no testing stages logged yet)"
else
  jq -r '
    select(.stage=="testing")
    | "  \(.ts)  \(.feature)  lines=\(.coverage.lines // "?")  branches=\(.coverage.branches // "?")  functions=\(.coverage.functions // "?")  strategy=\(.test_strategy // "pyramid")  by_type=\(.tests_by_type // {} | tostring)"' "$LOG"
fi
echo

echo "-- Shape / inverted-pyramid check --"
if [ "${HAS_TESTING:-0}" -eq 0 ]; then
  echo "  (no testing stages logged yet)"
else
  # A pyramid expects unit tests to dominate. Flag any pyramid-strategy run whose
  # unit count is below integration+e2e. (A per-suite combined-minus-unit coverage
  # gap would be a finer signal, but the run log carries only combined coverage.)
  jq -r '
    select(.stage=="testing" and (.tests_by_type != null))
    | (.tests_by_type.unit // 0) as $u
    | (.tests_by_type.integration // 0) as $i
    | (.tests_by_type.e2e // 0) as $e
    | (.test_strategy // "pyramid") as $s
    | if ($s == "pyramid" and $u < ($i + $e))
      then "  ⚠ INVERTED PYRAMID  \(.feature): unit=\($u) < integration+e2e=\($i + $e) under \($s) strategy"
      else "  ok  \(.feature): unit=\($u) integration=\($i) e2e=\($e) (\($s))"
      end' "$LOG"
fi
