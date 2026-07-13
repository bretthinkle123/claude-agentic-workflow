#!/bin/bash
# The human diff-review checkpoint (M5). After the pipeline goes GREEN and
# documentation writes its files, a HUMAN reviews the full diff + the
# security/test/quality reports and runs THIS script to record approval. The deploy
# gate then requires the approval AND that the committed bytes match the approved
# ones — so "what ships == what a human approved," not merely "what a machine
# re-anchored" (closes F3: the gate no longer trusts the machine-written
# review-manifest, which the deployer could regenerate).
#
# Writes .pipeline/diff-approved = {approved_change_hash, approved_at, note}. The hash
# is the shared change-set hash (compute-change-hash.sh) — identical to what
# deployment-gate.sh recomputes, so the two match byte-for-byte.
#
# HUMAN-ONLY BY DESIGN: refuses unless stdin is a TTY. A subagent's Bash tool runs
# non-interactively (no controlling terminal), so the deployment agent cannot approve
# *through this helper*. It is also instructed never to write .pipeline/diff-approved by
# any other means, and a structural guard now enforces that (PR K): guard-approval-markers.sh
# blocks Bash writes to the marker on every subagent, plus a settings Write/Edit deny. The
# gate still can't tell who wrote the file; the residual obfuscated-Bash risk is documented
# in docs/pipeline-threat-model.md. Run it yourself from your terminal:
#     bash ~/.claude/hooks/approve-diff.sh
set -euo pipefail

# Resolve the sibling hash helper relative to THIS script (global install location),
# not the CWD, so the recorded hash matches deployment-gate.sh's recompute exactly.
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Pipeline-project guard.
[ -f .pipeline/state.json ] || { echo "approve-diff: not a bootstrapped pipeline project (no .pipeline/state.json)." >&2; exit 1; }

# Human-only guard: no TTY ⇒ an automated/agent caller ⇒ refuse. This is what makes
# the checkpoint a real human gate rather than something the deployment agent can tick.
[ -t 0 ] || { echo "approve-diff: refusing — this is the human diff-review checkpoint and must be run interactively (no TTY detected). A subagent must not approve on your behalf." >&2; exit 2; }

command -v jq >/dev/null 2>&1 || { echo "approve-diff: jq not found on PATH." >&2; exit 2; }

CURRENT="$(bash "$HOOK_DIR/compute-change-hash.sh")"

# Sanity: you should be approving exactly what documentation finalized. If the tree
# has drifted from documentation's reviewed_change_hash, re-run documentation first.
RECORDED="$(jq -r '.reviewed_change_hash' .pipeline/review-manifest.json 2>/dev/null || echo '')"
if [ -n "$RECORDED" ] && [ "$RECORDED" != "null" ] && [ "$RECORDED" != "$CURRENT" ]; then
  echo "approve-diff: working tree ($CURRENT) does not match documentation's reviewed hash ($RECORDED)." >&2
  echo "            Re-run documentation so the reviewed state is current, then review the diff again." >&2
  exit 2
fi

echo "About to approve change-set hash: $CURRENT"
printf 'Have you reviewed the full diff + the security/test/quality reports? Type "approve" to confirm: '
read -r ans
if [ "$ans" != "approve" ]; then
  echo "approve-diff: not approved (you typed '$ans'). No approval recorded."
  exit 1
fi

# F1 (events-force-rls run): record the per-path approved state alongside the aggregate
# hash. The gate's currency check compared ONLY the aggregate change-set hash, so any
# tree divergence after approval — including out-of-scope files a diff-scoped commit
# deliberately leaves dirty, or the mere act of staging — blocked every later command
# (two deployment-gate blocks in that run). With {path: content-sha256} recorded, the
# gate verifies each changed path against its approved bytes: committed-at-approved-bytes
# paths drop out of the check, still-dirty approved paths match, and any NEW or MODIFIED
# path still blocks. "__deleted__" records an approved deletion.
APPROVED_PATHS=$( { git diff HEAD --name-only 2>/dev/null; git ls-files --others --exclude-standard; } \
  | LC_ALL=C sort -u | while IFS= read -r p; do
      [ -n "$p" ] || continue
      if [ -f "$p" ]; then h=$(sha256sum "$p" | cut -d' ' -f1); else h="__deleted__"; fi
      jq -nc --arg p "$p" --arg h "$h" '{($p): $h}'
    done | jq -sc 'add // {}')
[ -n "$APPROVED_PATHS" ] || APPROVED_PATHS='{}'

jq -nc --arg h "$CURRENT" --arg t "$(date -u +%FT%TZ)" --argjson paths "$APPROVED_PATHS" \
  '{approved_change_hash:$h, approved_paths:$paths, approved_at:$t, note:"human diff-review checkpoint (M5)"}' \
  > .pipeline/diff-approved
# CN1-2: name the host + absolute path — a marker written on the WRONG machine/filesystem
# (e.g. the Windows clone while the run polls the WSL clone) looks identical to success.
echo "[approve-diff] recorded approval — $(hostname 2>/dev/null || uname -n):$(pwd)/.pipeline/diff-approved (approved_change_hash=$CURRENT)"
echo "[approve-diff] if the run doesn't advance within a minute, confirm the pipeline session is polling THIS path."
