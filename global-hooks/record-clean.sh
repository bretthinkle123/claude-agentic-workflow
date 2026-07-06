#!/bin/bash
# Resets the debug retry counters when, and only when, both gate reports are
# clean/passing. Safe to fire on every testing-completion event; no-ops otherwise.
#
# Scope: this touches ONLY .pipeline/state.json's per-cycle `debug_retry_count`. It
# deliberately does NOT touch the feature-level circuit-breaker budget in
# .pipeline/loop-state.json (owned by loop-guard.sh) — if a transiently-clean cycle
# reset that budget, the breaker could never bound a thrashing loop. Keep them apart.

STATE=".pipeline/state.json"
TEST_RESULTS=".pipeline/test-results.json"
SECURITY_STATUS=".pipeline/security-status.json"

# Pipeline-project guard: installed globally; no-op (and no jq warning) in any repo
# that is not a bootstrapped pipeline project — there are no retry counters to reset.
[ -f "$STATE" ] || exit 0

# jq reads the gate status below. If it is missing, surface that (non-zero,
# non-silent) instead of no-op'ing as if the gates weren't clean — a silent skip
# would leave the retry counters un-reset on a genuinely clean pass. Exit 1, not 2,
# so a missing tool reports without blocking the testing agent's stop.
if ! command -v jq >/dev/null 2>&1; then
  echo "[record-clean] jq not found on PATH — cannot evaluate gate status; counters not reset. Install jq and restart the session." >&2
  exit 1
fi

if [ ! -f "$TEST_RESULTS" ] || [ "$(jq -r '.status' "$TEST_RESULTS")" != "pass" ]; then
  exit 0
fi
if [ ! -f "$SECURITY_STATUS" ] || [ "$(jq -r '.status' "$SECURITY_STATUS")" != "clean" ]; then
  exit 0
fi

tmp=$(mktemp)
jq '.debug_retry_count = {"sanity":0,"remediation":0}' "$STATE" > "$tmp" && mv "$tmp" "$STATE"

exit 0
