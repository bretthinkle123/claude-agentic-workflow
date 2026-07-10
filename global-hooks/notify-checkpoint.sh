#!/bin/bash
# notify-checkpoint.sh — page the operator when the pipeline needs a human (autonomy plan
# Phase 2). Called by the ORCHESTRATOR at the three pause points, and wired as a
# settings-level `Notification` hook so any unexpected permission/input wait pages too
# (stall-to-page, 2.2b) instead of silently freezing an unattended run.
#
# Usage: notify-checkpoint.sh <plan|diff|capped|attention|done> [feature-slug]
#
# PAYLOAD RULE (hard): the message is event kind + feature slug + repo basename ONLY.
# Never diff content, findings, file paths, or report text — this crosses an external
# service (ntfy.sh) and must carry nothing worth intercepting.
#
# Backends, in order:
#   ntfy  — NTFY_TOPIC set in ~/.claude/notify.env (topic IS the secret: long random
#           string, e.g. `openssl rand -hex 16`; subscribe in the ntfy app). Default.
#   toast — Windows BurntToast, same-machine only (no NTFY_TOPIC set).
#   log   — always: append to .pipeline/notify-log.jsonl when a .pipeline/ dir exists.
# A notification failure must NEVER wedge or fail a run: every path degrades silently
# and the script always exits 0.
set -uo pipefail

# Drain stdin when invoked as a Notification hook (payload JSON arrives on stdin; we
# deliberately ignore its contents — payload rule above). Skip when run from a TTY.
[ ! -t 0 ] && cat >/dev/null 2>&1

EVENT="${1:-attention}"
SLUG="${2:-}"
REPO="$(basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)")"
MSG="${SLUG:+${SLUG} @ }${REPO}"

ENVF="$HOME/.claude/notify.env"
# shellcheck disable=SC1090
[ -f "$ENVF" ] && . "$ENVF" 2>/dev/null

sent=""
if [ -n "${NTFY_TOPIC:-}" ]; then
  if curl -fsS --max-time 10 -H "Title: pipeline ${EVENT}" -d "$MSG" \
       "https://ntfy.sh/${NTFY_TOPIC}" >/dev/null 2>&1; then
    sent="ntfy"
  fi
fi

if [ -z "$sent" ] && command -v powershell.exe >/dev/null 2>&1; then
  if powershell.exe -NoProfile -NonInteractive -Command \
       "New-BurntToastNotification -Text 'pipeline ${EVENT}', '${MSG}'" >/dev/null 2>&1; then
    sent="toast"
  fi
fi

if [ -d .pipeline ]; then
  printf '{"ts":"%s","event":"%s","msg":"%s","via":"%s"}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$EVENT" "$MSG" "${sent:-none}" \
    >> .pipeline/notify-log.jsonl 2>/dev/null
fi

exit 0
