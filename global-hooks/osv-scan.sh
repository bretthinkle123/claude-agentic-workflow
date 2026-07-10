#!/usr/bin/env bash
# osv-scan.sh — U-09: thin wrapper around osv-scanner that stamps every execution.
#
# Before U-09 the security agent invoked `osv-scanner` DIRECTLY (raw permission), which
# is exactly why the M3 series' OSV execution claims were uncheckable — no breadcrumb.
# This wrapper runs the real binary with the same args and appends an execution stamp to
# .pipeline/scan-log.jsonl, so a report can only say "OSV executed this pass" when a
# stamp proves it. reconcile-scans.sh recomputes the finding count from the
# .pipeline/osv.json artifact and gates on the match. project-settings.json now grants
# this wrapper path instead of the raw osv-scanner binary.
#
# Usage: identical to osv-scanner — e.g.
#   $HOME/.claude/hooks/osv-scan.sh --format json --output .pipeline/osv.json -L poetry.lock
set -uo pipefail

if ! command -v osv-scanner >/dev/null 2>&1; then
  echo "[osv-scan] osv-scanner not found on PATH. Install it (https://google.github.io/osv-scanner/) then re-run. Do NOT report dependency-clean without it." >&2
  # M4″-A9: stamp the disclosed skip — silent absence must be distinguishable.
  "$(dirname "${BASH_SOURCE[0]}")/stamp-scan.sh" osv 2 "" "skipped: binary not on PATH" >/dev/null 2>&1 || true
  exit 2
fi

osv-scanner "$@"
_rc=$?
"$(dirname "${BASH_SOURCE[0]}")/stamp-scan.sh" osv "$_rc" "" "$@" >/dev/null 2>&1 || true
exit "$_rc"
