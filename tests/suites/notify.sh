#!/usr/bin/env bash
# notify.sh — notify-checkpoint.sh must never wedge or fail the caller (its own contract).
# Regression for the 2026-07-11 live finding: an unbounded stdin drain (`cat >/dev/null`)
# blocked forever when the caller handed the hook an open pipe that never EOFs.
# Hermetic: clean HOME (no notify.env), PATH-stubbed powershell.exe that fails, so the
# hook falls through ntfy -> toast to the log backend deterministically, no popups.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../helpers/assert.sh"

HOOK="$REPO_ROOT/global-hooks/notify-checkpoint.sh"
echo "-- notify (checkpoint notification hook) --"

assert_exit 0 "notify-checkpoint parses" bash -n "$HOOK"

WORK="$(mktemp -d)"
mkdir -p "$WORK/bin" "$WORK/repo/.pipeline"
printf '#!/bin/sh\nexit 1\n' > "$WORK/bin/powershell.exe"
chmod +x "$WORK/bin/powershell.exe"

run_hook() { # args: <stdin-redirect-cmd...>
  (cd "$WORK/repo" && HOME="$WORK" PATH="$WORK/bin:$PATH" "$@")
}

# --- open-pipe stdin must not hang (bounded drain; 124 = timed out = regression) ----------
# Process substitution (not `sleep | hook`): the shell would wait for the whole pipeline,
# so a plain pipe measures the sleep, not the hook. bash does not wait on <(...) writers.
run_hook timeout 8 bash -c "bash '$HOOK' plan pipe-test < <(sleep 15)"; rc=$?
assert_eq 0 "$rc" "hook returns promptly (exit 0) with a never-EOF pipe on stdin"

# --- /dev/null stdin: exits 0 and logs via the fallback chain ------------------------------
run_hook bash "$HOOK" diff devnull-test </dev/null; rc=$?
assert_eq 0 "$rc" "hook exits 0 with /dev/null stdin"
log="$WORK/repo/.pipeline/notify-log.jsonl"
assert_exit 0 "notify log line is valid JSON" bash -c "tail -1 '$log' | jq -e . >/dev/null"
assert_eq "none" "$(tail -1 "$log" | jq -r .via)" "no backend available -> via none (silent degrade)"
assert_eq "diff" "$(tail -1 "$log" | jq -r .event)" "event kind recorded"
assert_match "$(tail -1 "$log" | jq -r .msg)" 'devnull-test' "slug recorded in payload"

rm -rf "$WORK"
finish notify
