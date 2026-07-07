#!/usr/bin/env bash
# bootstrap-integration.sh — U-11: the cross-change interaction net.
#
# Both engine regressions in the week before the M3 audit were interactions between
# individually-green PRs (new scaffold copies + step names tripping an existing guard;
# a new criterion class breaking existing gate arithmetic). Per-entry suites can't see
# that class. This suite runs the WHOLE first-contact path a fresh project experiences:
#   install-global.sh → sandbox ~/.claude → bootstrap-project.sh → fresh scaffold →
#   the ambient hooks that fire on it.
# Any future PR whose template/hook combination self-breaks a fresh project fails HERE,
# in engine CI, instead of on the next real feature run.
#
# Born red (by design): at introduction this suite FAILS against the pre-U-05
# templates — the scaffold's own guard-source-markers.sh prose and the pipeline-ci.yml
# step name trip the marker guard. U-05 (same PR) turns it green; the red→green pair
# is the fails-before/passes-after proof.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../helpers/assert.sh"

echo "-- bootstrap-integration --"

FAKE_HOME="$(mktemp -d)"; _WORKDIRS+=("$FAKE_HOME")
PROJ="$(mktemp -d)";      _WORKDIRS+=("$PROJ")

# --- 1. Publish the CURRENT repo into a sandbox HOME (install round-trip) ----------
if HOME="$FAKE_HOME" bash "$REPO_ROOT/scripts/install-global.sh" >/dev/null 2>&1; then
  _ok "install-global.sh publishes cleanly into a sandbox HOME"
else
  _no "install-global.sh failed against a sandbox HOME"
fi
GHOOKS="$FAKE_HOME/.claude/hooks"

# --- 2. Bootstrap a fresh project from the installed templates ---------------------
(
  cd "$PROJ" && git init -q \
    && git config user.email pipeline-eval@local && git config user.name pipeline-eval \
    && HOME="$FAKE_HOME" bash "$FAKE_HOME/.claude/pipeline-templates/bootstrap-project.sh"
) >/dev/null 2>&1
assert_eq 0 "$?" "bootstrap-project.sh exits 0 on a fresh git repo"

for f in .pipeline/state.json .claude/settings.json CLAUDE.md PROJECT.md .gitattributes \
         .github/workflows/pipeline-ci.yml scripts/ci/guard-source-markers.sh; do
  if [ -f "$PROJ/$f" ]; then _ok "scaffold contains $f"; else _no "scaffold missing $f"; fi
done

# --- 3. U-05: the ambient marker guard must be CLEAN on the untouched scaffold -----
# Everything bootstrap wrote is untracked, exactly what the guard scans. A guard that
# blocks its own scaffold cost the M3 run an improvised rewording.
( cd "$PROJ" && bash "$GHOOKS/guard-source-markers.sh" ) >/dev/null 2>&1
assert_eq 0 "$?" "guard-source-markers is clean on a fresh scaffold (U-05)"

# --- 4. ...and its teeth are intact: a planted marker still blocks -----------------
mkdir -p "$PROJ/src"
printf '# TEMP-REVERT: planted repro, must never ship\n' > "$PROJ/src/planted.py"
( cd "$PROJ" && bash "$GHOOKS/guard-source-markers.sh" ) >/dev/null 2>&1
assert_eq 2 "$?" "planted marker in scaffold src/ still blocks (guard teeth intact)"
rm -f "$PROJ/src/planted.py"

# --- 5. Telemetry hook fires on the scaffold ---------------------------------------
( cd "$PROJ" && HOME="$FAKE_HOME" bash "$GHOOKS/log-run.sh" planning ) >/dev/null 2>&1
if [ -f "$PROJ/.pipeline/run-log.jsonl" ] \
   && [ "$(jq -r '.stage' "$PROJ/.pipeline/run-log.jsonl" 2>/dev/null | head -1)" = "planning" ]; then
  _ok "log-run.sh appends a planning line on the fresh scaffold"
else
  _no "log-run.sh did not log on the fresh scaffold"
fi

# --- 6. Greenfield smoke path (best-effort: needs a python on PATH) ----------------
if command -v python >/dev/null 2>&1 || command -v python3 >/dev/null 2>&1; then
  mkdir -p "$PROJ/src" && : > "$PROJ/src/__init__.py" && printf 'x = 1\n' > "$PROJ/src/main.py"
  ( cd "$PROJ" && bash "$GHOOKS/smoke-check.sh" ) >/dev/null 2>&1
  rc=$?
  st="$(jq -r '.status // "missing"' "$PROJ/.pipeline/smoke-status.json" 2>/dev/null)"
  if [ "$rc" -eq 0 ] && [ "$st" = "pass" ]; then
    _ok "greenfield smoke-check passes on a stub module and records smoke-status"
  else
    _no "greenfield smoke-check failed on a stub module (rc=$rc status=$st)"
  fi
else
  _ok "greenfield smoke skipped — no python on PATH (recorded, not failed)"
fi

# --- 7. tree-hygiene guard (U-08), once it exists: clean scaffold must pass --------
if [ -f "$GHOOKS/guard-tree-hygiene.sh" ]; then
  ( cd "$PROJ" && bash "$GHOOKS/guard-tree-hygiene.sh" ) >/dev/null 2>&1
  assert_eq 0 "$?" "guard-tree-hygiene is clean on a fresh scaffold"
fi

finish bootstrap-integration
