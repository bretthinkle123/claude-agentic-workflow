#!/usr/bin/env bash
# stamp-ran-at.sh — deterministic ran_at enforcement (F6): placeholder → real UTC on
# both stage artifacts; no-op on missing artifact / unknown stage / outside project;
# malformed JSON left unchanged.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../helpers/assert.sh"

SR="$HOOKS/stamp-ran-at.sh"
UTC_RE='^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$'
PLACEHOLDER='2026-06-30T00:00:00Z'
echo "-- stamp-ran-at --"

# The golden fixture keeps the real F6 placeholder ran_at on both artifacts.
w="$(mk_fixture)"
assert_json "$w/.pipeline/test-results.json"  '.ran_at' "$PLACEHOLDER" "fixture starts with placeholder (testing)"
assert_json "$w/.pipeline/security-status.json" '.ran_at' "$PLACEHOLDER" "fixture starts with placeholder (security)"

( cd "$w" && bash "$SR" testing ) >/dev/null 2>&1
assert_eq 0 "$?" "stamp testing → exit 0"
tr="$(jq -r '.ran_at' "$w/.pipeline/test-results.json")"
assert_match "$tr" "$UTC_RE" "testing ran_at is real UTC"
[ "$tr" != "$PLACEHOLDER" ] && _ok "testing ran_at replaced" || _no "testing ran_at still placeholder"
# other fields intact
assert_json "$w/.pipeline/test-results.json" '.status' pass "testing: status field intact"
assert_json "$w/.pipeline/test-results.json" '.perf.budget.throughput_rps' 100 "testing: perf field intact"

( cd "$w" && bash "$SR" security ) >/dev/null 2>&1
sr="$(jq -r '.ran_at' "$w/.pipeline/security-status.json")"
assert_match "$sr" "$UTC_RE" "security ran_at is real UTC"
assert_json "$w/.pipeline/security-status.json" '.status' clean "security: status field intact"

# no-op: missing artifact
w="$(mk_fixture)"; rm -f "$w/.pipeline/test-results.json"
( cd "$w" && bash "$SR" testing ) >/dev/null 2>&1; assert_eq 0 "$?" "missing artifact → no-op exit 0"

# no-op: unknown stage
( cd "$w" && bash "$SR" bogus ) >/dev/null 2>&1; assert_eq 0 "$?" "unknown stage → exit 0"

# no-op: outside a pipeline project (no state.json)
w="$(mktemp -d)"; _WORKDIRS+=("$w"); mkdir -p "$w/.pipeline"; echo '{"status":"pass"}' > "$w/.pipeline/test-results.json"
( cd "$w" && bash "$SR" testing ) >/dev/null 2>&1; assert_eq 0 "$?" "outside project → no-op exit 0"
assert_json "$w/.pipeline/test-results.json" '.status' pass "outside project → artifact untouched"

# malformed JSON: left unchanged, exit 1 (non-blocking)
w="$(mktemp -d)"; _WORKDIRS+=("$w"); mkdir -p "$w/.pipeline"; echo '{ not json' > "$w/.pipeline/test-results.json"; echo '{}' > "$w/.pipeline/state.json"
( cd "$w" && bash "$SR" testing ) >/dev/null 2>&1; assert_eq 1 "$?" "malformed JSON → exit 1 (non-blocking)"
assert_eq '{ not json' "$(cat "$w/.pipeline/test-results.json")" "malformed JSON → left unchanged"

finish stamp-ran-at
