#!/bin/bash
# check-doc-identifiers.sh — U-13: documentation identifiers must resolve in the tree.
#
# The documentation agent invented nonexistent API names in READMEs it was updating on
# TWO consecutive runs: run 2 wrote `create_or_replay_event` / `window_start_utc` (the
# real function is `floor_to_hour_utc`); run 3 wrote a wrong `get_usage_series` signature
# (real: keyword-only customer_id/metric/granularity) and a false "service validates"
# claim. Both are checkable by inspection: an identifier written into docs must exist in
# the tree, and a documented call signature must match the def site.
#
# Wired as a Stop hook on the documentation agent. WARN-FIRST (exit 0 + stderr report)
# for the first rollout so the heuristic extraction can be calibrated on real runs; flip
# WARN_ONLY=0 (or set DOC_IDENT_ENFORCE=1) to promote to a blocking exit 2 after M4.
# NEVER a deploy-gate conjunct — this is a documentation-stage quality signal, and
# heuristic identifier extraction is too brittle to block a deploy on.
#
# Scope: CHANGED markdown only (the same change-set scoping every other guard uses).
# Extracts backticked, project-symbol-shaped identifiers (snake_case / CamelCase,
# call-parenthesized or bare) and checks:
#   (1) EXISTENCE — the bare name appears as a definition or any occurrence in a
#       non-doc file (def/class/function/const, or simply used somewhere real);
#   (2) SIGNATURE — for `name(arg, ...)` where `name` resolves to a Python `def`, the
#       documented argument NAMES are a subset of the def site's parameter names
#       (catches run 3's get_usage_series(principal, params) vs (*, customer_id, ...)).
# An allowlist variable covers external/library names that legitimately won't resolve.
set -uo pipefail

WARN_ONLY=1
[ "${DOC_IDENT_ENFORCE:-0}" = "1" ] && WARN_ONLY=0

[ -f .pipeline/state.json ] || exit 0
command -v git >/dev/null 2>&1 || exit 0

# Allowlist: identifier names that need not resolve in-tree (framework/library/builtin
# symbols documented in prose). One variable — extend as real runs surface false hits.
ALLOW='^(fastapi|uvicorn|pydantic|BaseModel|sqlalchemy|alembic|redis|boto3|pytest|structlog|datetime|Decimal|Optional|List|Dict|str|int|bool|float|None|True|False|async|await|self|cls)$'

# --- gather changed markdown (tracked diff added lines + untracked .md) --------------
DIFF_REF="HEAD"
git rev-parse --verify -q HEAD >/dev/null 2>&1 || DIFF_REF=""

changed_md() {
  if [ -n "$DIFF_REF" ]; then
    git diff "$DIFF_REF" --name-only -z 2>/dev/null | tr '\0' '\n' | grep -E '\.md$' || true
  fi
  git ls-files -z --others --exclude-standard 2>/dev/null | tr '\0' '\n' | grep -E '\.md$' || true
}

mapfile -t MD_FILES < <(changed_md | sort -u)
[ "${#MD_FILES[@]}" -gt 0 ] || exit 0

# Search corpus for resolution: all non-markdown source, TRACKED + UNTRACKED. At
# documentation time (greenfield) nothing is committed yet, so `git grep` (tracked/staged
# only) misses everything — the plain recursive grep over the working tree is the one that
# actually resolves symbols. A documented symbol must exist in real source, not in a doc.
resolve_exists() {  # $1 = bare identifier → 0 if it occurs in any non-doc source file
  git grep -qwI "$1" -- ':!*.md' ':!.pipeline/' 2>/dev/null && return 0
  grep -RqwI --include='*.py' --include='*.js' --include='*.ts' --include='*.go' \
    --include='*.tsx' --include='*.jsx' --exclude-dir='.git' --exclude='*.md' "$1" . 2>/dev/null
}

# For a documented `name(args)`, if name resolves to a python `def`, check arg names.
# Returns non-empty (a reason string) on a mismatch, empty on OK/unknown. Searches
# tracked (git grep) then the working tree (grep) so an uncommitted def is still seen.
sig_mismatch() {  # $1 = name, $2 = comma-joined documented arg list
  local name="$1" doc_args="$2" defline params
  defline="$(git grep -hI -E "def[[:space:]]+$name[[:space:]]*\(" -- '*.py' 2>/dev/null | head -1)"
  [ -n "$defline" ] || defline="$(grep -RhI --include='*.py' --exclude-dir='.git' \
    -E "def[[:space:]]+$name[[:space:]]*\(" . 2>/dev/null | head -1)"
  [ -n "$defline" ] || return 0                       # not a python def we can see → skip
  params="$(printf '%s' "$defline" | sed -E 's/.*def[[:space:]]+'"$name"'[[:space:]]*\(([^)]*)\).*/\1/')"
  # Normalize def params to a set of bare names (strip *, **, defaults, type hints).
  local defset; defset=" $(printf '%s' "$params" | tr ',' '\n' \
    | sed -E 's/[*]+//g; s/:.*$//; s/=.*$//; s/[[:space:]]//g' | grep -v '^$' | tr '\n' ' ') "
  local a bad=""
  for a in $(printf '%s' "$doc_args" | tr ',' '\n' | sed -E 's/=.*$//; s/[[:space:]]//g' | grep -v '^$'); do
    case "$a" in ''|self|cls|\**) continue ;; esac
    case "$defset" in *" $a "*) : ;; *) bad="$bad $a" ;; esac
  done
  [ -n "$bad" ] && echo "documented arg(s)$bad not in def($name) params:$defset"
}

hits=""
for f in "${MD_FILES[@]}"; do
  [ -f "$f" ] || continue
  # Pull `backticked` tokens that look like project symbols: contain _ or are CamelCase,
  # optionally followed by an arg list. One per line: "name|args".
  while IFS= read -r tok; do
    name="${tok%%(*}"
    args=""; case "$tok" in *\(*\)*) args="${tok#*(}"; args="${args%)*}" ;; esac
    printf '%s' "$name" | grep -qE '^[A-Za-z_][A-Za-z0-9_]*$' || continue
    printf '%s' "$name" | grep -qE '_|[a-z][A-Z]' || continue   # snake_case or CamelCase only
    printf '%s' "$name" | grep -qE "$ALLOW" && continue
    if ! resolve_exists "$name"; then
      hits="$hits"$'\n'"  $f: \`$name\` — documented identifier not found in any source file"
      continue
    fi
    if [ -n "$args" ]; then
      reason="$(sig_mismatch "$name" "$args")"
      [ -n "$reason" ] && hits="$hits"$'\n'"  $f: \`$name(...)\` — $reason"
    fi
  done < <(grep -oE '`[A-Za-z_][A-Za-z0-9_]*(\([^`)]*\))?`' "$f" 2>/dev/null | tr -d '`')
done

if [ -n "$hits" ]; then
  echo "[check-doc-identifiers] Documentation names that don't resolve in the tree (U-13):" >&2
  printf '%s\n' "$hits" >&2
  echo "Copy identifiers from the tree, never from memory. Fix or remove the names above." >&2
  if [ "$WARN_ONLY" = "1" ]; then
    echo "(warn-only: not blocking this run — set DOC_IDENT_ENFORCE=1 to enforce after M4.)" >&2
    exit 0
  fi
  exit 2
fi
exit 0
