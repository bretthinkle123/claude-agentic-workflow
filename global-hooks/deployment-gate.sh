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
DIFF_APPROVED=".pipeline/diff-approved"

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

# Human diff-review checkpoint (M5) + currency, anchored to the HUMAN's approval (F3).
# Applies to the COMMIT only: once the reviewed change is committed the working tree is
# clean (git status --porcelain empty), so the later commands in the same run (git push,
# gh pr create) pass straight through — the commit already cleared this gate. While work
# is still uncommitted, a human must have approved the diff (`.pipeline/diff-approved`,
# written only by approve-diff.sh, which refuses without a TTY), AND the bytes about to be
# committed must match exactly the hash that human approved.
#
# The anchor is the human-owned diff-approved hash, NOT documentation's review-manifest:
# that removes the F3 vector — the deployment agent can regenerate review-manifest (it's
# in its Bash allow-list), but the gate no longer reads it, and any tree change the agent
# makes shifts the change-set hash away from approved_change_hash → blocked → re-review.
# approve-diff.sh is human-only (TTY) and the deployment agent is instructed never to
# write diff-approved itself; the gate can't verify who wrote the file. That fabrication
# vector is now structurally guarded (PR K): guard-approval-markers.sh (a PreToolUse Bash
# hook on every Bash agent) blocks commands that write the marker, and a settings
# Write/Edit deny covers the tool vector. The residual — obfuscated Bash past the string
# scan — is documented in docs/pipeline-threat-model.md; this gate still doesn't verify
# authorship, it relies on those two guards + the currency hash below.
if [ -n "$(git status --porcelain)" ]; then
  if [ ! -f "$DIFF_APPROVED" ]; then
    echo "Blocked: no human diff approval. Review the diff + the security/test/quality reports, then run approve-diff.sh (the M5 diff-review checkpoint)." >&2
    exit 2
  fi
  APPROVED=$(jq -r '.approved_change_hash' "$DIFF_APPROVED" 2>/dev/null)
  # Shared change-set hash helper: approve-diff.sh records approved_change_hash via this
  # same script, so the two match byte-for-byte (see the diff-scoping-conventions skill).
  # On an empty repo (no HEAD) both sides hash the untracked tree identically.
  CURRENT=$("$HOOK_DIR/compute-change-hash.sh")
  if [ -z "$APPROVED" ] || [ "$APPROVED" = "null" ] || [ "$APPROVED" != "$CURRENT" ]; then
    echo "Blocked: working tree does not match the human-approved diff ($DIFF_APPROVED approved_change_hash). Something changed after approval — re-review and re-run approve-diff.sh." >&2
    exit 2
  fi
fi

exit 0
