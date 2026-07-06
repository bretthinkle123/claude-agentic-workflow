#!/bin/bash
# Documentation's final action: write .pipeline/review-manifest.json — a
# reviewed_change_hash sanity anchor (approve-diff.sh checks the tree still matches
# it before recording a human approval), plus a UTC timestamp. It is NOT the deploy
# gate's currency anchor anymore: post-F3 the gate reads diff-approved's
# approved_change_hash (the human's), never this machine-written hash. Runs the shared
# compute-change-hash.sh so the recorded hash matches deployment-gate.sh's recompute
# exactly. Invoked via Bash by the documentation
# agent; the whole script is covered by the Bash($HOME/.claude/hooks/*.sh) allow-list,
# so it runs without per-binary permission prompts (replacing the inline
# git/sort/xargs/cat/sha256sum/awk/date pipeline that otherwise prompts).
set -euo pipefail
# Resolve the sibling hash helper relative to THIS script (global install location),
# not the CWD, so the recorded hash still matches deployment-gate.sh's recompute.
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
mkdir -p .pipeline
HASH=$(bash "$HOOK_DIR/compute-change-hash.sh")
printf '{"reviewed_change_hash":"%s","ran_at":"%s"}\n' "$HASH" "$(date -u +%FT%TZ)" > .pipeline/review-manifest.json
echo "[write-review-manifest] reviewed_change_hash=$HASH"
