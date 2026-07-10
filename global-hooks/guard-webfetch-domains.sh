#!/bin/bash
# guard-webfetch-domains.sh — deterministic domain allowlist for WebFetch (autonomy plan
# 4.2). Wired as a settings-level PreToolUse hook (matcher: WebFetch) — no pipeline
# SUBAGENT holds WebFetch (only planning has WebSearch), so the surface this guards is
# the MAIN THREAD, which reads untrusted content and is therefore injectable too.
#
# Why deny-not-ask: with checkpoints desk-only, an `ask` mid-run is a silent multi-hour
# stall. A deterministic denial returns to the agent, which adapts (WebSearch, registry
# metadata, or proceeds without the page) — the run keeps moving. Why guard at all: an
# attacker-controlled URL is an exfiltration channel (data encoded into the query string),
# the widest one the old bare `WebFetch` allow left open.
#
# Allowlist: ~/.claude/hooks/webfetch-domains.txt — one domain per line, `#` comments,
# leading `.` = this host and any subdomain (same format as egress-allowlist.txt).
# The settings WebFetch(domain:...) allow rules mirror this file; the hook is the
# non-bypassable backstop (fails closed on any parse/list problem).
#
# Denials append {ts, domain} to .pipeline/webfetch-denied.jsonl — triage that log into
# the domain list between runs; it converges exactly like the egress list.
set -uo pipefail

PAYLOAD="$(cat)"

URL=""
if command -v jq >/dev/null 2>&1; then
  URL="$(printf '%s' "$PAYLOAD" | jq -r '.tool_input.url // empty' 2>/dev/null)"
fi
if [ -z "$URL" ]; then
  echo "guard-webfetch-domains: could not extract a URL from the WebFetch call — failing closed." >&2
  exit 2
fi

# Extract the host from the authority. ORDER MATTERS (security): strip the path/query/
# fragment FIRST, THEN userinfo — otherwise an `@` planted in a fragment or query
# (https://evil.com#@github.com , https://evil.com?x=@github.com) fools the credential
# strip into keeping the trailing allowlisted-looking host while WebFetch really fetches
# evil.com. Sequence: strip scheme -> strip from first /?# (leaves userinfo@host:port)
# -> strip userinfo -> strip port -> lowercase.
HOST="$(printf '%s' "$URL" \
  | sed -E 's|^[A-Za-z][A-Za-z0-9+.-]*://||; s|[/?#].*$||; s|^[^@]*@||; s|:[0-9]+$||' \
  | tr '[:upper:]' '[:lower:]')"
if [ -z "$HOST" ]; then
  echo "guard-webfetch-domains: could not parse a host from '$URL' — failing closed." >&2
  exit 2
fi

LIST="$HOME/.claude/hooks/webfetch-domains.txt"
if [ ! -f "$LIST" ]; then
  echo "guard-webfetch-domains: allowlist $LIST missing — failing closed (re-run install-global.sh)." >&2
  exit 2
fi

while IFS= read -r line; do
  line="${line%%#*}"
  line="$(printf '%s' "$line" | tr -d '[:space:]')"
  [ -z "$line" ] && continue
  case "$line" in
    .*) # suffix rule: match the apex and any subdomain
      apex="${line#.}"
      [ "$HOST" = "$apex" ] && exit 0
      case "$HOST" in *".$apex") exit 0 ;; esac
      ;;
    *)
      [ "$HOST" = "$line" ] && exit 0
      ;;
  esac
done < "$LIST"

if [ -d .pipeline ]; then
  printf '{"ts":"%s","domain":"%s"}\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$HOST" \
    >> .pipeline/webfetch-denied.jsonl 2>/dev/null
fi

echo "Blocked: WebFetch to '$HOST' is not in the domain allowlist (~/.claude/hooks/webfetch-domains.txt). This is the deterministic egress guard for fetched URLs — an unlisted domain is denied, never prompted, so unattended runs keep moving. Adapt without this page (WebSearch, registry metadata, or proceed), and the denial log (.pipeline/webfetch-denied.jsonl) will be triaged into the allowlist between runs if the domain is legitimate." >&2
exit 2
