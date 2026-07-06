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
# Loop journal (audit T3): append-only cap-out/reset/completion history, written by
# loop-guard.sh. Lives beside the run log; used below to surface cap-outs the Stop-hook
# run log structurally cannot capture (audit T1/T4).
EVENTS="$(dirname "$LOG")/loop-events.jsonl"

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

echo "-- Loop events / suspected cap-outs (audit T1/T3/T4) --"
# The run log is written by a Stop hook, which CANNOT fire when an agent hits its
# maxTurns cap — so capped stages leave no line and the log under-counts the real run.
# Two deterministic signals of that:
#   1. loop-events.jsonl (append-only, from loop-guard.sh) records every cap-out/reset,
#      even when the run log missed the stage entirely.
#   2. a run-log line whose status or model could not be derived ("unknown") usually
#      means the stage stopped mid-work before its artifact was finalized — a cap-out tell.
if [ -f "$EVENTS" ]; then
  cap_events=$(jq -rs 'map(select(.status=="capped")) | length' "$EVENTS" 2>/dev/null || echo 0)
  echo "  loop-events.jsonl present: $(grep -c . "$EVENTS" 2>/dev/null || echo 0) event(s), ${cap_events} cap-out(s) recorded"
  jq -r 'select(.event!=null)
    | "    \(.archived_at // "?")  event=\(.event)  status=\(.status // "?")  cycles=\(.cycles // "?")"' "$EVENTS" 2>/dev/null || true
else
  echo "  (no loop-events.jsonl — either no loop ran, or loop-guard predates the T3 journal fix)"
fi
CAPPED=$(jq -rs 'map(select(.status=="capped")) | length' "$LOG" 2>/dev/null || echo 0)
if [ "${CAPPED:-0}" -gt 0 ]; then
  echo "  ${CAPPED} explicit cap-out breadcrumb(s) in the run log (audit T1):"
  jq -r 'select(.status=="capped")
    | "    \(.ts // "?")  stage=\(.stage // "?")  attempt=\(.attempt // "?")"' "$LOG" 2>/dev/null || true
fi
UNKNOWN=$(jq -rs 'map(select(.status=="unknown" or .model=="unknown")) | length' "$LOG" 2>/dev/null || echo 0)
if [ "${UNKNOWN:-0}" -gt 0 ]; then
  echo "  ⚠ ${UNKNOWN} run-log line(s) with status/model=unknown — suspected cap-out or missing artifact:"
  jq -r 'select(.status=="unknown" or .model=="unknown")
    | "    \(.ts // "?")  stage=\(.stage // "?")  status=\(.status // "?")  model=\(.model // "?")"' "$LOG" 2>/dev/null || true
fi
echo

echo "-- combined-coverage trend (testing stages: lines/branches/functions) --"
HAS_TESTING=$(jq -rs 'map(select(.stage=="testing")) | length' "$LOG")
if [ "${HAS_TESTING:-0}" -eq 0 ]; then
  echo "  (no testing stages logged yet)"
else
  jq -r '
    select(.stage=="testing")
    | "  \(.ts)  \(.feature)  lines=\(.coverage.lines // "?")  branches=\(.coverage.branches // "?")  functions=\(.coverage.functions // "?")  strategy=\(.test_strategy // "pyramid")  by_type=\(.tests_by_type // {} | tostring)"
    + (if .coverage_by_tier then "\n      per-tier: unit=\(.coverage_by_tier.unit // "n/a" | tostring)  integration=\(.coverage_by_tier.integration // "n/a" | tostring)" else "" end)' "$LOG"
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
