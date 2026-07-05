#!/usr/bin/env bash
# run-summary.sh — emit .pipeline/run-summary.json, a deterministic machine summary of the
# whole run, written once at GREEN (the orchestrator calls it right after
# `loop-guard.sh done`, before documentation). Audit B7/T4: the retrospective must COPY
# per-stage model + cost from data, never hand-write it — in the trial the retrospective
# said implementation ran on "opus" when its frontmatter (and thus the run log) said
# sonnet. This summary is the single source the retrospective quotes, so that class of
# misattribution can't recur. Zero-LLM, deterministic (jq + shell).
#
# Reads .pipeline/run-log.jsonl (per-stage lines, incl. attempt + capped breadcrumbs) and
# .pipeline/loop-events.jsonl (append-only cap-out/reset/complete journal). Emits counts
# that are honest even when the Stop hook missed capped stages, because the orchestrator's
# T1 breadcrumb + the loop journal fill those gaps.
#
# Usage: run-summary.sh [path/to/run-log.jsonl]   # default .pipeline/run-log.jsonl
set -euo pipefail

LOG="${1:-.pipeline/run-log.jsonl}"
DIR="$(dirname "$LOG")"
EVENTS="$DIR/loop-events.jsonl"
OUT="$DIR/run-summary.json"

command -v jq >/dev/null 2>&1 || { echo "run-summary: jq not found on PATH." >&2; exit 1; }
[ -f "$LOG" ] || { echo "run-summary: no run log at $LOG" >&2; exit 1; }

# loop cap-out count from the append-only journal (survives resets); 0 if absent.
LOOP_CAPS=0
[ -f "$EVENTS" ] && LOOP_CAPS=$(jq -rs 'map(select(.status=="capped")) | length' "$EVENTS" 2>/dev/null || echo 0)

# Assurance stamp (iOS plan Layer 3). The deterministic gates (Semgrep/OSV/coverage) are
# Python/JS-shaped; on a **Swift/iOS** target they run but analyze little until the Swift language
# adapters (xcodebuild smoke, Semgrep-Swift, xccov coverage) exist. So detect a Swift target with
# ABSENT adapters and stamp the run `reduced` — while that stamp is present the run must NOT be
# called "gate-verified" (documentation/retrospective read this field). Default `standard`.
SWIFT_TARGET=false
git ls-files 2>/dev/null | grep -qiE '(\.swift$|(^|/)Package\.swift$|\.xcodeproj)' && SWIFT_TARGET=true
grep -riqE 'native ios|swiftui' "$DIR/../CLAUDE.md" "$DIR/../PROJECT.md" 2>/dev/null && SWIFT_TARGET=true
SWIFT_ADAPTERS=false
{ [ -f "$HOME/.claude/hooks/swift-gate.sh" ] || [ -f "$DIR/swift-adapters.json" ]; } && SWIFT_ADAPTERS=true
ASSURANCE="standard"
if [ "$SWIFT_TARGET" = true ] && [ "$SWIFT_ADAPTERS" = false ]; then
  ASSURANCE="reduced (swift adapters absent)"
fi

# Per-stage rollup from the run log. `slurp` the JSONL, group by stage, and for each stage
# record invocations (line count), the max attempt seen, cap-out lines (status=="capped"),
# the distinct models, and the last recorded status. Models come from the log, which
# auto-derives them from agent frontmatter — so this can never desync from the real model.
jq -rs \
  --arg gen "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg assurance "$ASSURANCE" \
  --argjson loop_caps "${LOOP_CAPS:-0}" '
  (group_by(.stage) | map({
     key: (.[0].stage // "unknown"),
     value: {
       invocations: length,
       attempts_max: (map(.attempt // 1) | max),
       caps: (map(select(.status=="capped")) | length),
       models: (map(.model // "unknown") | unique),
       last_status: (last.status // "unknown")
     }
   }) | from_entries) as $stages
  | {
      generated_at: $gen,
      assurance: $assurance,
      stages: $stages,
      totals: {
        log_lines: length,
        capped_lines: (map(select(.status=="capped")) | length),
        loop_cap_events: $loop_caps,
        suspected_underlog: (map(select(.status=="unknown" or .model=="unknown")) | length)
      },
      models_used: (map(.model // "unknown") | unique),
      first_pass_clean: (
        (map(select(.status=="capped")) | length) == 0
        and $loop_caps == 0
        and (map(.retries // 0) | add // 0) == 0
      )
    }' "$LOG" > "$OUT"

echo "[run-summary] wrote $OUT"
jq -r '"  stages=\(.stages|keys|length)  log_lines=\(.totals.log_lines)  capped=\(.totals.capped_lines)  loop_caps=\(.totals.loop_cap_events)  first_pass_clean=\(.first_pass_clean)  assurance=\(.assurance)"' "$OUT"
[ "$ASSURANCE" != "standard" ] && echo "[run-summary] ⚠ assurance=$ASSURANCE — do NOT describe this run as gate-verified until the Swift language adapters (iOS Layer 3) land." >&2
exit 0
