#!/bin/bash
# Deterministically stamps a REAL `ran_at` (UTC, at Stop time) into a stage's JSON
# result artifact, so the recorded timestamp can never be a model-invented
# placeholder. F6: `test-results.json` and `security-status.json` were both seen
# with `ran_at:"2026-06-30T00:00:00Z"` (a guessed midnight, not the real run time).
#
# Wired as the FIRST Stop hook on the testing + security agents. It stamps `.ran_at`,
# which the later hooks never read, so ITS position is not load-bearing. NOTE (U-16f):
# the relative order of log-run.sh and record-clean.sh IS load-bearing on the testing
# agent — record-clean zeroes debug_retry_count and log-run records it, so log-run must
# run first. This hook stays first regardless. Zero-LLM, deterministic.
# The agent is still told to write a real `date -u` value (the honest path); THIS is
# the enforcement layer that guarantees it regardless of what the model wrote — the
# same two-layer pattern as the criterion-completeness gate.
#
# Fail-SOFT by design: this is telemetry hygiene, not a gate. It must NEVER block an
# agent's Stop. A missing artifact, missing jq, or malformed JSON leaves the file as
# written and returns non-zero-but-non-blocking (exit 1) or no-ops (exit 0).
#
# Usage: stamp-ran-at.sh <testing|security>

# Pipeline-project guard: no-op (exit 0) outside a bootstrapped pipeline project,
# mirroring the other ambient Stop hooks so it never touches an unrelated repo.
[ -f .pipeline/state.json ] || exit 0

STAGE="${1:?stage required}"
case "$STAGE" in
  testing)  ARTIFACT=".pipeline/test-results.json" ;;
  security) ARTIFACT=".pipeline/security-status.json" ;;
  *) echo "[stamp-ran-at] unknown stage '$STAGE' — nothing to stamp." >&2; exit 0 ;;
esac

# No artifact yet (e.g. the agent stopped before writing it, or was capped) — nothing
# to normalize. Not an error.
[ -f "$ARTIFACT" ] || exit 0

# jq rewrites the JSON. Without it, leave the file untouched and say so (non-blocking).
# jq is required pipeline-wide (the deploy gate fails closed without it), so this only
# fires in an already-broken environment.
if ! command -v jq >/dev/null 2>&1; then
  echo "[stamp-ran-at] jq not found — leaving $ARTIFACT .ran_at as written." >&2
  exit 1
fi

NOW_ISO=$(date -u +%Y-%m-%dT%H:%M:%SZ)
tmp=$(mktemp)
if jq --arg now "$NOW_ISO" '.ran_at = $now' "$ARTIFACT" > "$tmp" 2>/dev/null; then
  mv "$tmp" "$ARTIFACT"
  echo "[stamp-ran-at] $STAGE .ran_at = $NOW_ISO"
  exit 0
else
  rm -f "$tmp"
  echo "[stamp-ran-at] $ARTIFACT is not valid JSON — left unchanged." >&2
  exit 1
fi
