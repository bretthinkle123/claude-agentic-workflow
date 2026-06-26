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
