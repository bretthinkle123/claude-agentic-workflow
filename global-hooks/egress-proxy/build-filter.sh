#!/bin/bash
# build-filter.sh — turn egress-allowlist.txt into a tinyproxy Filter file (EG Layer 2).
#
# tinyproxy with `FilterDefaultDeny Yes` + `Filter <file>` ALLOWS only hosts matching a line in
# the filter and DENIES everything else — a default-deny egress ACL. This script converts the
# human allow-list into the anchored host regexes tinyproxy expects, deterministically, so the
# proxy ACL is always derived from the single source of truth (no hand-maintained second list).
#
# Usage:  build-filter.sh [allowlist-path] > egress-filter.txt
#   default allowlist: ../egress-allowlist.txt (sibling of this dir), then ./egress-allowlist.txt
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ALLOW="${1:-}"
if [ -z "$ALLOW" ]; then
  for c in "$here/../egress-allowlist.txt" "$here/egress-allowlist.txt"; do
    [ -f "$c" ] && { ALLOW="$c"; break; }
  done
fi
[ -f "$ALLOW" ] || { echo "build-filter: allowlist not found ($ALLOW)" >&2; exit 2; }

# Each non-comment host → an anchored regex matching that host AND its subdomains. A leading `.`
# (e.g. `.docker.io`) is stripped and treated the same (host-or-subdomain). Dots are escaped.
while IFS= read -r line; do
  host="${line%%#*}"                       # strip inline comments
  host="$(printf '%s' "$host" | tr -d '[:space:]')"
  [ -z "$host" ] && continue
  host="${host#.}"                          # a leading-dot entry is host-or-subdomain anyway
  esc="$(printf '%s' "$host" | sed 's/\./\\./g')"
  printf '(^|\\.)%s$\n' "$esc"
done < "$ALLOW"
