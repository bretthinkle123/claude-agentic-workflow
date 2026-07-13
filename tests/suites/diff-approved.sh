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

# --- F1 per-path currency (events-force-rls run: two gate blocks from out-of-scope dirt) ---
# Marker with approved_paths: the gate verifies each changed path's bytes, so a
# diff-scoped commit that leaves APPROVED out-of-scope files dirty passes, while any
# NEW path, byte drift, or staged tamper still blocks.
approve_paths_marker() { # writes a new-format marker for the CURRENT change set of $1
  ( cd "$1"
    paths=$( { git diff HEAD --name-only 2>/dev/null; git ls-files --others --exclude-standard; } \
      | LC_ALL=C sort -u | while IFS= read -r p; do
          [ -n "$p" ] || continue
          if [ -f "$p" ]; then h=$(sha256sum "$p" | cut -d' ' -f1); else h="__deleted__"; fi
          jq -nc --arg p "$p" --arg h "$h" '{($p): $h}'
        done | jq -sc 'add // {}')
    jq -nc --arg h "$(bash "$HOOKS/compute-change-hash.sh")" --argjson paths "$paths" \
      '{approved_change_hash:$h, approved_paths:$paths, approved_at:"2026-07-13T00:00:00Z"}' \
      > .pipeline/diff-approved )
}

# Fixture: one feature file (app.py, already dirty from mk_git_fixture) + one
# out-of-scope file, both present at approval time.
w="$(mk_git_fixture)"
echo 'out-of-scope operator edit' > "$w/PROJECT.md"
approve_paths_marker "$w"
( cd "$w" && bash "$GATE" ) >/dev/null 2>&1
assert_eq 0 "$?" "F1: per-path marker, tree exactly as approved → pass"

# Staging an approved file must NOT block (Block 1 regression: add→commit split).
( cd "$w" && git add app.py && bash "$GATE" ) >/dev/null 2>&1
assert_eq 0 "$?" "F1: staging an approved file no longer shifts currency → pass"

# Diff-scoped commit leaving the approved out-of-scope file dirty must NOT block
# (Block 2 regression: post-commit residue blocked push/pr).
( cd "$w" && git commit -qm feature -- app.py && bash "$GATE" ) >/dev/null 2>&1
assert_eq 0 "$?" "F1: post-commit residue of APPROVED out-of-scope dirt → pass"

# A NEW path created after approval is not in the approved set → block (teeth).
echo 'sneaky' > "$w/new-unapproved.txt"
( cd "$w" && bash "$GATE" ) >/dev/null 2>&1
assert_eq 2 "$?" "F1: new unapproved path after approval → block"
rm -f "$w/new-unapproved.txt"

# Byte drift in an approved file after approval → block (teeth).
echo 'drifted' >> "$w/PROJECT.md"
( cd "$w" && bash "$GATE" ) >/dev/null 2>&1
assert_eq 2 "$?" "F1: approved path with drifted bytes → block"

# Staged-tamper vector: stage malicious bytes, then restore the worktree to the
# approved bytes — the commit would ship the INDEX, so the gate must block.
w="$(mk_git_fixture)"
approve_paths_marker "$w"
( cd "$w"
  cp app.py /tmp/approved-app.py.$$
  echo 'malicious' > app.py
  git add app.py
  cp /tmp/approved-app.py.$$ app.py; rm -f /tmp/approved-app.py.$$
  bash "$GATE" ) >/dev/null 2>&1
assert_eq 2 "$?" "F1: staged bytes differ from approved while worktree matches → block (staged-tamper)"

finish diff-approved
