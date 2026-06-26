#!/bin/bash
# Blocks deployment unless interlock files show a clean, CURRENT, documented state.

TEST_RESULTS=".pipeline/test-results.json"
SECURITY_STATUS=".pipeline/security-status.json"
PR_DESCRIPTION=".pipeline/pr-description.md"
REVIEW_MANIFEST=".pipeline/review-manifest.json"

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
  # Identical change-set hash command to the one documentation records (see the
  # diff-scoping-conventions skill); on an empty repo (no HEAD) both sides hash
  # the untracked tree the same way, so they still match.
  CURRENT=$( { git diff HEAD; git ls-files --others --exclude-standard | sort | xargs -r cat; } | sha256sum | awk '{print $1}')
  if [ -z "$RECORDED" ] || [ "$RECORDED" = "null" ] || [ "$RECORDED" != "$CURRENT" ]; then
    echo "Blocked: working tree does not match the reviewed state in $REVIEW_MANIFEST (or no hash recorded); re-run documentation after any change, then re-review." >&2
    exit 2
  fi
fi

exit 0
