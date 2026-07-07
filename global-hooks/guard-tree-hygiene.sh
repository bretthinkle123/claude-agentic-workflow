#!/bin/bash
# guard-tree-hygiene.sh — U-08: deterministic block on scanner/scratch junk leaking
# into the repo tree.
#
# The M3 run had the security agent write raw scanner output into a directory under
# the repo root (a scratchpad path that nearly got committed; the debugging agent
# removed it). A prose rule already existed in security.md ("tool output goes to the
# scratchpad, never the repo tree") and was violated anyway — prose alone doesn't
# hold. This makes the signal deterministic, the same two-layer pattern that made
# source markers reliable: wired as a Stop hook on the security + debugging agents,
# exit 2 feeds the offending paths back to the model before it can stop.
#
# Scope: UNTRACKED files only (the change set the rest of the pipeline scopes to,
# minus tracked files — a junk dir is always untracked). Patterns match the CLASS of
# leak, not one artifact name: the exact M3 directory was deleted before preservation
# and NTFS forbids ':' in filenames, so "C:" was never a literal path — pattern for
# the shape (scratchpad/scratch_/reports/, a top-level Users/ tree) and keep the
# patterns in one variable so a future observed leak name is a one-line addition.
#
# Exit: 0 = clean (or not a pipeline project) · 2 = junk found (BLOCK).
set -uo pipefail

# Pipeline-project guard: no-op outside a bootstrapped pipeline project.
[ -f .pipeline/state.json ] || exit 0

command -v git >/dev/null 2>&1 || exit 0

# Junk-path shapes (anchored, case-sensitive on the segment). One variable so adding a
# newly-observed leak name is a single edit. Deliberately NARROW — only shapes that are
# unambiguously tool/scratch output, never legitimate source:
#   scratchpad/         a scratch dir committed into the tree
#   scratch_<x>         audit E4 scratch files
#   reports/            tool report dumps (Stryker/scan) when not gitignored
#   ^Users/ , ^[A-Za-z]:/  a home/drive-rooted path materialized as a repo dir
#     (the M3 shape — an absolute scratchpad path created relative to the repo root)
JUNK='(^|/)scratchpad(/|$)|(^|/)scratch_|(^|/)reports/|^Users/|^[A-Za-z]:/'

# Untracked, non-gitignored files (respects .gitignore, so a project that deliberately
# gitignores reports/ is never flagged — that dir won't appear here).
mapfile -t offenders < <(git ls-files -z --others --exclude-standard 2>/dev/null \
  | tr '\0' '\n' | grep -nE "$JUNK" 2>/dev/null | cut -d: -f2-)

if [ "${#offenders[@]}" -gt 0 ]; then
  echo "Blocked: scanner/scratch output leaked into the repo tree (audit E4 / U-08). Raw" >&2
  echo "tool output belongs in the session scratchpad or .pipeline/, never as tracked-tree" >&2
  echo "junk. Remove these untracked paths (or gitignore them if intentional) and re-run:" >&2
  printf '  %s\n' "${offenders[@]}" >&2
  exit 2
fi
exit 0
