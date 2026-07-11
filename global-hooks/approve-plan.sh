#!/bin/bash
# The human plan checkpoint (M4″-A1) — the plan-side twin of approve-diff.sh.
#
# Why a helper instead of `touch .pipeline/plan-approved`: in the M4″ run the operator
# answered "Approved — marker touched" while the marker did NOT exist (a session/terminal
# mix-up); the orchestrator correctly refused and polled for ~2h. A single script that
# checks the plan exists, asks for explicit confirmation, and writes the marker makes
# "answered but not touched" impossible — you ran it or you didn't. Bare `touch` still
# works (the checkpoint gate only tests existence); this is the recommended path.
#
# Writes .pipeline/plan-approved = {approved_at, plan_sha256, note}. The sha records
# WHICH plan bytes were approved (provenance for the audit trail); no gate consumes it
# today — existence remains the contract, so an empty touch-file stays valid.
#
# HUMAN-ONLY BY DESIGN: refuses unless stdin is a TTY (same rationale as approve-diff.sh;
# guard-approval-markers.sh + a settings deny block subagent writes to the marker).
# Run it yourself from your terminal:
#     bash ~/.claude/hooks/approve-plan.sh
set -euo pipefail

# Pipeline-project guard.
[ -f .pipeline/state.json ] || { echo "approve-plan: not a bootstrapped pipeline project (no .pipeline/state.json)." >&2; exit 1; }

# Human-only guard: no TTY ⇒ an automated/agent caller ⇒ refuse.
[ -t 0 ] || { echo "approve-plan: refusing — this is the human plan checkpoint and must be run interactively (no TTY detected). A subagent must not approve on your behalf." >&2; exit 2; }

[ -f .pipeline/plan.md ] || { echo "approve-plan: no .pipeline/plan.md to approve — run planning first." >&2; exit 1; }

PLAN_SHA=""
if command -v sha256sum >/dev/null 2>&1; then
  PLAN_SHA="$(sha256sum .pipeline/plan.md | cut -d' ' -f1)"
fi

echo "About to approve the plan at .pipeline/plan.md${PLAN_SHA:+ (sha256 $PLAN_SHA)}"
printf 'Have you reviewed plan.md (+ plan-audit.md if present)? Type "approve" to confirm: '
read -r ans
if [ "$ans" != "approve" ]; then
  echo "approve-plan: not approved (you typed '$ans'). No approval recorded."
  exit 1
fi

if command -v jq >/dev/null 2>&1; then
  jq -nc --arg t "$(date -u +%FT%TZ)" --arg s "$PLAN_SHA" \
    '{approved_at:$t, plan_sha256:$s, note:"human plan checkpoint"}' \
    > .pipeline/plan-approved
else
  : > .pipeline/plan-approved   # jq-less fallback: the empty marker is still valid
fi
# CN1-2: name the host + absolute path — a marker written on the WRONG machine/filesystem
# (e.g. the Windows clone while the run polls the WSL clone) looks identical to success.
echo "[approve-plan] recorded approval — $(hostname 2>/dev/null || uname -n):$(pwd)/.pipeline/plan-approved written${PLAN_SHA:+ (plan sha256 $PLAN_SHA)}"
echo "[approve-plan] if the run doesn't advance within a minute, confirm the pipeline session is polling THIS path."
