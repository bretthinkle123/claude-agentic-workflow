#!/usr/bin/env bash
# Shared assertion helpers for the pipeline eval harness. Sourced by every suite.
# Zero-dependency (bash + jq). Suites use `set -uo pipefail` (NOT -e — assertions
# routinely run hooks that exit non-zero on purpose).
#
# Paths are resolved from THIS file's location, so suites can `cd` into throwaway
# workdirs freely and still reach the repo's hooks/fixtures by absolute path.

HELPERS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HELPERS_DIR/../.." && pwd)"
HOOKS="$REPO_ROOT/global-hooks"
# Fixture is stored as `pipeline/` (no dot) so the repo's `.pipeline/` gitignore does
# not swallow it; mk_fixture copies it INTO a real `.pipeline/` in the throwaway workdir.
FIXTURE="$REPO_ROOT/tests/fixtures/linkly-green/pipeline"
LOOP_EXIT_PREDICATE="$HELPERS_DIR/loop-exit-predicate.jq"

command -v jq >/dev/null 2>&1 || { echo "eval-harness: jq is required on PATH." >&2; exit 2; }

_PASS=0
_FAIL=0
_WORKDIRS=()

# Clean up every fixture workdir when the suite process exits.
_cleanup() { local d; for d in "${_WORKDIRS[@]:-}"; do [ -n "$d" ] && rm -rf "$d"; done; }
trap _cleanup EXIT

_ok() { _PASS=$((_PASS + 1)); [ -n "${VERBOSE:-}" ] && echo "  PASS  $1"; return 0; }
_no() { _FAIL=$((_FAIL + 1)); echo "  FAIL  $1"; return 0; }

# mk_fixture — copy the golden green .pipeline snapshot into a fresh temp workdir
# (outside any git repo, so the gate's currency check self-skips). Echoes the dir.
mk_fixture() {
  local w; w="$(mktemp -d)"
  mkdir -p "$w/.pipeline"
  cp "$FIXTURE"/* "$w/.pipeline/"
  _WORKDIRS+=("$w")
  echo "$w"
}

# mk_git_fixture — a real (throwaway) git repo with the green .pipeline snapshot and a
# **dirty** working tree (an untracked source file = "the change under review"), so the
# gate's dirty-tree path actually runs — the only way to exercise the diff-approval /
# currency checks (in a non-git dir they self-skip). `.pipeline/` is gitignored like a
# real bootstrapped project, so the change-set hash is over the source file, not state.
mk_git_fixture() {
  local w; w="$(mktemp -d)"; _WORKDIRS+=("$w")
  (
    cd "$w"
    git init -q
    git config user.email pipeline-eval@local && git config user.name pipeline-eval
    printf '.pipeline/\n' > .gitignore
    git add .gitignore && git commit -qm baseline
    mkdir -p .pipeline && cp "$FIXTURE"/* .pipeline/
    printf 'def handler():\n    return "ok"\n' > app.py   # the reviewed change (untracked ⇒ tree dirty)
  ) >/dev/null 2>&1
  echo "$w"
}

# change_hash <workdir> — the shared change-set hash for a workdir, as both the gate
# and approve-diff.sh compute it.
change_hash() { ( cd "$1" && bash "$HOOKS/compute-change-hash.sh" ); }

# jq_edit <file> '<filter>' — apply a jq filter to a JSON file IN PLACE. The temp lands
# beside the file (inside the caller's throwaway workdir, so cleanup covers it — no
# TMPDIR residue), replacing the repeated `mktemp; jq > t && mv` mutation boilerplate.
jq_edit() {
  local f="$1"; local t="$1.tmp"
  jq "$2" "$f" > "$t" && mv "$t" "$f"
}

# assert_exit <want-code> "<desc>" <cmd...>
assert_exit() {
  local want="$1" desc="$2"; shift 2
  "$@" >/dev/null 2>&1; local got=$?
  if [ "$got" -eq "$want" ]; then _ok "$desc (exit $got)"; else _no "$desc (want exit $want, got $got)"; fi
}

# assert_eq <want> <got> "<desc>"
assert_eq() {
  if [ "$1" = "$2" ]; then _ok "$3"; else _no "$3 (want '$1', got '$2')"; fi
}

# assert_json <file> '<jq-filter>' <want> "<desc>"
assert_json() {
  local got; got="$(jq -r "$2" "$1" 2>/dev/null)"
  assert_eq "$3" "$got" "$4"
}

# assert_match <string> '<ERE>' "<desc>"
assert_match() {
  if printf '%s' "$1" | grep -qE "$2"; then _ok "$3"; else _no "$3 (value '$1' !~ /$2/)"; fi
}

# finish "<suite-name>" — print footer, exit 0 iff no failures.
finish() {
  if [ "$_FAIL" -eq 0 ]; then
    echo "[$1] OK — $_PASS passed"
    exit 0
  fi
  echo "[$1] FAIL — $_FAIL failed / $((_PASS + _FAIL)) total"
  exit 1
}
