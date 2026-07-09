#!/usr/bin/env bash
# doc-identifiers.sh — U-13: documentation names must resolve (and signatures match).
# Fixtures reproduce the run-2 + run-3 documentation-agent defects verbatim.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../helpers/assert.sh"

HOOK="$HOOKS/check-doc-identifiers.sh"
echo "-- doc-identifiers (U-13) --"

# A pipeline project with a real source file; the README (untracked = "changed") is
# supplied per case. Nothing committed — mirrors documentation-stage greenfield state.
mk_proj() {
  local w; w="$(mktemp -d)"; _WORKDIRS+=("$w")
  (
    cd "$w" && git init -q && mkdir -p .pipeline src \
      && printf '{}' > .pipeline/state.json \
      && cat > src/dashboard_service.py <<'PY'
async def get_usage_series(*, customer_id, metric, granularity):
    return {}
def floor_to_hour_utc(ts):
    return ts
PY
  ) >/dev/null 2>&1
  echo "$w"
}

# doc_case <enforce-exit> <desc> <readme-content>
doc_case() {
  local want="$1" desc="$2" body="$3"
  local w; w="$(mk_proj)"
  printf '%s\n' "$body" > "$w/src/README.md"
  ( cd "$w" && DOC_IDENT_ENFORCE=1 bash "$HOOK" ) >/dev/null 2>&1
  assert_eq "$want" "$?" "$desc"
}

# Real symbol, correct → pass.
doc_case 0 "real function name resolves → pass" \
  'Floors via `floor_to_hour_utc` in dashboard_service.py.'
# Run-2 invented names → block.
doc_case 2 "run-2 invented \`window_start_utc\` → block" \
  'Floors via `window_start_utc(ts)`.'
doc_case 2 "run-2 invented \`create_or_replay_event\` → block" \
  'The repo exposes `create_or_replay_event`.'
# Run-3 wrong signature on a REAL name → block (arg-name mismatch).
doc_case 2 "run-3 wrong signature \`get_usage_series(principal, params)\` → block" \
  'Service `get_usage_series(principal, params)` assembles the series.'
# Run-3 CORRECT signature on the real name → pass.
doc_case 0 "correct signature \`get_usage_series(customer_id, metric, granularity)\` → pass" \
  'Service `get_usage_series(customer_id, metric, granularity)`.'
# Allowlisted framework name that won't resolve → pass (no false positive).
doc_case 0 "allowlisted external name \`fastapi\` → pass" \
  'Built on `fastapi` and `pydantic`.'
# Prose without project-symbol shape (no _ / not CamelCase) → ignored.
doc_case 0 "plain backticked word \`status\` → ignored (not symbol-shaped)" \
  'Returns a `status` field.'

# Warn-only (default, no DOC_IDENT_ENFORCE) must NOT block even on a bad name.
wo="$(mk_proj)"; printf 'Uses `window_start_utc`.\n' > "$wo/src/README.md"
( cd "$wo" && bash "$HOOK" ) >/dev/null 2>&1
assert_eq 0 "$?" "warn-only default: invented name reports but does not block (exit 0)"

# No-op outside a pipeline project.
np="$(mktemp -d)"; _WORKDIRS+=("$np")
( cd "$np" && git init -q && printf 'Uses `made_up_name`.\n' > x.md && DOC_IDENT_ENFORCE=1 bash "$HOOK" ) >/dev/null 2>&1
assert_eq 0 "$?" "no .pipeline/state.json → no-op even in enforce mode"

# F-M4′-6a: MULTI-LINE def signature — correct documented args must NOT false-positive
# (M4′: the single-line grep mangled the def into params "asyncdefcount_…" and flagged
# every real caller).
ml="$(mk_proj)"
cat >> "$ml/src/dashboard_service.py" <<'PY'
async def count_usage_rollups(
    api_key_id,
    metric,
):
    return 0
PY
printf 'Counts via `count_usage_rollups(api_key_id, metric)`.\n' > "$ml/src/README.md"
( cd "$ml" && DOC_IDENT_ENFORCE=1 bash "$HOOK" ) >/dev/null 2>&1
assert_eq 0 "$?" "F-M4′-6a: multi-line def signature, correct args → pass (no mangled-params FP)"

# F-M4′-6b: docs/decisions/ design-record copies are excluded from the sweep.
dd="$(mk_proj)"
mkdir -p "$dd/docs/decisions/feature/x"
printf 'Frontmatter key `repomix_pack_sha256` and invented `made_up_fn(a, b)`.\n' \
  > "$dd/docs/decisions/feature/x/plan.md"
( cd "$dd" && DOC_IDENT_ENFORCE=1 bash "$HOOK" ) >/dev/null 2>&1
assert_eq 0 "$?" "F-M4′-6b: docs/decisions/ design-record copies excluded (no FP)"

# F-M4′-6c: YAML frontmatter keys are not documented identifiers.
fm="$(mk_proj)"
printf -- '---\nrepomix_pack_sha256: abc\nmigration_added: false\n---\nBody uses `floor_to_hour_utc`.\n' \
  > "$fm/src/README.md"
( cd "$fm" && DOC_IDENT_ENFORCE=1 bash "$HOOK" ) >/dev/null 2>&1
assert_eq 0 "$?" "F-M4′-6c: frontmatter keys skipped; real body identifier passes"

finish doc-identifiers
