#!/usr/bin/env bash
# run-agent-evals.sh — U-23 runner. Invokes the REAL pipeline agents against the
# planted-defect trees and asserts (deterministic grep over the agents' output) that each
# planted defect is named. Needs model access (an ANTHROPIC_API_KEY + the `claude` agent
# runner), so it is NOT part of the zero-LLM tests/run-eval.sh — run it as a CI job or by
# hand after editing a scanned agent (security.md, plan-audit.md, documentation.md), a
# conventions skill, or on a model bump.
#
# Two modes:
#   bash run-agent-evals.sh --check        # DETERMINISTIC: validate the corpus is
#                                          # well-formed (every case has a manifest and its
#                                          # planted_marker really exists in the tree). This
#                                          # is what static.sh's well-formedness check mirrors;
#                                          # it needs no model and always runs.
#   bash run-agent-evals.sh [case ...]     # FULL: invoke the agent(s) and assert findings.
#                                          # Requires the agent runner (see AGENT_CMD below).
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODE="${1:-full}"

fail=0
ok()  { echo "  PASS  $1"; }
no()  { echo "  FAIL  $1"; fail=1; }

# --- --check: deterministic corpus validity (no model) --------------------------------
if [ "$MODE" = "--check" ]; then
  for d in "$HERE"/*/; do
    [ -f "${d}expected-findings.json" ] || continue
    name="$(basename "$d")"
    marker="$(jq -r '.planted_marker // empty' "${d}expected-findings.json" 2>/dev/null)"
    if [ -z "$marker" ]; then no "$name: manifest has no planted_marker"; continue; fi
    if grep -rqF "$marker" "$d" --include='*.py' --include='*.tf' --include='*.md' --include='*.js' 2>/dev/null; then
      ok "$name: planted defect present (marker resolves in the tree)"
    else
      no "$name: planted_marker '$marker' not found in the case tree — the eval would pass vacuously"
    fi
  done
  [ "$fail" -eq 0 ] && echo "agent-eval corpus: well-formed" || echo "agent-eval corpus: INVALID"
  exit "$fail"
fi

# --- full: invoke the agents (requires a runner) --------------------------------------
# Wire AGENT_CMD to your agent runner. Contract: AGENT_CMD <agent> <prompt> runs the named
# global agent in $PWD (a throwaway copy of the case tree) to completion, writing its
# .pipeline/ artifacts. Left unset here because it is environment-specific (the SDK /
# `claude` CLI / a harness). Example: AGENT_CMD='claude-run-agent'.
: "${AGENT_CMD:=}"
if [ -z "$AGENT_CMD" ]; then
  echo "run-agent-evals: AGENT_CMD is not set — cannot invoke agents. Set it to your agent" >&2
  echo "runner (contract: AGENT_CMD <agent> <prompt> executes the agent in CWD), or use" >&2
  echo "--check for the deterministic corpus-validity pass." >&2
  exit 2
fi

CASES=("$@"); [ "${#CASES[@]}" -eq 0 ] && CASES=("$HERE"/*/)
for d in "${CASES[@]}"; do
  d="$HERE/$(basename "$d")/"
  man="${d}expected-findings.json"; [ -f "$man" ] || continue
  name="$(basename "$d")"
  agent="$(jq -r '.agent' "$man")"; prompt="$(jq -r '.prompt' "$man")"
  work="$(mktemp -d)"; cp -r "$d." "$work/"; rm -f "$work/expected-findings.json"
  ( cd "$work" && git init -q && mkdir -p .pipeline && printf '{}' > .pipeline/state.json \
    && $AGENT_CMD "$agent" "$prompt" ) >/dev/null 2>&1
  # assert each must_flag grep hits its named artifact
  n="$(jq -r '.must_flag | length' "$man")"
  for i in $(seq 0 $((n - 1))); do
    g="$(jq -r ".must_flag[$i].grep" "$man")"; wf="$(jq -r ".must_flag[$i].where" "$man")"; id="$(jq -r ".must_flag[$i].id" "$man")"
    if grep -qiE "$g" "$work/.pipeline/$wf" 2>/dev/null; then ok "$name/$id caught"; else no "$name/$id MISSED (agent did not name the planted defect)"; fi
  done
  rm -rf "$work"
done
[ "$fail" -eq 0 ] && echo "agent-evals: all planted defects caught" || echo "agent-evals: DETECTION REGRESSION"
exit "$fail"
