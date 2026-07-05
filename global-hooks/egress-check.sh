#!/bin/bash
# egress-check.sh — Layer 3 detection for the default-deny egress control (EG side-track).
#
# The ENFORCEMENT is Layer 2 (a default-deny forward proxy; see global-hooks/egress-proxy/). This
# hook is the DETECTION half: it reads the proxy's decision log `.pipeline/egress-log.jsonl` and
# surfaces every DENIED outbound attempt (a request to a non-allow-listed host) as a security
# signal — turning "was there an injection attempt to phone home?" from invisible into an auditable
# line. A denied attempt is a WARNING (the proxy already blocked it); a repeated / exfil-shaped
# burst is worth escalating in the security report.
#
# It is a SIGNAL, not a hard gate: it writes `.pipeline/egress-findings.json` for the security
# agent to fold into `warning_count`, and adds NO loop-exit conjunct (the proxy is the teeth, not
# this). Absent proxy log ⇒ no findings ⇒ no-op (backward compatible; also the state on any host
# where the operator has not provisioned the Layer-2 proxy yet). Wired as a security Stop hook.
#
# egress-log.jsonl shape (one JSON object per outbound decision, written by the proxy):
#   {"ts":"2026-07-04T…Z","host":"evil.example","action":"deny"}
#   {"ts":"…","host":"pypi.org","action":"allow"}
set -uo pipefail
[ -f .pipeline/state.json ] || exit 0            # ambient no-op outside a bootstrapped project
command -v jq >/dev/null 2>&1 || exit 0           # no jq ⇒ can't parse/emit JSON
LOG=.pipeline/egress-log.jsonl
[ -f "$LOG" ] || exit 0                            # no proxy log ⇒ nothing to detect ⇒ no-op
OUT=.pipeline/egress-findings.json

# Every denied decision, grouped by host with a count. Processed LINE BY LINE with `fromjson?`
# so a single malformed line is skipped INDIVIDUALLY — never drops the whole log (a slurp `-s`
# would abort on one junk line and blind the detector). `deny` is matched case-insensitively.
DENIED=$(jq -Rnc '
  [ inputs | fromjson? | select(type=="object")
        | select((.action // "" | ascii_downcase) == "deny")
        | (.host // "unknown") ]
  | group_by(.) | map({host: .[0], attempts: length})
' "$LOG" 2>/dev/null || echo '[]')
DENIED="${DENIED:-[]}"
COUNT=$(jq 'length' <<<"$DENIED" 2>/dev/null || echo 0)

jq -n --argjson d "$DENIED" --argjson c "${COUNT:-0}" --arg t "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  '{ran_at:$t, denied_hosts:$c, denied:$d}' > "$OUT"

if [ "${COUNT:-0}" -gt 0 ]; then
  HOSTS=$(jq -rc '[.[].host] | join(", ")' <<<"$DENIED" 2>/dev/null)
  echo "[egress-check] $COUNT non-allow-listed host(s) DENIED by the egress proxy: $HOSTS — surface in the security report (possible injection phone-home). See $OUT and $LOG." >&2
else
  echo "[egress-check] no denied egress in $LOG (all outbound was allow-listed)."
fi
exit 0
