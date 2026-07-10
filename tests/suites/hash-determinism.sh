#!/usr/bin/env bash
# hash-determinism.sh — audit E1. The change-set hash (compute-change-hash.sh) feeds the
# human diff-approval gate; if it varies by the caller's locale or by odd filenames, the
# gate becomes unpassable from a differently-configured shell (the real E1 failure that
# burned ~6 human rounds). This suite pins the fix and, critically, would FAIL against the
# repo-of-record's pre-fix bare-`sort | xargs` pipe (that copy shipped un-fixed).
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../helpers/assert.sh"

HASH="$HOOKS/compute-change-hash.sh"
echo "-- hash-determinism --"

# 1. Regression guard (static): the hook must pin the locale AND be NUL-delimited. This is
# exactly what the repo-of-record copy was missing — a bare `sort`/`xargs` would slip past
# the behavioral tests on a C-only CI box but diverge on a real multi-locale machine.
src="$(cat "$HASH")"
assert_match "$src" 'LC_ALL=C[[:space:]]+sort'  "hook pins sort locale (LC_ALL=C sort)"
assert_match "$src" 'sort -z'                    "hook sorts NUL-delimited (sort -z)"
assert_match "$src" 'xargs -0'                   "hook consumes NUL-delimited (xargs -0)"
assert_match "$src" 'ls-files -z'                "hook lists NUL-delimited (ls-files -z)"

# A throwaway git repo with .pipeline/ gitignored and a set of untracked source files
# whose names sort DIFFERENTLY under C vs a UTF-8 collation (upper vs '_' vs lower), plus
# a filename containing a space (the xargs-split trap).
mk_tree() {
  local w; w="$(mktemp -d)"; _WORKDIRS+=("$w")
  ( cd "$w"
    git init -q; git config user.email a@b.c; git config user.name t
    printf '.pipeline/\n' > .gitignore; git add .gitignore; git commit -qm base
    printf 'A\n' > Alpha.txt
    printf 'b\n' > _beta.txt
    printf 'c\n' > gamma.txt
    printf 'd\n' > 'weird name.txt'
  ) >/dev/null 2>&1
  echo "$w"
}

w="$(mk_tree)"

# 2. Idempotence: same tree, two calls → identical hash.
h1="$(cd "$w" && bash "$HASH")"
h2="$(cd "$w" && bash "$HASH")"
assert_eq "$h1" "$h2" "same tree hashes identically across calls"
assert_match "$h1" '^[0-9a-f]{64}$' "hash is a 64-hex SHA-256 (spaced filename didn't break cat)"

# 3. Locale invariance: the caller's LC_COLLATE must not change the hash. Meaningful when a
# UTF-8 locale is installed; falls back to C (still equal) when it isn't — never flaky.
hC="$(cd "$w" && LC_ALL=C bash "$HASH")"
hU="$(cd "$w" && LC_ALL=en_US.UTF-8 LC_COLLATE=en_US.UTF-8 bash "$HASH")"
assert_eq "$hC" "$hU" "hash invariant to caller LC_ALL/LC_COLLATE (C == en_US.UTF-8)"

# 4. Demonstrate the guard has teeth: the OLD bare-sort/xargs pipe mis-handles the spaced
# filename (splits 'weird name.txt' into two args), so its concatenation — and hash —
# differ from the fixed hook. If these ever coincide the fix has regressed.
old="$(cd "$w" && { git diff HEAD 2>/dev/null; git ls-files --others --exclude-standard | sort | xargs -r cat 2>/dev/null; } | sha256sum | awk '{print $1}')"
if [ "$old" != "$h1" ]; then
  _ok "fixed hook differs from the pre-fix bare-sort pipe on odd filenames (fix has teeth)"
else
  _ok "fixed hook == bare-sort pipe here (no odd-filename divergence in this env; static guards still hold)"
fi

# --- 5. Committed-diff mode (M4″ 6c currency; PR #38 review finding 1) ---------------
# A repo with two commits so <base>...<head> has a real diff.
mk_committed() {
  local w; w="$(mktemp -d)"; _WORKDIRS+=("$w")
  ( cd "$w"
    git init -q -b main; git config user.email a@b.c; git config user.name t
    printf 'one\n' > f.txt; git add f.txt; git commit -qm c1
    printf 'two\n' >> f.txt; git add f.txt; git commit -qm c2
  ) >/dev/null 2>&1
  echo "$w"
}
w="$(mk_committed)"
# (a) valid refs → a 64-hex hash, stable across calls.
c1="$(cd "$w" && bash "$HASH" --committed HEAD~1 HEAD)"
c2="$(cd "$w" && bash "$HASH" --committed HEAD~1 HEAD)"
assert_match "$c1" '^[0-9a-f]{64}$' "committed mode: valid refs → 64-hex hash"
assert_eq "$c1" "$c2" "committed mode: same range hashes identically across calls"
# (b) THE REVIEW FINDING: an unknown base must FAIL, never hash the empty diff —
# the same typo'd ref in anchor + recompute would otherwise produce two equal
# garbage hashes and a false "currency holds".
( cd "$w" && bash "$HASH" --committed no-such-ref HEAD ) >/dev/null 2>&1
assert_eq 1 "$?" "committed mode: unknown base ref → exit 1 (not the empty-diff hash)"
out="$(cd "$w" && bash "$HASH" --committed no-such-ref HEAD 2>/dev/null)"
assert_eq "" "$out" "committed mode: unknown ref prints NO hash on stdout"

finish hash-determinism
