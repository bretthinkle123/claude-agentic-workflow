#!/usr/bin/env bash
# webfetch-guard.sh — proves guard-webfetch-domains.sh (autonomy plan Phase 4) enforces
# the WebFetch domain allowlist: an unlisted host is DENIED (exit 2, never a prompt), an
# allowlisted host passes (exit 0), and the URL parse cannot be fooled into reading an
# allowlisted host out of a URL that actually fetches elsewhere.
#
# Feeds a PreToolUse-shaped WebFetch event on stdin and asserts the hook's exit code:
#   exit 2 = blocked / fail-closed, exit 0 = allowed.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../helpers/assert.sh"

HOOK="$HOOKS/guard-webfetch-domains.sh"
LIST="$HOOKS/webfetch-domains.txt"
echo "-- webfetch-guard (autonomy Phase 4) --"

# The hook reads the allowlist from ~/.claude/hooks/webfetch-domains.txt (its published
# location), NOT the repo copy. Point HOME at a temp dir seeded with the repo's list so
# the suite is hermetic and tests the file that ships.
TMPH="$(mktemp -d)"
mkdir -p "$TMPH/.claude/hooks"
cp "$LIST" "$TMPH/.claude/hooks/webfetch-domains.txt"
trap 'rm -rf "$TMPH"' EXIT

# feed <url> — pipe a realistic PreToolUse WebFetch event into the hook.
feed() {
  printf '{"tool_name":"WebFetch","tool_input":{"url":%s}}' \
    "$(jq -Rn --arg u "$1" '$u')" | HOME="$TMPH" bash "$HOOK"
}
# feed_nourl — a WebFetch event with no url field (exercises the fail-closed path).
feed_nourl() {
  printf '{"tool_name":"WebFetch","tool_input":{}}' | HOME="$TMPH" bash "$HOOK"
}

assert_exit 0 "hook parses (bash -n)" bash -n "$HOOK"

# --- ALLOW: allowlisted hosts, across legitimate shapes ---------------------------
assert_exit 0 "allow: github.com/x"                 feed "https://github.com/x"
assert_exit 0 "allow: bare host, no path"           feed "https://pypi.org"
assert_exit 0 "allow: case-insensitive host"        feed "https://GITHUB.COM/x"
assert_exit 0 "allow: explicit port"                feed "https://github.com:443/x"
assert_exit 0 "allow: userinfo before real host"    feed "https://user@github.com/path"
assert_exit 0 "allow: suffix rule subdomain"        feed "https://www.anthropic.com/news"
assert_exit 0 "allow: http scheme osv.dev"          feed "http://osv.dev"
assert_exit 0 "allow: query string on allowed host" feed "https://pypi.org/search?q=x"

# --- DENY: unlisted hosts ---------------------------------------------------------
assert_exit 2 "deny: unrelated host"                feed "https://evil.example/x?data=secret"
assert_exit 2 "deny: lookalike prefix"              feed "https://notgithub.com"
assert_exit 2 "deny: allowed name as subdomain of attacker" feed "https://github.com.evil.com"

# --- DENY: URL-parse bypasses (the 2026-07-10 audit finding — regression) ---------
# These URLs are FETCHED from evil.com by WebFetch; a naive parser that strips userinfo
# before the fragment/query would misread the host as an allowlisted one and ALLOW them.
assert_exit 2 "deny: fragment-planted @ (audit bug)"  feed "https://evil.com#@github.com"
assert_exit 2 "deny: query-planted @ (audit bug)"     feed "https://evil.com?x=@github.com"
assert_exit 2 "deny: real userinfo=allowed, host=evil" feed "https://github.com@evil.com"

# --- FAIL-CLOSED: malformed input and a missing allowlist -------------------------
assert_exit 2 "fail-closed: no url field"           feed_nourl
assert_exit 2 "fail-closed: empty url"              feed ""
# A missing allowlist must deny, never allow (re-run install-global.sh is the fix).
assert_exit 2 "fail-closed: allowlist absent" bash -c \
  'printf "{\"tool_input\":{\"url\":\"https://github.com/x\"}}" | HOME="$(mktemp -d)" bash "'"$HOOK"'"'

# --- WIRING: the guard is actually a settings-level PreToolUse hook on WebFetch ----
# (No pipeline SUBAGENT holds WebFetch — only the main thread does — so this guards via
# settings.json, not agent frontmatter. Catches a silently-dropped wiring in either the
# framework settings or the app-repo template.)
for sf in "$REPO_ROOT/.claude/settings.json" "$REPO_ROOT/templates/project-settings.json"; do
  wired="$(jq -r '[.hooks.PreToolUse[]? | select(.matcher=="WebFetch") | .hooks[]?.command]
                  | any(contains("guard-webfetch-domains.sh"))' "$sf" 2>/dev/null)"
  assert_eq "true" "$wired" "guard wired as WebFetch PreToolUse in $(basename "$(dirname "$sf")")/$(basename "$sf")"
done

finish webfetch-guard
