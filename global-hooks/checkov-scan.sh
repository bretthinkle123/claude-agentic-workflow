#!/usr/bin/env bash
# checkov-scan.sh — U-09: thin wrapper around checkov that stamps every execution.
#
# Before U-09 the security agent invoked `checkov` DIRECTLY (raw permission) — no
# execution breadcrumb, so a report's Checkov claims were uncheckable (M3 shipped a
# Checkov finding on a NEW resource while the on-disk checkov.json was a prior run's).
# This wrapper runs the real binary with the same args and appends a stamp to
# .pipeline/scan-log.jsonl. reconcile-scans.sh recomputes the failed-check count from
# the .pipeline/checkov.json artifact (top-level ARRAY: sum of .[].summary.failed) and
# gates on the match. project-settings.json grants this wrapper instead of raw checkov.
#
# Usage: identical to checkov — e.g.
#   $HOME/.claude/hooks/checkov-scan.sh -d infra --output json --output-file-path .pipeline
set -uo pipefail

if ! command -v checkov >/dev/null 2>&1; then
  echo "[checkov-scan] checkov not found on PATH. Install it (pip install checkov) then re-run. Do NOT report infra-clean without it." >&2
  exit 2
fi

checkov "$@"
_rc=$?
"$(dirname "${BASH_SOURCE[0]}")/stamp-scan.sh" checkov "$_rc" "" "$@" >/dev/null 2>&1 || true
exit "$_rc"
