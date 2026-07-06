#!/usr/bin/env bash
# ci-scan-base.sh — SCAN_BASE CI re-run mode (PR L, per-project CI job 6).
# The problem this mode solves: on a merge commit `git diff HEAD` is EMPTY and
# .pipeline/state.json is absent (gitignored), so a naive CI re-run of asvs-sast.sh /
# guard-source-markers.sh passes VACUOUSLY — the exact author's-claims failure PR L exists
# to close. SCAN_BASE=<ref> must (1) detect findings committed between base and HEAD,
# (2) fail CLOSED on an unresolvable ref, (3) keep added-lines-only semantics for markers
# (a marker being REMOVED must not block), and (4) leave local (no-SCAN_BASE) behavior
# untouched, including the state.json ambient no-op.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../helpers/assert.sh"

ASVS="$HOOKS/asvs-sast.sh"
MARKERS="$HOOKS/guard-source-markers.sh"
LOCK="$HOOKS/lockfile-check.sh"
echo "-- ci-scan-base (SCAN_BASE CI re-run mode) --"

# Build a CI-shaped repo: a clean base commit, then a second commit adding <file>=<content>.
# No .pipeline/state.json, clean tree — exactly what a CI checkout of a merge commit looks like.
ci_repo() {  # <file> <content> ; echoes the workdir; tags the base commit as refs/tags/base
  local w; w="$(mktemp -d)"; _WORKDIRS+=("$w")
  ( cd "$w"
    git init -q; git config user.email a@b.c; git config user.name t
    echo '# app' > README.md; git add -A; git commit -qm base; git tag base
    mkdir -p "$(dirname "$1")" 2>/dev/null
    printf '%s\n' "$2" > "$1"; git add -A; git commit -qm change ) >/dev/null 2>&1
  printf '%s' "$w"
}

# (1) asvs-sast: vacuous WITHOUT SCAN_BASE (no state.json → ambient no-op) — the bug being closed.
W="$(ci_repo app.py 'import jwt
jwt.decode(t, algorithms=["none"])')"
( cd "$W" && bash "$ASVS" ) >/dev/null 2>&1
assert_eq 0 $? "no SCAN_BASE + no state.json → ambient no-op (exit 0; the pre-L vacuous pass)"
assert_eq "" "$( [ -f "$W/.pipeline/asvs-sast.json" ] && echo written )" "…and writes nothing (local semantics untouched)"

# (2) asvs-sast CI mode: the committed JWT-none IS detected and the job fails (exit 2).
( cd "$W" && SCAN_BASE=base bash "$ASVS" ) >/dev/null 2>&1
assert_eq 2 $? "SCAN_BASE=base: committed JWT alg:none → exit 2 (CI job fails)"
assert_eq 1 "$(jq -r '.critical' "$W/.pipeline/asvs-sast.json" 2>/dev/null)" "…and the JSON records 1 critical"

# (3) asvs-sast CI mode: clean committed change → exit 0.
W2="$(ci_repo app.py 'def add(a, b):
    return a + b')"
( cd "$W2" && SCAN_BASE=base bash "$ASVS" ) >/dev/null 2>&1
assert_eq 0 $? "SCAN_BASE=base: clean committed change → exit 0"

# (4) asvs-sast: unresolvable SCAN_BASE fails CLOSED, never vacuous.
( cd "$W2" && SCAN_BASE=no-such-ref bash "$ASVS" ) >/dev/null 2>&1
assert_eq 2 $? "SCAN_BASE=<bad ref> → exit 2 (fail closed)"

# (5) guard-source-markers CI mode: a committed revert marker blocks…
W3="$(ci_repo src/pay.py '# TEMP-PREFIX-REVERT: original buggy path
def charge(): pass')"
( cd "$W3" && SCAN_BASE=base bash "$MARKERS" ) >/dev/null 2>&1
assert_eq 2 $? "SCAN_BASE=base: committed TEMP-PREFIX-REVERT → exit 2 (block)"
( cd "$W3" && bash "$MARKERS" ) >/dev/null 2>&1
assert_eq 0 $? "…but without SCAN_BASE (no state.json) → ambient no-op (the pre-L vacuous pass)"

# (6) added-lines-only preserved: a marker REMOVED between base and HEAD must NOT block.
W4="$(mktemp -d)"; _WORKDIRS+=("$W4")
( cd "$W4"
  git init -q; git config user.email a@b.c; git config user.name t
  printf '# DO-NOT-COMMIT scaffold\nx = 1\n' > src.py; git add -A; git commit -qm base; git tag base
  printf 'x = 1\n' > src.py; git add -A; git commit -qm 'remove marker' ) >/dev/null 2>&1
( cd "$W4" && SCAN_BASE=base bash "$MARKERS" ) >/dev/null 2>&1
assert_eq 0 $? "marker REMOVED between base and HEAD → exit 0 (added-lines-only preserved)"

# (7) guard-source-markers: unresolvable SCAN_BASE fails CLOSED.
( cd "$W4" && SCAN_BASE=no-such-ref bash "$MARKERS" ) >/dev/null 2>&1
assert_eq 2 $? "markers: SCAN_BASE=<bad ref> → exit 2 (fail closed)"

# (8) local mode regression: with state.json, working-tree behavior is unchanged.
W5="$(mktemp -d)"; _WORKDIRS+=("$W5")
( cd "$W5"
  git init -q; git config user.email a@b.c; git config user.name t
  printf '.pipeline/\n' > .gitignore; mkdir -p .pipeline; echo '{}' > .pipeline/state.json
  printf 'import jwt\njwt.decode(t, algorithms=["none"])\n' > app.py
  bash "$ASVS" ) >/dev/null 2>&1
assert_eq 1 "$(jq -r '.critical' "$W5/.pipeline/asvs-sast.json" 2>/dev/null)" "local mode (untracked file + state.json) still detects — unchanged"

# (9) lockfile-check CI mode: a committed NEW package.json with deps and NO lockfile → block.
W6="$(ci_repo package.json '{"name":"app","dependencies":{"express":"4.18.2"}}')"
( cd "$W6" && SCAN_BASE=base bash "$LOCK" ) >/dev/null 2>&1
assert_eq 2 $? "lockfile: SCAN_BASE=base, committed new package.json w/o lockfile → exit 2 (block)"
( cd "$W6" && bash "$LOCK" ) >/dev/null 2>&1
assert_eq 0 $? "…but without SCAN_BASE (no state.json) → ambient no-op (the pre-L vacuous pass)"

# (10) lockfile-check CI mode: manifest + lockfile committed together → clean.
W7="$(mktemp -d)"; _WORKDIRS+=("$W7")
( cd "$W7"
  git init -q; git config user.email a@b.c; git config user.name t
  echo '# app' > README.md; git add -A; git commit -qm base; git tag base
  printf '{"name":"app","dependencies":{"express":"4.18.2"}}\n' > package.json
  printf '{"lockfileVersion":3}\n' > package-lock.json
  git add -A; git commit -qm deps ) >/dev/null 2>&1
( cd "$W7" && SCAN_BASE=base bash "$LOCK" ) >/dev/null 2>&1
assert_eq 0 $? "lockfile: SCAN_BASE=base, manifest+lockfile committed together → exit 0"

# (11) lockfile-check: unresolvable SCAN_BASE fails CLOSED.
( cd "$W7" && SCAN_BASE=no-such-ref bash "$LOCK" ) >/dev/null 2>&1
assert_eq 2 $? "lockfile: SCAN_BASE=<bad ref> → exit 2 (fail closed)"

finish ci-scan-base
