#!/bin/bash
# Appends one line to .pipeline/run-log.jsonl — the pipeline's per-stage telemetry.
# Zero-LLM, deterministic. The orchestrator calls it at each stage boundary.
#
# Usage: log-run.sh <feature> <stage> <status> [retries] [notes]
#   feature : slug for the change (e.g. "file-upload")
#   stage   : planning|implementation|debugging|security|testing|documentation|deployment
#   status  : pass|fail|clean|issues-found|blocked|escalated
#   retries : integer debug count for this stage (default 0)
#   notes   : free-text (default empty)
#
# duration_s / tokens from the spec schema are omitted in v1 (not deterministically
# available from a shell); add them later if the run result exposes them.
set -euo pipefail

FEATURE="${1:?feature slug required}"
STAGE="${2:?stage required}"
STATUS="${3:?status required}"
RETRIES="${4:-0}"
NOTES="${5:-}"

mkdir -p .pipeline
jq -nc \
  --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg feature "$FEATURE" \
  --arg stage "$STAGE" \
  --arg status "$STATUS" \
  --argjson retries "$RETRIES" \
  --arg notes "$NOTES" \
  '{ts:$ts,feature:$feature,stage:$stage,status:$status,retries:$retries,notes:$notes}' \
  >> .pipeline/run-log.jsonl

echo "[log-run] recorded: $FEATURE / $STAGE / $STATUS (retries=$RETRIES)"
