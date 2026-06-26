#!/bin/bash
# Resets the debug retry counters when, and only when, both gate reports are
# clean/passing. Safe to fire on every testing-completion event; no-ops otherwise.

STATE=".pipeline/state.json"
TEST_RESULTS=".pipeline/test-results.json"
SECURITY_STATUS=".pipeline/security-status.json"

if [ ! -f "$TEST_RESULTS" ] || [ "$(jq -r '.status' "$TEST_RESULTS")" != "pass" ]; then
  exit 0
fi
if [ ! -f "$SECURITY_STATUS" ] || [ "$(jq -r '.status' "$SECURITY_STATUS")" != "clean" ]; then
  exit 0
fi

tmp=$(mktemp)
jq '.debug_retry_count = {"sanity":0,"remediation":0}' "$STATE" > "$tmp" && mv "$tmp" "$STATE"

exit 0
