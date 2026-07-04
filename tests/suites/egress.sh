#!/usr/bin/env bash
# egress.sh — the deterministic slices of the default-deny egress control (EG side-track).
#  (1) DETECTION — egress-check.sh flags denied outbound hosts from the proxy log, and is a
#      silent no-op when no proxy log is present (the un-provisioned / backward-compatible state).
#  (2) FILTER — build-filter.sh derives the tinyproxy ACL from egress-allowlist.txt (single source
#      of truth), emitting an anchored host-or-subdomain regex per allowed host.
# The Layer-2 proxy itself is Docker/OS-bound (operator-provisioned) and not exercised here.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../helpers/assert.sh"

CHECK="$HOOKS/egress-check.sh"
BUILD="$HOOKS/egress-proxy/build-filter.sh"
ALLOW="$HOOKS/egress-allowlist.txt"
echo "-- egress (EG detection + filter) --"

# (1) DETECTION. Run egress-check.sh in a throwaway bootstrapped workdir with a given egress log.
#   echoes the denied_hosts count from .pipeline/egress-findings.json ('' if no findings file).
check_denied() {  # <egress-log-contents|__none__>
  local body="$1" w; w="$(mktemp -d)"; _WORKDIRS+=("$w")
  ( cd "$w"
    mkdir -p .pipeline; echo '{}' > .pipeline/state.json
    [ "$body" != "__none__" ] && printf '%s\n' "$body" > .pipeline/egress-log.jsonl
    bash "$CHECK" ) >/dev/null 2>&1
  jq -r '.denied_hosts' "$w/.pipeline/egress-findings.json" 2>/dev/null
}

# a denied host is flagged
assert_eq 1 "$(check_denied '{"host":"evil.example","action":"deny"}')" "one denied host → denied_hosts=1"
# multiple denies to the same host collapse to one host with an attempt count
assert_eq 1 "$(check_denied '{"host":"evil.example","action":"deny"}
{"host":"evil.example","action":"deny"}')" "repeated denies to one host → denied_hosts=1 (grouped)"
# two distinct denied hosts → 2
assert_eq 2 "$(check_denied '{"host":"evil.example","action":"deny"}
{"host":"exfil.test","action":"DENY"}')" "two distinct denied hosts (case-insensitive) → 2"
# allow-only traffic → 0 denied
assert_eq 0 "$(check_denied '{"host":"pypi.org","action":"allow"}
{"host":"github.com","action":"allow"}')" "all allowed → denied_hosts=0"
# malformed lines are skipped, not counted
assert_eq 0 "$(check_denied 'not json
{"host":"pypi.org","action":"allow"}')" "malformed line skipped → denied_hosts=0"
# no proxy log at all → no-op: no findings file (empty output)
assert_eq "" "$(check_denied __none__)" "no egress-log.jsonl → no-op (no findings file)"

# (2) FILTER. build-filter.sh turns the allow-list into anchored tinyproxy regexes.
FILT="$(bash "$BUILD" "$ALLOW" 2>/dev/null)"
assert_match "$FILT" '\(\^\|\\\.\)pypi\\\.org\$'      "filter has anchored pypi.org regex"
assert_match "$FILT" '\(\^\|\\\.\)github\\\.com\$'    "filter has anchored github.com regex"
assert_match "$FILT" '\(\^\|\\\.\)docker\\\.io\$'     "leading-dot .docker.io → host-or-subdomain regex"
# comments / blank lines produce no filter lines (count == non-comment host count)
HOSTS="$(grep -vE '^[[:space:]]*(#|$)' "$ALLOW" | grep -vE '^[[:space:]]*#' | sed 's/#.*//' | grep -cE '[^[:space:]]')"
LINES="$(printf '%s\n' "$FILT" | grep -cE '.')"
assert_eq "$HOSTS" "$LINES" "one filter regex per allow-listed host (no comment/blank leakage)"

finish egress
