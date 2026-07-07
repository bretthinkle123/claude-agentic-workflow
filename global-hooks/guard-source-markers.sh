#!/bin/bash
# guard-source-markers.sh — deterministic block (audit E3) against shipping a tree
# that still carries an experimental / reverted-fix marker in CHANGED source.
#
# The M5 hazard: a debugging agent replaced a money-path fix with the original buggy
# code tagged with an experimental scratch-revert marker (a TEMP-style prefix combined
# with a REVERT suffix — see the pattern list below) to demonstrate a repro, then capped
# before restoring it — leaving the money path broken while the build stayed green (no
# signal). It was caught only because a human re-grepped for SAVEPOINT. This hook makes
# that signal deterministic: it greps the change set (tracked diff + untracked files vs
# HEAD, the same set the rest of the pipeline scopes to) for danger markers and blocks.
#
# Two roles (same logic):
#   1. deployment-gate.sh sources/invokes it → a HARD deploy block (the money guarantee).
#   2. Wired as a Stop hook on debugging + implementation → the agent is told, before it
#      can stop, that it left a marker in the tree (exit 2 feeds stderr back to the model).
#
# Markers matched (word-boundary, case-insensitive; see the MARKERS regex below for the
# exact shapes — U-05: this prose deliberately DESCRIBES them instead of spelling them,
# so the scaffold copy of this file never trips the guard itself): a TEMP tag combined
# with a REVERT suffix (optionally via an extra prefix word); a REVERT tag combined with
# an ME suffix; an XXX tag combined with a REVERT suffix; a phrase meaning the change
# must not be committed; a HACK tag with a REMOVE suffix; a FIXME tag scoped to
# before-commit. Plain TODO/FIXME/XXX are NOT matched — those are normal and blocking on
# them would just train people to bypass the gate. Only experimental-revert or
# must-not-ship-class markers block.
#
# Exit: 0 = clean (or no change set / not a pipeline project) · 2 = marker found (BLOCK).
set -uo pipefail

# CI re-run mode (PR L, job 6): SCAN_BASE=<ref> rescopes the added-lines scan to
# `git diff SCAN_BASE...HEAD` — on a merge commit `git diff HEAD` is empty, so a naive CI
# re-run passes vacuously. Added-lines-only semantics are PRESERVED (a full-tree grep would
# false-block on a marker being *removed*). The state.json guard is skipped in CI (not a
# bootstrapped checkout); an unresolvable SCAN_BASE fails CLOSED (exit 2), never vacuous.
# Exit 2 on a hit is already the contract, so CI needs no separate failure path.
DIFF_REF="HEAD"
if [ -n "${SCAN_BASE:-}" ]; then
  git rev-parse --verify --quiet "$SCAN_BASE^{commit}" >/dev/null 2>&1 || {
    echo "[guard-source-markers] SCAN_BASE '$SCAN_BASE' does not resolve to a commit — failing closed." >&2
    exit 2
  }
  DIFF_REF="$SCAN_BASE...HEAD"
else
  # Pipeline-project guard: no-op outside a bootstrapped pipeline project.
  [ -f .pipeline/state.json ] || exit 0
fi

# Danger-marker pattern. Anchored to experimental-revert or must-not-ship intent, not
# ordinary TODOs. (The regex itself does not self-match — verified in marker-guard.sh.)
MARKERS='TEMP[-_ ]?(PREFIX[-_ ]?)?REVERT|REVERT[-_ ]?ME|XXX[-_ ]?REVERT|DO[-_ ]?NOT[-_ ]?COMMIT|HACK[-_ ]?REMOVE|FIXME[-_ ]?BEFORE[-_ ]?COMMIT'

# Change set = tracked diff (added lines only) + untracked files vs HEAD. We scan ADDED
# diff lines (leading '+') so a marker being REMOVED in the diff doesn't false-positive,
# and untracked files in full. Exclude this hook's own definition files by path — the
# repo-of-record copy AND the per-project scaffold copy bootstrap writes to scripts/ci/
# (U-05: the M3 run false-blocked on its own fresh scaffold because only the
# global-hooks path was excluded) — plus test fixtures/suites, which legitimately
# contain marker strings as test data. The exclusion is pinned to this one filename: a
# real marker planted anywhere else in scripts/ci/ still blocks.
EXCLUDE='(^|/)(tests/|.*\.pipeline/|(global-hooks|scripts/ci)/guard-source-markers\.sh)'

hits=""

# 1. Added lines in the tracked diff — restricted to non-excluded paths, so a marker
#    string that legitimately lives in tests/, .pipeline/, or this hook's own test data
#    doesn't false-block a deploy. This mirrors the EXCLUDE the untracked scan (2) already
#    applies; previously the tracked scan ran over the whole `git diff HEAD` unfiltered.
#    NUL-delimited end-to-end (name-only -z | grep -z | xargs -0) so odd filenames and the
#    NUL-stripping of $() capture can't corrupt the file list.
added="$(git diff "$DIFF_REF" --name-only -z 2>/dev/null | grep -zvE "$EXCLUDE" \
         | xargs -0 -r git diff "$DIFF_REF" -- 2>/dev/null | grep -E '^\+' | grep -vE '^\+\+\+' || true)"
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
