#!/usr/bin/env bash
# Pipeline eval / regression harness (M8) — entry point.
#
# Deterministic, zero-LLM, zero new deps (bash + jq). Runs every suite against
# golden fixture artifacts and asserts the deterministic layer behaves: gate
# block/pass, loop-guard caps, stamp-ran-at normalization, record-clean, static
# wiring, and the loop-exit ≡ gate no-drift invariant. Not a runtime gate; not
# published to ~/.claude. Run it after editing anything under global-agents/,
# global-hooks/, or global-skills/.
#
# Usage:  bash tests/run-eval.sh [-v]     # -v prints passing assertions too
# Exit:   0 iff every suite passes (CI-ready — PR L wires this as a job).
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ "${1:-}" = "-v" ] && export VERBOSE=1

SUITES=(static gate diff-approved marker-guard lockfile-check ci-scan-base loop-guard loop-exit-invariant stamp-ran-at record-clean hash-determinism asvs waiver-guard asvs-sast design-spec egress assurance design-review dast-review store-compliance triage bootstrap-integration smoke-check tree-hygiene doc-identifiers scan-reconcile)

command -v jq >/dev/null 2>&1 || { echo "run-eval: jq is required on PATH." >&2; exit 2; }

echo "=== pipeline eval harness ==="
fails=0
for s in "${SUITES[@]}"; do
  if ! bash "$ROOT/suites/$s.sh"; then
    fails=$((fails + 1))
  fi
done
echo "============================="
if [ "$fails" -eq 0 ]; then
  echo "ALL SUITES PASSED"
  exit 0
fi
echo "$fails SUITE(S) FAILED"
exit 1
