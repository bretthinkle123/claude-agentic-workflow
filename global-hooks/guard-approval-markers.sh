#!/bin/bash
# guard-approval-markers.sh — structural block (PR K, M9) against a subagent
# FABRICATING a human-owned gate marker:
#   .pipeline/diff-approved   — the M5 human diff-review approval (deployment gate anchor)
#   .pipeline/plan-approved   — the human plan checkpoint (implementation refuses without it)
#   .pipeline/design-approved — the human design-spec checkpoint (planning treats visual intent as
#                               authoritative only if it exists + the currency hash matches). The
#                               design-spec agent holds Write, so guarding this stops it self-approving.
#   .pipeline/waivers.json    — human-recorded security waivers (Option B; record-waiver.sh writes it,
#                               deployment-gate.sh cross-checks claimed waivers against it)
#
# Both markers are created ONLY by the human, on the un-hooked main thread
# (approve-diff.sh writes diff-approved; a human `touch`es plan-approved). A subagent
# writing either one would forge a human approval and bypass the checkpoint. This hook
# is wired as an ADDITIONAL PreToolUse Bash hook on every Bash-carrying subagent and
# blocks (exit 2) any command that WRITES a marker.
#
# Writes only, not reads: the implementation agent legitimately VERIFIES
# plan-approved exists (`test -f .pipeline/plan-approved`) — a read must pass through.
# So we match redirection-into / mutating-command-targeting a marker, not every mention.
# review-manifest.json is deliberately NOT guarded (documentation's write-review-manifest.sh
# writes it legitimately, and post-F3 the gate no longer reads it — forging it is inert).
#
# Pairs with the settings.json Write/Edit deny (closes the non-Bash tool vector). The
# residual — obfuscated Bash (marker path built from a variable / $() / base64) can slip
# past this string scan — is documented in docs/pipeline-threat-model.md. This raises the
# bar from "just write the file" to "defeat two guards (one non-obfuscatable) AND match the
# currency hash AND beat the human-approves-first ordering."
set -uo pipefail

# Read the PreToolUse event and pull the Bash command. Fail TOWARD inspection: if the
# field can't be parsed (no jq / unexpected shape) scan the whole raw payload instead,
# so a malformed event can't smuggle a write through unread.
PAYLOAD="$(cat)"
CMD=""
if command -v jq >/dev/null 2>&1; then
  CMD="$(printf '%s' "$PAYLOAD" | jq -r '.tool_input.command // empty' 2>/dev/null)"
fi
[ -z "$CMD" ] && CMD="$PAYLOAD"

MARK='\.pipeline/((diff|plan|design)-approved|waivers\.json)'

# WRITE contexts (block): redirection into a marker (>, >>, >|, &>); a marker passed to a
# mutating command AT A COMMAND POSITION; an in-place edit of a marker. READ contexts
# (test -f / [ -f / ls / cat / grep / stat) match none of these and pass through.
#
# The mutating-command patterns are anchored to a command position (start of string, or
# after ; | & ( — a command separator) so a mutating verb appearing as prose inside a
# `git commit -m "touch up .pipeline/diff-approved"` message is NOT mistaken for a write.
if printf '%s' "$CMD" | grep -qE ">>?[|]?[[:space:]]*[^[:space:]<>|&;]*$MARK" \
 || printf '%s' "$CMD" | grep -qE "(^|[;&|(])[[:space:]]*(tee|cp|mv|install|dd|ln|rsync|touch|truncate)\b[^;|&]*$MARK" \
 || printf '%s' "$CMD" | grep -qE "(^|[;&|(])[[:space:]]*(sed|perl)\b[^;|&]*-i[^;|&]*$MARK"; then
  echo "Blocked: this command writes a human-owned file (.pipeline/diff-approved, .pipeline/plan-approved, .pipeline/design-approved, or .pipeline/waivers.json). Those are created only by a human on the main thread (approve-diff.sh / touch / the orchestrator recording design-approved / record-waiver.sh) — a subagent must never forge one. This is the M5 / plan-approval / design-approval / waiver structural guard (PR K + Option B + DS). If a finding cannot be met, STOP and report it so the human can decide (fix or record a waiver); do not write the file yourself." >&2
  exit 2
fi
exit 0
