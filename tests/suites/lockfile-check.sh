#!/usr/bin/env bash
# lockfile-check.sh — supply-chain integrity (M6): manifest-without-lockfile blocks
# (exit 2), unpinned deps / bare re-lock warn (exit 1), in-sync is clean (exit 0).
# Needs a real git repo so the change-set scoping (git diff HEAD + untracked) works.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../helpers/assert.sh"

LC="$HOOKS/lockfile-check.sh"
echo "-- lockfile-check (M6 supply-chain) --"

command -v git >/dev/null 2>&1 || { _no "git not on PATH — cannot run lockfile-check suite"; finish lockfile-check; }

# A committed-baseline git repo with a .pipeline/ guard; add files to form the change set.
lc_work() {
  local w; w="$(mktemp -d)"; _WORKDIRS+=("$w")
  ( cd "$w"
    git init -q; git config user.email t@local; git config user.name t
    printf '.pipeline/\n' > .gitignore; git add .gitignore; git commit -qm baseline
    mkdir -p .pipeline; echo '{}' > .pipeline/state.json
  ) >/dev/null 2>&1
  echo "$w"
}
run_lc() { ( cd "$1" && bash "$LC" ) >/dev/null 2>&1; echo $?; }

# 1. clean: empty change set
w="$(lc_work)"
assert_eq 0 "$(run_lc "$w")" "empty change set → clean (0)"

# 2. BLOCK: package.json changed, no lockfile
w="$(lc_work)"; printf '{"dependencies":{"left-pad":"1.3.0"}}\n' > "$w/package.json"
assert_eq 2 "$(run_lc "$w")" "package.json without lockfile → block (2)"

# 3. clean: package.json + lockfile together, pinned
w="$(lc_work)"
printf '{"dependencies":{"left-pad":"1.3.0"}}\n' > "$w/package.json"
printf '{"lockfileVersion":3}\n' > "$w/package-lock.json"
assert_eq 0 "$(run_lc "$w")" "package.json + lockfile, pinned → clean (0)"

# 4. WARN: package.json + lockfile but a floating specifier
w="$(lc_work)"
printf '{"dependencies":{"left-pad":"^1.3.0"}}\n' > "$w/package.json"
printf '{"lockfileVersion":3}\n' > "$w/package-lock.json"
assert_eq 1 "$(run_lc "$w")" "floating '^' specifier → warn (1)"

# 5. BLOCK: pyproject.toml without poetry.lock
w="$(lc_work)"; printf '[project]\ndependencies=["requests"]\n' > "$w/pyproject.toml"
assert_eq 2 "$(run_lc "$w")" "pyproject.toml without poetry.lock → block (2)"

# 6. WARN: unpinned requirements.txt
w="$(lc_work)"; printf 'requests>=2.0\nflask\n' > "$w/requirements.txt"
assert_eq 1 "$(run_lc "$w")" "unpinned requirements.txt → warn (1)"

# 7. clean: fully pinned requirements.txt
w="$(lc_work)"; printf 'requests==2.31.0\nflask==3.0.0\n' > "$w/requirements.txt"
assert_eq 0 "$(run_lc "$w")" "pinned requirements.txt → clean (0)"

# 8. WARN: lockfile changed with no manifest (bare re-lock)
w="$(lc_work)"; printf '{"lockfileVersion":3}\n' > "$w/package-lock.json"
assert_eq 1 "$(run_lc "$w")" "lockfile-only change → warn (1)"

# 9. no-op outside a pipeline project
w="$(mktemp -d)"; _WORKDIRS+=("$w")
( cd "$w" && git init -q && git config user.email t@local && git config user.name t && printf '{"dependencies":{"x":"^1"}}\n' > package.json ) >/dev/null 2>&1
assert_eq 0 "$(run_lc "$w")" "outside a pipeline project → no-op (0)"

finish lockfile-check
