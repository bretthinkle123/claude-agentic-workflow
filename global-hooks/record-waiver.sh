#!/bin/bash
# record-waiver.sh — HUMAN-ONLY recorder for security waivers (Option B).
#
# A waiver excuses an otherwise-blocking finding AFTER a human accepts the risk:
#   - osv  : a High/Critical CVE (CVSS >= 7.0) that cannot be patched this cycle
#   - asvs : an unmet ASVS 5.0.0 L1/L2 (or in-scope L3) code/config requirement
#
# Waivers live in .pipeline/waivers.json and are written ONLY here, interactively.
# The security agent may READ and honor them but CANNOT create one:
#   - this script refuses without a TTY (a subagent's Bash tool has no controlling terminal);
#   - guard-approval-markers.sh blocks subagent Bash WRITES to waivers.json;
#   - a settings Write/Edit deny covers the non-Bash tool vector;
#   - deployment-gate.sh cross-checks every waiver the agent CLAIMED in security-status.json
#     against this file, so a fabricated waiver blocks the deploy.
# This closes the "agent self-writes a waiver to go green" vector (the same hardening
# pattern as approve-diff.sh / plan-approved; see docs/pipeline-threat-model.md).
#
# Run it yourself, from your terminal:
#     bash ~/.claude/hooks/record-waiver.sh
set -euo pipefail

[ -f .pipeline/state.json ] || { echo "record-waiver: not a bootstrapped pipeline project (no .pipeline/state.json)." >&2; exit 1; }

# Human-only guard: no TTY ⇒ an automated/agent caller ⇒ refuse.
[ -t 0 ] || { echo "record-waiver: refusing — a waiver is a human risk-acceptance decision and must be recorded interactively (no TTY detected). A subagent must not waive on your behalf." >&2; exit 2; }

command -v jq >/dev/null 2>&1 || { echo "record-waiver: jq not found on PATH." >&2; exit 2; }

F=.pipeline/waivers.json
[ -f "$F" ] || echo '{"osv":[],"asvs":[]}' > "$F"

printf 'Waiver type (osv | asvs): '; read -r TYPE
case "$TYPE" in
  osv|asvs) : ;;
  *) echo "record-waiver: type must be 'osv' or 'asvs' (got '$TYPE'). Nothing recorded."; exit 1 ;;
esac

printf 'Finding id (CVE/GHSA for osv; ASVS requirement id e.g. 6.3.3 for asvs): '; read -r ID
[ -n "$ID" ] || { echo "record-waiver: an id is required. Nothing recorded."; exit 1; }

printf 'Reason (why this finding is acceptable or not applicable here): '; read -r REASON
[ -n "$REASON" ] || { echo "record-waiver: a reason is required. Nothing recorded."; exit 1; }

printf 'Approved by (your name / identity): '; read -r WHO
[ -n "$WHO" ] || WHO="${USER:-unknown}"

printf 'Record %s waiver id="%s"? Type "waive" to confirm: ' "$TYPE" "$ID"; read -r ANS
[ "$ANS" = "waive" ] || { echo "record-waiver: not recorded (you typed '$ANS')."; exit 1; }

TMP="$F.tmp"
# Replace any existing entry with the same id, then append (idempotent by id).
jq --arg t "$TYPE" --arg id "$ID" --arg r "$REASON" --arg by "$WHO" --arg at "$(date -u +%FT%TZ)" '
  .[$t] = ((.[$t] // []) | map(select(.id != $id)) + [{id:$id, reason:$r, approved_by:$by, recorded_at:$at}])
' "$F" > "$TMP" && mv "$TMP" "$F"

echo "[record-waiver] recorded $TYPE waiver id=$ID (approved_by=$WHO). deployment-gate.sh will now honor it for this project."
