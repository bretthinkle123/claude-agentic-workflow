#!/usr/bin/env bash
# stamp-scan.sh — U-09: append one execution stamp to .pipeline/scan-log.jsonl.
#
# The scanner WRAPPERS call this after running their tool, so every real execution
# leaves a durable, hash-anchored breadcrumb. The M3 series shipped security reports
# claiming "Semgrep/OSV executed this pass" whose on-disk artifacts were actually a
# PRIOR run's (or gone to OS temp) — three runs, uncheckable. With a stamp per run, a
# report may only say "executed" for a tool with a THIS-pass stamp; everything else is
# honestly "carried forward". reconcile-scans.sh (the security Stop hook) recomputes
# per-tool counts from the stamped artifacts and gates on the match.
#
# Usage:  stamp-scan.sh <tool> <exit_code> <output_path> [args...]
#   tool         semgrep | osv | trivy | checkov | gitleaks
#   exit_code    the tool's exit status
#   output_path  the artifact the tool wrote (e.g. .pipeline/semgrep.json); "" if none
#   args...      the argv the tool was invoked with (recorded as the ruleset floor)
#
# Zero-LLM, deterministic, fail-soft (a stamping failure must never break a scan).
set -uo pipefail

[ -f .pipeline/state.json ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

TOOL="${1:-unknown}"; EXITC="${2:-0}"; OUTPATH="${3:-}"
shift 3 2>/dev/null || shift $#
ARGS="$*"

SHA=""
if [ -n "$OUTPATH" ] && [ -f "$OUTPATH" ]; then
  if command -v sha256sum >/dev/null 2>&1; then
    SHA="$(sha256sum "$OUTPATH" 2>/dev/null | cut -d' ' -f1)"
  fi
fi

mkdir -p .pipeline
jq -nc \
  --arg tool "$TOOL" \
  --arg ran_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg args "$ARGS" \
  --argjson exit_code "${EXITC:-0}" \
  --arg output_path "$OUTPATH" \
  --arg output_sha256 "$SHA" \
  '{tool:$tool, ran_at:$ran_at, args:$args, exit_code:$exit_code,
    output_path:$output_path, output_sha256:$output_sha256}' \
  >> .pipeline/scan-log.jsonl 2>/dev/null || true
exit 0
