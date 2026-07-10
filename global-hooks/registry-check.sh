#!/bin/bash
# registry-check.sh — plan-audit's dependency reality-check, scoped (autonomy plan 1.2b).
#
# The anti-slopsquatting lookup (dependency-audit-policy skill) needs ONE network verb:
# an HTTPS GET against a package registry's JSON API. Bare `curl` must never be
# allowlisted (any-host egress = the threat model's "unrestricted curl" residual), so
# this wrapper enumerates the registry hosts and refuses everything else. It rides the
# existing `Bash(~/.claude/hooks/*.sh)` allow rule — plan-audit calls it instead of curl,
# and the run never prompts.
#
# Usage: registry-check.sh <npm|pypi> <package-name>
# Exit: 0 = package exists (JSON on stdout)
#       4 = package DOES NOT EXIST on the registry (the slopsquat signal)
#       3 = network/timeout — treat as "unverified", NOT "absent" (per the skill)
#       2 = bad invocation (unknown ecosystem / missing or unsafe package name)
set -uo pipefail

ECO="${1:-}"; PKG="${2:-}"

if [ -z "$ECO" ] || [ -z "$PKG" ]; then
  echo "usage: registry-check.sh <npm|pypi> <package-name>" >&2
  exit 2
fi

# Package names feed a URL — constrain to registry-legal characters so this can't be
# steered into a different path/host (npm scopes use @ and /; no dots-only traversal).
case "$PKG" in
  *[!A-Za-z0-9@/._-]*|*..*|/*|.*)
    echo "registry-check: unsafe package name: $PKG" >&2
    exit 2 ;;
esac

case "$ECO" in
  npm)  URL="https://registry.npmjs.org/${PKG}" ;;
  pypi) URL="https://pypi.org/pypi/${PKG}/json" ;;
  *)
    echo "registry-check: unknown ecosystem '$ECO' (npm|pypi)" >&2
    exit 2 ;;
esac

HTTP_CODE="$(curl -fsS --max-time 15 -o /tmp/registry-check.$$ -w '%{http_code}' "$URL" 2>/dev/null)"
RC=$?

if [ "$RC" -eq 0 ] && [ "$HTTP_CODE" = "200" ]; then
  cat /tmp/registry-check.$$; rm -f /tmp/registry-check.$$
  exit 0
fi
rm -f /tmp/registry-check.$$

# curl -f exits 22 on HTTP >= 400; distinguish a definitive 404 from network trouble.
if [ "$RC" -eq 22 ]; then
  echo "registry-check: $PKG NOT FOUND on $ECO (404) — treat as does-not-exist" >&2
  exit 4
fi

echo "registry-check: network failure reaching $ECO (curl rc=$RC) — treat as UNVERIFIED, not absent" >&2
exit 3
