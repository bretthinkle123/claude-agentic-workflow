#!/usr/bin/env bash
# tree-hygiene.sh — U-08: the scanner/scratch-junk leak guard.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../helpers/assert.sh"

HOOK="$HOOKS/guard-tree-hygiene.sh"
echo "-- tree-hygiene (U-08) --"

# A throwaway git repo that IS a pipeline project (.pipeline/state.json present),
# with a .gitignore, so the hook's untracked-non-ignored scoping is exercised.
mk_proj() {
  local w; w="$(mktemp -d)"; _WORKDIRS+=("$w")
  (
    cd "$w" && git init -q \
      && git config user.email e@x && git config user.name x \
      && mkdir -p .pipeline src \
      && printf '{}' > .pipeline/state.json \
      && printf '.pipeline/\nreports/\n' > .gitignore \
      && printf 'x = 1\n' > src/main.py
  ) >/dev/null 2>&1
  echo "$w"
}

hyg_case() {
  local want="$1" desc="$2"; shift 2
  local w; w="$(mk_proj)"
  # remaining args: relpaths to create as untracked junk (dirs inferred from path)
  local p
  for p in "$@"; do mkdir -p "$w/$(dirname "$p")" 2>/dev/null; printf 'junk\n' > "$w/$p"; done
  ( cd "$w" && bash "$HOOK" ) >/dev/null 2>&1
  assert_eq "$want" "$?" "$desc"
}

hyg_case 0 "clean scaffold → pass"
hyg_case 2 "scratchpad/ dir in tree → block"                 "scratchpad/semgrep.json"
hyg_case 2 "scratch_ file in tree → block"                   "scratch_semgrep.json"
hyg_case 2 "top-level Users/ path (the M3 shape) → block"    "Users/brett/scratch/out.json"
hyg_case 2 "nested scratchpad → block"                       "src/scratchpad/x.json"
hyg_case 0 "gitignored reports/ → pass (deliberate, ignored)" "reports/mutation.json"
hyg_case 0 "ordinary source file → pass"                     "src/service.py"

# No-op outside a pipeline project (no state.json).
noproj="$(mktemp -d)"; _WORKDIRS+=("$noproj")
( cd "$noproj" && git init -q && mkdir scratchpad && : > scratchpad/x && bash "$HOOK" ) >/dev/null 2>&1
assert_eq 0 "$?" "no .pipeline/state.json → no-op (exit 0) even with junk present"

finish tree-hygiene
