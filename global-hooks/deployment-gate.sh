#!/bin/bash
# Blocks deployment unless interlock files show a clean, CURRENT, documented state.
#
# Installed globally at ~/.claude/hooks/ and wired as the deployment agent's Bash
# PreToolUse gate. Deliberately has NO ".pipeline/state.json" no-op guard (unlike
# the ambient Stop hooks): if it ever fires outside a bootstrapped pipeline project
# the interlock files below are absent, so every check fails CLOSED (blocks) —
# exactly the safe behavior. Resolve sibling hooks relative to THIS script (not the
# CWD) so the global install location still finds compute-change-hash.sh.
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

TEST_RESULTS=".pipeline/test-results.json"
SECURITY_STATUS=".pipeline/security-status.json"
PR_DESCRIPTION=".pipeline/pr-description.md"
REVIEW_MANIFEST=".pipeline/review-manifest.json"

# Fail closed if jq is unavailable — every status check below depends on it.
# (Without this a missing jq still blocks, but with a misleading "tests not
# passing" reason; this makes the block reason accurate.)
if ! command -v jq >/dev/null 2>&1; then
  echo "Blocked: jq not found on PATH — cannot verify gate status. Install jq and restart the session." >&2
  exit 2
fi

if [ ! -f "$TEST_RESULTS" ] || [ "$(jq -r '.status' "$TEST_RESULTS")" != "pass" ]; then
  echo "Blocked: tests are not passing. See $TEST_RESULTS." >&2
  exit 2
fi

# Acceptance-criteria coverage must be COMPLETE (PR C). Every criterion testing
# recorded from acceptance.md must be covered. This is the SAME condition the
# orchestrator's run-to-condition loop exits on, so loop-exit ≡ deploy gate and the
# two cannot drift. An absent/empty criteria_covered (a feature with no acceptance
# criteria, or a pre-PR-C result file) means total 0 == covered 0 → complete, so
# this no-ops for those — never blocks a legitimately criteria-less change.
CRIT_TOTAL=$(jq -r '(.criteria_covered.total // 0)' "$TEST_RESULTS")
CRIT_COVERED=$(jq -r '(.criteria_covered.covered // 0)' "$TEST_RESULTS")
if [ "$CRIT_COVERED" -lt "$CRIT_TOTAL" ]; then
  echo "Blocked: acceptance criteria not fully covered ($CRIT_COVERED/$CRIT_TOTAL). See $TEST_RESULTS .criteria_covered." >&2
  exit 2
fi

# Criterion-completeness (PR G / F1). Counting criteria_covered trusts the testing
# agent's per-criterion covered:true; this adds a deterministic backstop for the one
# structured "measurable dimension" the schema carries — a declared perf budget must
# actually be MEASURED. If perf mode ran (status != n/a) and a non-null budget field
# (p95_ms / throughput_rps) has a null measured counterpart, the load/latency half of
# the criterion was never exercised — block, so a partial verification can't score the
# AC complete. Budget fields derive from the acceptance criterion's wording, so the
# honest fix is to measure it or mark the criterion uncovered (which then fails the
# criteria_covered check above). This same predicate is mirrored in the orchestrator's
# loop-exit (pipeline-orchestration skill), so loop-exit ≡ gate and the two never drift.
PERF_GAP=$(jq -r '
  if (.perf.status // "n/a") == "n/a" then "ok"
  elif (.perf.budget.p95_ms != null and .perf.measured.p95_ms == null) then "p95_ms"
  elif (.perf.budget.throughput_rps != null and .perf.measured.throughput_rps == null) then "throughput_rps"
  else "ok" end' "$TEST_RESULTS")
if [ "$PERF_GAP" != "ok" ]; then
  echo "Blocked: perf criterion under-covered — budget declares $PERF_GAP but measured is null. Measure it or mark the criterion uncovered. See $TEST_RESULTS .perf." >&2
  exit 2
fi

if [ ! -f "$SECURITY_STATUS" ] || [ "$(jq -r '.status' "$SECURITY_STATUS")" != "clean" ]; then
  echo "Blocked: security status is not clean. See .pipeline/security-report.md." >&2
  exit 2
fi

if [ ! -f "$PR_DESCRIPTION" ]; then
  echo "Blocked: documentation has not produced $PR_DESCRIPTION." >&2
  exit 2
fi

# Currency applies to the COMMIT only. Once the reviewed change is committed the
# working tree is clean (git status --porcelain is empty), so the later commands
# in the same deployment run (git push, gh pr create) pass straight through — the
# commit already cleared this gate. While work is still uncommitted, the bytes
# about to be committed must match exactly the reviewed state that documentation
# finalized in review-manifest.json (README/architecture writes included).
if [ -n "$(git status --porcelain)" ]; then
  RECORDED=$(jq -r '.reviewed_change_hash' "$REVIEW_MANIFEST" 2>/dev/null)
  # Shared change-set hash helper: documentation's write-review-manifest.sh records
  # reviewed_change_hash via this same script, so the two match byte-for-byte (see
  # the diff-scoping-conventions skill). On an empty repo (no HEAD) both sides hash
  # the untracked tree identically, so they still match.
  CURRENT=$("$HOOK_DIR/compute-change-hash.sh")
  if [ -z "$RECORDED" ] || [ "$RECORDED" = "null" ] || [ "$RECORDED" != "$CURRENT" ]; then
    echo "Blocked: working tree does not match the reviewed state in $REVIEW_MANIFEST (or no hash recorded); re-run documentation after any change, then re-review." >&2
    exit 2
  fi
fi

exit 0
