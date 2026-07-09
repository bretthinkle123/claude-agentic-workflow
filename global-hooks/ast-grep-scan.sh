#!/usr/bin/env bash
# ast-grep with the U-09 execution stamp (F-M4-5). The security agent calls this wrapper
# instead of bare `ast-grep` so every run leaves a .pipeline/scan-log.jsonl stamp — M4's
# audit could not tell "never ran" from "ran, found nothing" because bare ast-grep leaves
# no trace. Pass the SAME arguments you would pass to the `ast-grep` CLI, e.g.:
#   $HOME/.claude/hooks/ast-grep-scan.sh scan --rule .claude/skills/ast-grep-rules/rules/ src/
#
# ADVISORY BOUNDARY (unchanged from the skill): ast-grep findings go into
# security-report.md prose only. They MUST NOT feed any security-status.json count,
# scan_artifacts entry, or gate/loop-exit conjunct — the stamp proves execution, nothing
# more. reconcile-scans.sh is claim-driven (it verifies only tools named in
# scan_artifacts), so this extra stamp is invisible to the count reconciliation.
set -uo pipefail

if ! command -v ast-grep >/dev/null 2>&1; then
  echo "[ast-grep-scan] ast-grep not on PATH (npm install -g @ast-grep/cli). Skipping is a" >&2
  echo "                DISCLOSED skip: report 'ast-grep unavailable' in security-report.md." >&2
  exit 2
fi

set +e
ast-grep "$@"
_rc=$?
"$(dirname "${BASH_SOURCE[0]}")/stamp-scan.sh" ast-grep "$_rc" "" "$@" >/dev/null 2>&1 || true
exit "$_rc"
