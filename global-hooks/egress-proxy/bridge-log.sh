#!/usr/bin/env bash
# bridge-log.sh — translate tinyproxy's log into the egress-check.sh schema
# (one JSON object per outbound decision: {"ts","host","action":"allow|deny"}), appended to
# .pipeline/egress-log.jsonl. Promoted from the README's inline awk (autonomy plan 5.4) so it
# is a single reviewed artifact run every pipeline run, not a copy-pasted one-liner.
#
# Reads the tinyproxy log on STDIN so it is testable and container-runtime-agnostic:
#   docker exec pipeline-egress-proxy cat /var/log/tinyproxy/tinyproxy.log | bridge-log.sh
# Optional arg 1 = output file (default .pipeline/egress-log.jsonl).
#
# FIRST-RUN VERIFY: tinyproxy's log wording varies by version ("Filtered"/"Denied" for a
# blocked CONNECT, "Established"/"Request" for an allowed one). Confirm the two markers below
# against YOUR proxy's actual log after the first run and adjust if a decision is mis-classed —
# the README flags this same caveat. A misparse only mis-labels the detection log; it never
# changes what the proxy itself allowed (that is the ACL, enforced independently).
set -uo pipefail

OUT="${1:-.pipeline/egress-log.jsonl}"
TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Pull the first dotted token on the line as the host, tag by the decision marker, then emit
# JSON. Lines matching neither marker are skipped.
awk -v ts="$TS" '
  function host_of(   i,h) { h=""; for (i=1;i<=NF;i++) if ($i ~ /[A-Za-z0-9-]\.[A-Za-z]/) { h=$i; sub(/:[0-9]+$/,"",h); break } return h }
  /Filtered|Denied/          { h=host_of(); if (h!="") printf "{\"ts\":\"%s\",\"host\":\"%s\",\"action\":\"deny\"}\n",  ts, h }
  /Established|Request|Connect/ { h=host_of(); if (h!="") printf "{\"ts\":\"%s\",\"host\":\"%s\",\"action\":\"allow\"}\n", ts, h }
' >> "$OUT"
