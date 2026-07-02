#!/usr/bin/env bash
# marker-guard.sh — proves guard-approval-markers.sh (PR K) blocks a subagent from
# FORGING a human-owned approval marker (.pipeline/diff-approved / plan-approved) via
# Bash, while passing every legitimate command (incl. the implementation agent's
# read-only `test -f plan-approved` and documentation's write-review-manifest.sh).
#
# Feeds a PreToolUse-shaped event on stdin and asserts the hook's exit code:
#   exit 2 = blocked (a marker WRITE), exit 0 = allowed.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../helpers/assert.sh"

HOOK="$HOOKS/guard-approval-markers.sh"
echo "-- marker-guard (PR K) --"

# feed <command-string> — pipe a realistic PreToolUse Bash event into the hook.
feed() {
  printf '{"tool_name":"Bash","tool_input":{"command":%s}}' "$(jq -Rn --arg c "$1" '$c')" | bash "$HOOK"
}
# feed_raw <payload> — pipe an arbitrary payload (no .tool_input.command) to exercise
# the fail-toward-inspection fallback (scan the whole stdin when the field is absent).
feed_raw() { printf '%s' "$1" | bash "$HOOK"; }

assert_exit 0 "hook parses (bash -n)" bash -n "$HOOK"

# --- BLOCK: writes to a marker, across shapes -------------------------------------
assert_exit 2 "block: printf > diff-approved"        feed "printf '{}' > .pipeline/diff-approved"
assert_exit 2 "block: echo >> plan-approved"         feed "echo x >> .pipeline/plan-approved"
assert_exit 2 "block: jq > diff-approved"            feed "jq -n '{}' > .pipeline/diff-approved"
assert_exit 2 "block: redirect no space"             feed ">.pipeline/diff-approved"
assert_exit 2 "block: cp into plan-approved"         feed "cp /tmp/x .pipeline/plan-approved"
assert_exit 2 "block: mv into diff-approved"         feed "mv /tmp/x .pipeline/diff-approved"
assert_exit 2 "block: tee diff-approved"             feed "printf x | tee .pipeline/diff-approved"
assert_exit 2 "block: touch plan-approved"           feed "touch .pipeline/plan-approved"
assert_exit 2 "block: sed -i on diff-approved"       feed "sed -i 's/a/b/' .pipeline/diff-approved"
assert_exit 2 "block: quoted path redirect"          feed "printf x > './.pipeline/plan-approved'"

# --- ALLOW: legitimate reads + the real command sets ------------------------------
assert_exit 0 "allow: test -f plan-approved (impl read)" feed "test -f .pipeline/plan-approved"
assert_exit 0 "allow: [ -f ] plan-approved"          feed "[ -f .pipeline/plan-approved ] && echo ok"
assert_exit 0 "allow: cat plan-approved"             feed "cat .pipeline/plan-approved"
assert_exit 0 "allow: git add+commit"                feed "git add -A && git commit -m 'x'"
assert_exit 0 "allow: git status"                    feed "git status --porcelain"
assert_exit 0 "allow: gh pr create"                  feed "gh pr create --title t --body-file .pipeline/pr-description.md"
assert_exit 0 "allow: write-review-manifest.sh (no false pos)" feed "bash ~/.claude/hooks/write-review-manifest.sh"
assert_exit 0 "allow: compute-change-hash.sh"        feed "bash ~/.claude/hooks/compute-change-hash.sh"
assert_exit 0 "allow: writes an unrelated file"      feed "printf x > .pipeline/pr-description.md"

# --- Regression: audit findings (redirect shapes + prose-in-commit-message FP) -----
assert_exit 2 "block: force-clobber >| marker"       feed "printf x >| .pipeline/diff-approved"
assert_exit 2 "block: &> redirect marker"            feed "cmd &> .pipeline/diff-approved"
assert_exit 2 "block: mutating verb after || sep"    feed "false || touch .pipeline/plan-approved"
# The mutating verbs are anchored to a command position: a verb appearing as PROSE in a
# git commit message (the deployment agent's real command, esp. on approval-system PRs)
# must NOT be mistaken for a write.
assert_exit 0 "allow: commit msg says 'touch up …diff-approved'" feed "git commit -m 'touch up .pipeline/diff-approved handling'"
assert_exit 0 "allow: commit msg says 'cp of …plan-approved'"    feed "git commit -m 'cp of .pipeline/plan-approved semantics'"
assert_exit 0 "allow: grep the marker path (read)"   feed "grep -r '.pipeline/diff-approved' global-hooks/"

# --- Fallback: field absent ⇒ scan raw payload, still catch a marker write --------
assert_exit 2 "fallback: marker write in raw payload"  feed_raw '{"weird":"echo x > .pipeline/diff-approved"}'
assert_exit 0 "fallback: benign raw payload"           feed_raw '{"weird":"git commit -m x"}'

# --- Wiring: the guard is actually a PreToolUse hook on all 7 Bash-carrying agents.
# (static.sh only checks the hook FILE resolves; this checks it's WIRED — catches a
# silently-dropped wiring that would leave an agent's marker vector unguarded.)
WIRED="$(grep -lE 'guard-approval-markers\.sh' "$REPO_ROOT"/global-agents/*.md | wc -l | tr -d ' ')"
assert_eq 7 "$WIRED" "guard-approval-markers.sh wired on all 7 Bash-carrying agents"

finish marker-guard
