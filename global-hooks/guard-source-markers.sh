#!/bin/bash
# guard-source-markers.sh — deterministic block (audit E3) against shipping a tree
# that still carries an experimental / reverted-fix marker in CHANGED source.
#
# The M5 hazard: a debugging agent replaced a money-path fix with the original buggy
# code tagged `// TEMP-PREFIX-REVERT` to demonstrate a repro, then capped before
# restoring it — leaving the money path broken while the build stayed green (no signal).
# It was caught only because a human re-grepped for SAVEPOINT. This hook makes that
# signal deterministic: it greps the change set (tracked diff + untracked files vs HEAD,
# the same set the rest of the pipeline scopes to) for danger markers and blocks.
#
# Two roles (same logic):
#   1. deployment-gate.sh sources/invokes it → a HARD deploy block (the money guarantee).
#   2. Wired as a Stop hook on debugging + implementation → the agent is told, before it
#      can stop, that it left a marker in the tree (exit 2 feeds stderr back to the model).
#
# Markers matched (word-boundary, case-insensitive): TEMP-REVERT / TEMP-PREFIX-REVERT,
# REVERT-ME, XXX-REVERT, DO NOT COMMIT / DO-NOT-COMMIT, HACK-REMOVE, FIXME-BEFORE-COMMIT.
# Plain TODO/FIXME/XXX are NOT matched — those are normal and blocking on them would just
# train people to bypass the gate. Only revert/do-not-commit-class markers block.
#
# Exit: 0 = clean (or no change set / not a pipeline project) · 2 = marker found (BLOCK).
set -uo pipefail

# Pipeline-project guard: no-op outside a bootstrapped pipeline project.
[ -f .pipeline/state.json ] || exit 0

# Danger-marker pattern. Anchored to revert/do-not-commit intent, not ordinary TODOs.
MARKERS='TEMP[-_ ]?(PREFIX[-_ ]?)?REVERT|REVERT[-_ ]?ME|XXX[-_ ]?REVERT|DO[-_ ]?NOT[-_ ]?COMMIT|HACK[-_ ]?REMOVE|FIXME[-_ ]?BEFORE[-_ ]?COMMIT'

# Change set = tracked diff (added lines only) + untracked files vs HEAD. We scan ADDED
# diff lines (leading '+') so a marker being REMOVED in the diff doesn't false-positive,
# and untracked files in full. Exclude this hook itself and test fixtures/suites, which
# legitimately contain marker strings as test data.
EXCLUDE='(^|/)(tests/|.*\.pipeline/|global-hooks/guard-source-markers\.sh)'

hits=""

# 1. Added lines in the tracked diff — restricted to non-excluded paths, so a marker
#    string that legitimately lives in tests/, .pipeline/, or this hook's own test data
#    doesn't false-block a deploy. This mirrors the EXCLUDE the untracked scan (2) already
#    applies; previously the tracked scan ran over the whole `git diff HEAD` unfiltered.
#    NUL-delimited end-to-end (name-only -z | grep -z | xargs -0) so odd filenames and the
#    NUL-stripping of $() capture can't corrupt the file list.
added="$(git diff HEAD --name-only -z 2>/dev/null | grep -zvE "$EXCLUDE" \
         | xargs -0 -r git diff HEAD -- 2>/dev/null | grep -E '^\+' | grep -vE '^\+\+\+' || true)"
if [ -n "$added" ]; then
  m="$(printf '%s\n' "$added" | grep -inE "$MARKERS" || true)"
  [ -n "$m" ] && hits="$hits"$'\n'"tracked diff:"$'\n'"$m"
fi

# 2. Untracked files (skip excluded paths and binaries).
while IFS= read -r -d '' f; do
  case "$f" in
    *) printf '%s' "$f" | grep -qE "$EXCLUDE" && continue ;;
  esac
  [ -f "$f" ] || continue
  grep -Iq . "$f" 2>/dev/null || continue   # -I: skip binary files
  m="$(grep -inE "$MARKERS" "$f" 2>/dev/null || true)"
  [ -n "$m" ] && hits="$hits"$'\n'"$f:"$'\n'"$m"
done < <(git ls-files -z --others --exclude-standard 2>/dev/null || true)

if [ -n "$hits" ]; then
  echo "Blocked: the change set contains an experimental / revert marker (audit E3) — a" >&2
  echo "reverted or do-not-commit fix must never ship. Restore the real fix (prove repros in" >&2
  echo "a scratch copy, never in the tree), then re-run. Offending lines:" >&2
  printf '%s\n' "$hits" >&2
  exit 2
fi
exit 0
