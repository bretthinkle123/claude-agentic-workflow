#!/usr/bin/env bash
# smoke-check.sh (suite) — U-04: the greenfield build-command matrix.
#
# The M3 defect: SMOKE_BUILD_CMD='python -c "import src.main"' (the exact form the
# bootstrap docs recommended) was expanded UNQUOTED by the hook and word-split into a
# SyntaxError, costing an implementation resume cycle. The hook now runs commands via
# `bash -c`, resolving the greenfield default into a variable first. This matrix
# proves every reasonable command shape works — including the old fatal one — and
# that failures still fail honestly with smoke-status recorded on every path.
#
# Python-dependent rows self-skip (recorded, not failed) on hosts without python.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../helpers/assert.sh"

SMOKE="$HOOKS/smoke-check.sh"
echo "-- smoke-check (U-04 greenfield matrix) --"

PY=""
command -v python  >/dev/null 2>&1 && PY=python
[ -z "$PY" ] && command -v python3 >/dev/null 2>&1 && PY=python3

# mk_greenfield — a git repo with NO commits (the greenfield branch trigger), a
# .pipeline/state.json (the hook's pipeline-project guard), and a stub src module.
mk_greenfield() {
  local w; w="$(mktemp -d)"; _WORKDIRS+=("$w")
  (
    cd "$w" && git init -q \
      && mkdir -p .pipeline src \
      && printf '{}' > .pipeline/state.json \
      && : > src/__init__.py && printf 'x = 1\n' > src/main.py
  ) >/dev/null 2>&1
  echo "$w"
}

# smoke_row <want-exit> <want-status> <desc> [smoke.env content]
smoke_row() {
  local want="$1" wantst="$2" desc="$3" env="${4:-}"
  local w; w="$(mk_greenfield)"
  [ -n "$env" ] && printf '%s\n' "$env" > "$w/.pipeline/smoke.env"
  ( cd "$w" && bash "$SMOKE" ) >/dev/null 2>&1
  local rc=$?
  local st; st="$(jq -r '.status // "missing"' "$w/.pipeline/smoke-status.json" 2>/dev/null)"
  assert_eq "$want/$wantst" "$rc/$st" "$desc"
}

if [ -n "$PY" ]; then
  # (a) The old fatal form — nested quotes inside the value. Must now WORK.
  smoke_row 0 pass "old fatal quoted form now passes (bash -c)" \
    "export SMOKE_BUILD_CMD='$PY -c \"import src.main\"'"
  # (b) The recommended module form.
  smoke_row 0 pass "module form passes" \
    "export SMOKE_BUILD_CMD=\"$PY -m src.main\""
  # (c) No smoke.env at all — the hook's greenfield default import check.
  if [ "$PY" = "python" ]; then
    smoke_row 0 pass "unset (default import check) passes" ""
  else
    _ok "default-cmd row skipped (host has python3 but not python — default targets python)"
  fi
  # (d) A genuinely failing build must still fail, honestly, with status recorded.
  smoke_row 2 fail "failing import fails honestly (exit 2 + status fail)" \
    "export SMOKE_BUILD_CMD='$PY -c \"import nope_missing_module\"'"
else
  _ok "python matrix skipped — no python/python3 on PATH (recorded, not failed)"
fi

# Static U-04 assertions (host-independent): the exec wrapper and the resolved default.
if grep -q 'bash -c "exec \$START_CMD"' "$SMOKE"; then
  _ok "start command runs via bash -c \"exec …\" (no orphaned server on trap kill)"
else
  _no "start command is not exec-wrapped — the EXIT trap would kill the wrapper and orphan the server"
fi
if grep -q 'BUILD_CMD="\${SMOKE_BUILD_CMD:-' "$SMOKE"; then
  _ok "greenfield default resolves into a variable before bash -c (no nested-default quoting)"
else
  _no "greenfield default is not pre-resolved — nesting \${VAR:-…} inside bash -c re-introduces the quoting bug"
fi

finish smoke-check
