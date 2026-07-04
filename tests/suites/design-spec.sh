#!/usr/bin/env bash
# design-spec.sh — the design-spec stage's ONE deterministic guarantee (DS roadmap row).
# The stage's teeth are a HUMAN checkpoint, not a jq gate (design content never gates — by
# design, so loop-exit is untouched). The single thing that IS mechanically enforceable is the
# forgery guard: a subagent (notably the Write-holding design-spec agent) must not be able to
# fabricate `.pipeline/design-approved` and self-vouch for the design. That is what we assert.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../helpers/assert.sh"

GUARD="$HOOKS/guard-approval-markers.sh"
echo "-- design-spec (design-approved forgery guard) --"

# Feed a PreToolUse payload (same shape as waiver-guard) and return the guard's exit code.
guard_rc() { printf '{"tool_input":{"command":%s}}' "$(jq -Rn --arg c "$1" '$c')" | bash "$GUARD" >/dev/null 2>&1; echo $?; }

# (1) WRITES to design-approved are blocked (exit 2) in every mutating form.
assert_eq 2 "$(guard_rc 'echo x > .pipeline/design-approved')"  "guard blocks redirection into design-approved"
assert_eq 2 "$(guard_rc 'printf "{}" >> .pipeline/design-approved')" "guard blocks append into design-approved"
assert_eq 2 "$(guard_rc 'tee .pipeline/design-approved < x')"   "guard blocks tee into design-approved"
assert_eq 2 "$(guard_rc 'mv t .pipeline/design-approved')"      "guard blocks mv onto design-approved"
assert_eq 2 "$(guard_rc 'touch .pipeline/design-approved')"     "guard blocks touch of design-approved"
# The exact orchestrator-recording command, if a SUBAGENT tried it, is blocked too:
assert_eq 2 "$(guard_rc 'printf "{\"design_spec_hash\":\"h\"}" > .pipeline/design-approved')" \
  "guard blocks the orchestrator's own write form when a subagent runs it"

# (2) READS of design-approved pass through (planning legitimately checks it exists / reads it).
assert_eq 0 "$(guard_rc 'test -f .pipeline/design-approved')"   "guard passes test -f design-approved"
assert_eq 0 "$(guard_rc 'cat .pipeline/design-approved')"       "guard passes reading design-approved (cat)"
assert_eq 0 "$(guard_rc 'jq -r .design_spec_hash .pipeline/design-approved')" "guard passes reading design-approved (jq)"
# A mention inside a commit message (prose, command-position anchored) is NOT a write:
assert_eq 0 "$(guard_rc 'git commit -m "record design-approved marker"')" "guard passes design-approved mention in a commit message"

# (3) Regression: adding design-approved must not have broken the other three guarded markers.
assert_eq 2 "$(guard_rc 'echo x > .pipeline/plan-approved')"    "guard still blocks plan-approved (regression)"
assert_eq 2 "$(guard_rc 'echo x > .pipeline/diff-approved')"    "guard still blocks diff-approved (regression)"
assert_eq 2 "$(guard_rc 'echo x > .pipeline/waivers.json')"     "guard still blocks waivers.json (regression)"

finish design-spec
