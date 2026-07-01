#!/usr/bin/env bash
# diff-approved.sh — the M5 human diff-review gate + F3 currency anchor (PR I1).
#   part A: approve-diff.sh is human-only (refuses without a TTY) and project-guarded
#   part B: deployment-gate.sh, in a real git repo, requires diff-approved AND that the
#           commit hash matches approved_change_hash (exercises the dirty-tree path that
#           self-skips in a non-git workdir)
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../helpers/assert.sh"

AD="$HOOKS/approve-diff.sh"
GATE="$HOOKS/deployment-gate.sh"
echo "-- diff-approved (M5 + F3) --"

command -v git >/dev/null 2>&1 || { _no "git not on PATH — cannot run diff-approved suite"; finish diff-approved; }

# --- part A: approve-diff.sh guards (stdin is not a TTY inside the harness) ---
# In a bootstrapped project but non-interactive → must refuse (exit 2), never self-approve.
w="$(mk_fixture)"   # has .pipeline/state.json + review-manifest.json
( cd "$w" && bash "$AD" </dev/null ) >/dev/null 2>&1
assert_eq 2 "$?" "approve-diff refuses without a TTY (exit 2)"
[ -f "$w/.pipeline/diff-approved" ] && _no "approve-diff wrote diff-approved without a TTY (!!)" || _ok "no diff-approved written without a TTY"

# Outside a pipeline project → exit 1 (guard fires before the TTY check).
wbare="$(mktemp -d)"; _WORKDIRS+=("$wbare")
( cd "$wbare" && bash "$AD" </dev/null ) >/dev/null 2>&1
assert_eq 1 "$?" "approve-diff outside a project → exit 1"

# --- part B: the gate's diff-approval enforcement in a real git repo ---
# No diff-approved yet → the M5 checkpoint blocks.
w="$(mk_git_fixture)"
( cd "$w" && bash "$GATE" ) >/dev/null 2>&1
assert_eq 2 "$?" "dirty tree, no diff-approved → block (M5)"

# A stale approval (wrong hash) → block (F3: post-approval drift can't ship).
echo '{"approved_change_hash":"deadbeef","approved_at":"2026-07-01T00:00:00Z"}' > "$w/.pipeline/diff-approved"
( cd "$w" && bash "$GATE" ) >/dev/null 2>&1
assert_eq 2 "$?" "diff-approved with stale hash → block (F3)"

# The correct approved hash (what a human approval records) → gate passes.
H="$(change_hash "$w")"
jq -nc --arg h "$H" '{approved_change_hash:$h, approved_at:"2026-07-01T00:00:00Z"}' > "$w/.pipeline/diff-approved"
( cd "$w" && bash "$GATE" ) >/dev/null 2>&1
assert_eq 0 "$?" "diff-approved hash == tree → pass"

# Tamper after approval: modify the reviewed file → hash drifts → block again (F3).
printf 'def handler():\n    return "TAMPERED"\n' > "$w/app.py"
( cd "$w" && bash "$GATE" ) >/dev/null 2>&1
assert_eq 2 "$?" "tree changed after approval → block (F3)"

# Once committed, the tree is clean → the dirty-tree checks are skipped → pass.
( cd "$w" && git add -A && git commit -qm change ) >/dev/null 2>&1
( cd "$w" && bash "$GATE" ) >/dev/null 2>&1
assert_eq 0 "$?" "post-commit clean tree → pass (dirty-tree checks skipped)"

# F3 regression guard: the gate must NOT read review-manifest as its currency anchor.
grep -qF 'reviewed_change_hash' "$GATE" && _no "gate still references reviewed_change_hash (F3 vector)" || _ok "gate does not reference reviewed_change_hash (F3 closed)"

finish diff-approved
