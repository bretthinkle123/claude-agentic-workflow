#!/usr/bin/env bash
# sandbox.sh — proves the intrusion-tier tooling behaves safely (autonomy plan Phases 5/6):
#   verify-sandbox.sh must FAIL SAFE (never bless an un-hardened environment), and
#   bridge-log.sh must translate tinyproxy decisions into the egress-check.sh JSON schema.
# Deterministic + hermetic: controls HOME/HTTPS_PROXY so it does not depend on ambient state.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../helpers/assert.sh"

VS="$REPO_ROOT/scripts/verify-sandbox.sh"
BRIDGE="$REPO_ROOT/global-hooks/egress-proxy/bridge-log.sh"
SETUP="$REPO_ROOT/scripts/setup-wsl-pipeline.sh"
echo "-- sandbox (intrusion-tier tooling) --"

assert_exit 0 "verify-sandbox parses"   bash -n "$VS"
assert_exit 0 "setup-wsl-pipeline parses" bash -n "$SETUP"
assert_exit 0 "bridge-log parses"       bash -n "$BRIDGE"

# --- verify-sandbox FAIL-SAFE: with no proxy + a clean HOME it must still refuse ----------
# (clean HOME isolates the creds check; unset HTTPS_PROXY forces the proxy check to fail —
# so this asserts the safety-critical direction deterministically, on Windows AND CI Linux.)
CLEAN="$(mktemp -d)"
out="$(HOME="$CLEAN" HTTPS_PROXY="" bash "$VS" 2>&1)"; rc=$?
assert_eq 1 "$rc" "verify-sandbox exits nonzero when un-hardened (fail-safe)"
assert_match "$out" 'HTTPS_PROXY not set'   "verify-sandbox names the missing egress proxy"
assert_match "$out" 'SANDBOX INCOMPLETE'    "verify-sandbox reports INCOMPLETE, never a false OK"
rm -rf "$CLEAN"

# --- verify-sandbox must NOT contain a path that prints OK without checking the proxy -----
# (guards against a future edit that drops the required proxy conjunct.)
assert_match "$(grep -c 'HTTPS_PROXY' "$VS")" '^[1-9]' "verify-sandbox still checks HTTPS_PROXY"

# --- verify-sandbox FALSE-OK regression (found live 2026-07-10): HTTPS_PROXY set but the ---
# proxy UNREACHABLE made every curl fail, and "deny-probe failed" was read as "enforcing".
# An unreachable proxy must FAIL the allowlisted-host conjunct, never bless the environment.
CLEAN="$(mktemp -d)"
out="$(HOME="$CLEAN" HTTPS_PROXY="http://127.0.0.1:9" HTTP_PROXY="http://127.0.0.1:9" bash "$VS" 2>&1)"; rc=$?
assert_eq 1 "$rc" "verify-sandbox exits nonzero when the proxy is unreachable (no false OK)"
assert_match "$out" 'cannot prove enforcement' "unreachable proxy fails the allowlisted-host conjunct"
assert_match "$out" 'SANDBOX INCOMPLETE'       "unreachable proxy reports INCOMPLETE"
rm -rf "$CLEAN"

# --- check-run-host (CN2-3): the run-location tell -----------------------------------------
RH="$REPO_ROOT/global-hooks/check-run-host.sh"
assert_exit 0 "check-run-host parses" bash -n "$RH"
bash "$RH" /mnt/c/Users/someone/repo >/dev/null 2>&1; assert_eq 3 "$?" "CN2-3: /mnt/* path → exit 3 (Windows FS via WSL)"
bash "$RH" /home/u/OneDrive/repo >/dev/null 2>&1;    assert_eq 3 "$?" "CN2-3: OneDrive path → exit 3 (sync-quarantine hazard)"
out="$(bash "$RH" /mnt/c/x 2>&1)"; assert_match "$out" 'OneDrive may sync|WINDOWS filesystem' "CN2-3: the warning names the hazard"

# --- bridge-log: tinyproxy log -> {"ts","host","action"} JSON ----------------------------
mk() { printf '%s\n' "$@" | bash "$BRIDGE" /dev/stdout; }
deny_line='CONNECT Jan 01 00:00:00 [1]: Filtered connection to evil.example:443'
allow_line='CONNECT Jan 01 00:00:01 [2]: Established connection to registry.npmjs.org:443'
noise_line='INFO    Jan 01 00:00:02 [3]: accepting connection'

TMP="$(mktemp)"; mk "$deny_line" "$allow_line" "$noise_line" > "$TMP"
assert_eq 2 "$(wc -l < "$TMP" | tr -d ' ')" "bridge emits one line per decision, skips noise"
assert_exit 0 "bridge output is valid JSON" bash -c "jq -e . '$TMP' >/dev/null"
assert_eq "deny"  "$(sed -n 1p "$TMP" | jq -r .action)" "Filtered -> deny"
assert_eq "evil.example" "$(sed -n 1p "$TMP" | jq -r .host)" "deny row carries the blocked host"
assert_eq "allow" "$(sed -n 2p "$TMP" | jq -r .action)" "Established -> allow"
assert_eq "registry.npmjs.org" "$(sed -n 2p "$TMP" | jq -r .host)" "allow row carries the host"
rm -f "$TMP"

finish sandbox
