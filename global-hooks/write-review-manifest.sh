#!/bin/bash
# Documentation's final action: write .pipeline/review-manifest.json — the
# reviewed_change_hash currency anchor the deployment gate checks, plus a UTC
# timestamp. Runs the shared compute-change-hash.sh so the recorded hash matches
# deployment-gate.sh's recompute exactly. Invoked via Bash by the documentation
# agent; the whole script is covered by the Bash($HOME/.claude/hooks/*.sh) allow-list,
# so it runs without per-binary permission prompts (replacing the inline
# git/sort/xargs/cat/sha256sum/awk/date pipeline that otherwise prompts).
set -euo pipefail
# Resolve the sibling hash helper relative to THIS script (global install location),
# not the CWD, so the recorded hash still matches deployment-gate.sh's recompute.
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
mkdir -p .pipeline
HASH=$("$HOOK_DIR/compute-change-hash.sh")
printf '{"reviewed_change_hash":"%s","ran_at":"%s"}\n' "$HASH" "$(date -u +%FT%TZ)" > .pipeline/review-manifest.json
echo "[write-review-manifest] reviewed_change_hash=$HASH"
