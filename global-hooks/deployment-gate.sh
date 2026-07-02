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
# A declared perf budget must be MEASURED (p95/throughput non-null) AND the measured
# run must DISCLOSE its scenario (audit WS3-3). In the trial the headline perf number
# was a best case (webhook disabled, uncontended, amount:1) reported without that
# context — a true number measured under an unrepresentative scenario overstates. A
# non-null `.perf.scenario` (the harness records what it actually exercised) is now
# required when perf ran, so the metric can't silently be a best case. Mirrored in the
# orchestrator loop-exit (SKILL) + loop-exit-predicate.jq — loop-exit ≡ gate.
PERF_GAP=$(jq -r '
  if (.perf.status // "n/a") == "n/a" then "ok"
  elif (.perf.budget.p95_ms != null and .perf.measured.p95_ms == null) then "p95_ms"
  elif (.perf.budget.throughput_rps != null and .perf.measured.throughput_rps == null) then "throughput_rps"
  elif (.perf.scenario == null) then "scenario"
  else "ok" end' "$TEST_RESULTS")
if [ "$PERF_GAP" = "scenario" ]; then
  echo "Blocked: perf ran but $TEST_RESULTS .perf.scenario is null — the measured scenario is undisclosed (a best-case number reported as the headline overstates). Record .perf.scenario (what the harness actually exercised: concurrency, workload, webhook on/off, contention)." >&2
  exit 2
elif [ "$PERF_GAP" != "ok" ]; then
  echo "Blocked: perf criterion under-covered — budget declares $PERF_GAP but measured is null. Measure it or mark the criterion uncovered. See $TEST_RESULTS .perf." >&2
  exit 2
fi

if [ ! -f "$SECURITY_STATUS" ] || [ "$(jq -r '.status' "$SECURITY_STATUS")" != "clean" ]; then
  echo "Blocked: security status is not clean. See .pipeline/security-report.md." >&2
  exit 2
fi

# CVE-severity floor (audit B6). `status:"clean"` is the security agent's judgment; this
# is a DETERMINISTIC backstop so a High/Critical OSV finding (CVSS >= 7.0) cannot ship as
# clean without an explicit, recorded `.osv_waiver`. A CVSS 7.5 High shipped green in the
# audited run precisely because nothing independently checked severity. `.osv_max_cvss`
# is the max CVSS across remaining (unfixed) OSV findings, written by the security agent;
# absent ⇒ 0 ⇒ no block. This same predicate is mirrored in the orchestrator's loop-exit
# security check (pipeline-orchestration SKILL.md) so loop-exit ≡ gate and the two never
# drift (asserted by tests/suites/loop-exit-invariant.sh).
CVE_BLOCK=$(jq -r 'if ((.osv_max_cvss // 0) >= 7) and ((.osv_waiver // null) == null) then "block" else "ok" end' "$SECURITY_STATUS")
if [ "$CVE_BLOCK" = "block" ]; then
  echo "Blocked: an OSV finding at CVSS >= 7.0 (High/Critical) remains and no .osv_waiver is recorded in $SECURITY_STATUS. Patch the dependency, or record an explicit waiver {id, reason, approved_by} after a human accepts the risk. See .pipeline/security-report.md." >&2
  exit 2
fi

# Reverted / do-not-commit source markers (audit E3). A reverted money-path fix once
# passed build-green and nearly shipped; this makes the signal deterministic. The guard
# no-ops on a clean change set and self-skips outside a pipeline project.
if ! "$HOOK_DIR/guard-source-markers.sh"; then
  exit 2   # guard already printed the offending lines to stderr
fi

if [ ! -f "$PR_DESCRIPTION" ]; then
  echo "Blocked: documentation has not produced $PR_DESCRIPTION." >&2
  exit 2
fi

# Mutation scope-pairing (audit WS3-1) — a DEPLOY-ONLY honesty check, deliberately NOT in
# the loop-exit predicate. Mutation quality is settled-ADVISORY (a low kill score never
# blocks) and folding it into the per-cycle loop would re-introduce the exact per-loop
# mutation cost that drives the cap-out problem. But a FALSE completeness claim must not
# ship: in the trial `quality_ok:true` was written while the mutation scope had silently
# shrunk from the configured set (stryker.conf `mutate`) to one file — so the security-
# critical guard shipped mutation-UNMEASURED under a green quality flag. This blocks only
# that lie: quality_ok=true asserted while `mutation.scope` fails to cover
# `mutation.configured_scope`, with no recorded `quality_waiver`. An honest quality_ok=false
# still ships (advisory); running the full scope or recording a waiver clears the block.
# test-quality.json is optional (projects with no mutation tool omit it) → absent ⇒ no-op.
TEST_QUALITY=".pipeline/test-quality.json"
if [ -f "$TEST_QUALITY" ]; then
  QUAL_BLOCK=$(jq -r '
    if (.quality_ok == true)
       and (((.mutation.configured_scope // []) - (.mutation.scope // [])) | length > 0)
       and ((.quality_waiver // null) == null)
    then "block" else "ok" end' "$TEST_QUALITY" 2>/dev/null || echo "ok")
  if [ "$QUAL_BLOCK" = "block" ]; then
    MISSING=$(jq -rc '((.mutation.configured_scope // []) - (.mutation.scope // []))' "$TEST_QUALITY" 2>/dev/null)
    echo "Blocked: $TEST_QUALITY claims quality_ok=true but mutation.scope does not cover the configured mutation scope (uncovered: $MISSING). Either run mutation over the full configured scope, set quality_ok=false (honest advisory), or record a quality_waiver {id, reason, approved_by} after a human accepts the gap." >&2
    exit 2
  fi
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
