#!/bin/bash
# Appends one line to .pipeline/run-log.jsonl — per-stage pipeline telemetry.
# Wired as a Stop hook on every agent. Zero-LLM, deterministic.
#
# Usage: log-run.sh <stage> <model> [status] [retries] [notes]
#   stage   : planning|implementation|debugging|security|testing|documentation|deployment
#   model   : opus|sonnet|haiku
#   status  : pass|fail|clean|issues-found|blocked|escalated  (default: auto-derive)
#   retries : integer  (default: auto-read from state.json)
#   notes   : free-text (default: empty)
#
# feature    — derived from the current git branch name
# status     — "auto" reads the relevant .pipeline artifact for the stage:
#              implementation → smoke-status.json, security → security-status.json,
#              testing → test-results.json, debugging → state.json (retry cap).
#              Stages with no outcome artifact default to "pass" (= the agent ran
#              to completion, not a verified-correct signal).
# extras     — stage-specific fields pulled from pipeline artifacts:
#              testing   → coverage, tests.{total,passed,failed}
#              security  → critical_findings, warning_findings
#
# Not captured (not exposed to shell hooks by Claude Code):
#   turns_used, duration_s  — use timestamp deltas between log entries as a proxy

set -euo pipefail

STAGE="${1:?stage required}"
MODEL="${2:?model required}"
STATUS="${3:-auto}"
RETRIES="${4:-auto}"
NOTES="${5:-}"

# Feature: current git branch (slug for the in-progress change). symbolic-ref
# resolves the branch even before the first commit, unlike `rev-parse --abbrev-ref`
# which prints "HEAD" and exits non-zero on a commitless repo. Use a replace-style
# guard (|| FEATURE="") so a failure can't append stray output to the value.
FEATURE=$(git symbolic-ref --short HEAD 2>/dev/null) || FEATURE=""
[ -n "$FEATURE" ] || FEATURE="unknown"

# Retries: sum sanity + remediation counts from state.json
if [ "$RETRIES" = "auto" ]; then
  if [ -f .pipeline/state.json ]; then
    RETRIES=$(jq -r '(.debug_retry_count.sanity // 0) + (.debug_retry_count.remediation // 0)' \
      .pipeline/state.json 2>/dev/null || echo 0)
  else
    RETRIES=0
  fi
fi

# Status: derive from the stage's canonical output artifact
if [ "$STATUS" = "auto" ]; then
  case "$STAGE" in
    security)
      STATUS=$(jq -r '.status // "unknown"' .pipeline/security-status.json 2>/dev/null || echo "unknown")
      ;;
    testing)
      STATUS=$(jq -r '.status // "unknown"' .pipeline/test-results.json 2>/dev/null || echo "unknown")
      ;;
    implementation)
      # smoke-check.sh (earlier in the same Stop array) writes this fresh on every
      # run, so it reflects the smoke result for the code just implemented.
      STATUS=$(jq -r '.status // "unknown"' .pipeline/smoke-status.json 2>/dev/null || echo "unknown")
      ;;
    debugging)
      if [ -f .pipeline/state.json ]; then
        MAX=$(jq -r '.max_retries // 3' .pipeline/state.json 2>/dev/null || echo 3)
        CURRENT=$(jq -r '(.debug_retry_count.sanity // 0) + (.debug_retry_count.remediation // 0)' \
          .pipeline/state.json 2>/dev/null || echo 0)
        [ "$CURRENT" -ge "$MAX" ] && STATUS="escalated" || STATUS="pass"
      else
        STATUS="pass"
      fi
      ;;
    *)
      STATUS="pass"
      ;;
  esac
fi

# Scope: files touched so far (tracked diff + untracked new files).
# `git diff HEAD` fails on a repo with no commits (greenfield first run); capture
# the file lists with a guard FIRST so pipefail can't abort the script, then count.
TRACKED_LIST=$(git diff HEAD --name-only 2>/dev/null || true)
UNTRACKED_LIST=$(git ls-files --others --exclude-standard 2>/dev/null || true)
TRACKED=0; UNTRACKED=0
[ -n "$TRACKED_LIST" ]   && TRACKED=$(printf '%s\n' "$TRACKED_LIST" | grep -c .)
[ -n "$UNTRACKED_LIST" ] && UNTRACKED=$(printf '%s\n' "$UNTRACKED_LIST" | grep -c .)
FILES_CHANGED=$(( TRACKED + UNTRACKED ))

# Stage-specific extras pulled from pipeline artifacts
EXTRAS='{}'
case "$STAGE" in
  testing)
    if [ -f .pipeline/test-results.json ]; then
      EXTRAS=$(jq -c '{coverage:.coverage,tests:{total:(.total // 0),passed:(.passed // 0),failed:(.failed // 0)}}' \
        .pipeline/test-results.json 2>/dev/null || echo '{}')
    fi
    ;;
  security)
    if [ -f .pipeline/security-status.json ]; then
      EXTRAS=$(jq -c '{critical_findings:(.critical_count // 0),warning_findings:(.warning_count // 0)}' \
        .pipeline/security-status.json 2>/dev/null || echo '{}')
    fi
    ;;
esac

mkdir -p .pipeline
jq -nc \
  --arg  ts            "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg  feature       "$FEATURE" \
  --arg  stage         "$STAGE" \
  --arg  status        "$STATUS" \
  --arg  model         "$MODEL" \
  --argjson retries    "$RETRIES" \
  --argjson files_changed "$FILES_CHANGED" \
  --arg  notes         "$NOTES" \
  --argjson extras     "$EXTRAS" \
  '{ts:$ts,feature:$feature,stage:$stage,status:$status,model:$model,
    retries:$retries,files_changed:$files_changed,notes:$notes} + $extras' \
  >> .pipeline/run-log.jsonl

echo "[log-run] $FEATURE / $STAGE / $STATUS (model=$MODEL, files=$FILES_CHANGED)"
