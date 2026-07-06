#!/bin/bash
# Appends one line to .pipeline/run-log.jsonl — per-stage pipeline telemetry.
# Wired as a Stop hook on every agent. Zero-LLM, deterministic.
#
# Usage: log-run.sh <stage> [model] [status] [retries] [notes]
#   stage   : planning|plan-audit|implementation|debugging|security|testing|documentation|deployment
#   model   : opus|sonnet|haiku  (default: auto-derived from the agent's published
#             frontmatter ~/.claude/agents/<stage>.md — the Stop-hook wiring passes
#             only <stage>, so the logged model can never desync from a frontmatter
#             model change. An explicit arg-2 still wins.)
#   status  : pass|fail|clean|issues-found|blocked|escalated  (default: auto-derive)
#   retries : integer  (default: auto-read from state.json)
#   notes   : free-text (default: auto-derive a short summary from the stage's
#             artifact). The Stop-hook wiring only ever passes <stage>,
#             so an explicit note is rare — auto-derivation keeps the field
#             populated instead of writing "notes":"" on every line.
#
# feature    — derived from the current git branch name
# status     — "auto" reads the relevant .pipeline artifact for the stage:
#              implementation → smoke-status.json, security → security-status.json,
#              testing → test-results.json, debugging → state.json (retry cap).
#              Stages with no outcome artifact default to "pass" (= the agent ran
#              to completion, not a verified-correct signal).
# extras     — stage-specific fields pulled from pipeline artifacts:
#              testing   → coverage, tests.{total,passed,failed}
#              security  → critical_findings, warning_findings
#
# attempt    — how many times this (feature,stage) has been logged, +1 (audit T2). Makes
#              resumes/retries distinct instead of collapsing to one line.
#
# CAP-OUT BREADCRUMB (audit T1): a Stop hook does NOT fire when an agent hits its maxTurns
# cap, so a capped stage would otherwise leave NO line at all and the log under-counts the
# run. When the orchestrator OBSERVES a cap-out, it must call this script explicitly to
# leave the breadcrumb, e.g.:   log-run.sh testing "" capped
# The `attempt` field then distinguishes that capped line from the eventual clean resume.
#
# Not captured (not exposed to shell hooks by Claude Code):
#   turns_used, duration_s  — use timestamp deltas between log entries as a proxy

set -euo pipefail

# Pipeline-project guard: installed globally and wired as a Stop hook on every agent.
# No-op in any repo that is not a bootstrapped pipeline project (no .pipeline/state.json)
# so it never appends a run-log line in an unrelated repo.
[ -f .pipeline/state.json ] || exit 0

STAGE="${1:?stage required}"
# Model: derive from the agent's published frontmatter when not passed explicitly.
# The Stop-hook wiring passes only <stage>, so $2 is normally empty -> read the
# model from ~/.claude/agents/<stage>.md (the single source of truth) so a model
# change in frontmatter can never desync a hardcoded arg. $STAGE matches the agent
# filename for all 8 agents. An explicit arg-2 still wins (back-compatible).
MODEL="${2:-auto}"
if [ "$MODEL" = "auto" ]; then
  AGENT_FILE="$HOME/.claude/agents/$STAGE.md"
  # Clear first so a missing agent file (not installed) falls through to "unknown"
  # rather than logging the literal "auto" sentinel.
  MODEL=""
  [ -f "$AGENT_FILE" ] && MODEL=$(grep -m1 '^model:' "$AGENT_FILE" 2>/dev/null \
    | sed 's/^model:[[:space:]]*//' | tr -d '[:space:]')
  [ -n "$MODEL" ] || MODEL="unknown"
fi
STATUS="${3:-auto}"
RETRIES="${4:-auto}"
NOTES="${5:-}"

# Feature: current git branch (slug for the in-progress change). symbolic-ref
# resolves the branch even before the first commit, unlike `rev-parse --abbrev-ref`
# which prints "HEAD" and exits non-zero on a commitless repo. Use a replace-style
# guard (|| FEATURE="") so a failure can't append stray output to the value.
FEATURE=$(git symbolic-ref --short HEAD 2>/dev/null) || FEATURE=""
[ -n "$FEATURE" ] || FEATURE="unknown"

# Attempt number (audit T2): how many times this (feature, stage) pair has already been
# logged, +1. A Stop hook CANNOT fire on a maxTurns cap, so cap-outs and resumes are
# logged by the orchestrator invoking this script explicitly (e.g.
# `log-run.sh testing "" capped`); numbering the attempts keeps resumes/retries as
# distinct, countable lines instead of collapsing to one, so the run log stops
# under-counting invocations (the T1/T2 telemetry gap).
ATTEMPT=1
if [ -f .pipeline/run-log.jsonl ]; then
  PRIOR=$(jq -rs --arg f "$FEATURE" --arg s "$STAGE" \
    'map(select(.feature==$f and .stage==$s)) | length' .pipeline/run-log.jsonl 2>/dev/null || echo 0)
  [ -n "$PRIOR" ] && ATTEMPT=$((PRIOR + 1))
fi

# Retries: sum sanity + remediation counts from state.json
if [ "$RETRIES" = "auto" ]; then
  if [ -f .pipeline/state.json ]; then
    RETRIES=$(jq -r '(.debug_retry_count.sanity // 0) + (.debug_retry_count.remediation // 0)' \
      .pipeline/state.json 2>/dev/null || echo 0)
  else
    RETRIES=0
  fi
fi

# Status: derive from the stage's canonical output artifact
if [ "$STATUS" = "auto" ]; then
  case "$STAGE" in
    security)
      STATUS=$(jq -r '.status // "unknown"' .pipeline/security-status.json 2>/dev/null || echo "unknown")
      ;;
    testing)
      STATUS=$(jq -r '.status // "unknown"' .pipeline/test-results.json 2>/dev/null || echo "unknown")
      ;;
    implementation)
      # smoke-check.sh (earlier in the same Stop array) writes this fresh on every
      # run, so it reflects the smoke result for the code just implemented.
      STATUS=$(jq -r '.status // "unknown"' .pipeline/smoke-status.json 2>/dev/null || echo "unknown")
      ;;
    debugging)
      if [ -f .pipeline/state.json ]; then
        MAX=$(jq -r '.max_retries // 3' .pipeline/state.json 2>/dev/null || echo 3)
        CURRENT=$(jq -r '(.debug_retry_count.sanity // 0) + (.debug_retry_count.remediation // 0)' \
          .pipeline/state.json 2>/dev/null || echo 0)
        [ "$CURRENT" -ge "$MAX" ] && STATUS="escalated" || STATUS="pass"
      else
        STATUS="pass"
      fi
      ;;
    *)
      STATUS="pass"
      ;;
  esac
fi

# Scope: files touched so far (tracked diff + untracked new files).
# `git diff HEAD` fails on a repo with no commits (greenfield first run); capture
# the file lists with a guard FIRST so pipefail can't abort the script, then count.
TRACKED_LIST=$(git diff HEAD --name-only 2>/dev/null || true)
UNTRACKED_LIST=$(git ls-files --others --exclude-standard 2>/dev/null || true)
TRACKED=0; UNTRACKED=0
[ -n "$TRACKED_LIST" ]   && TRACKED=$(printf '%s\n' "$TRACKED_LIST" | grep -c .)
[ -n "$UNTRACKED_LIST" ] && UNTRACKED=$(printf '%s\n' "$UNTRACKED_LIST" | grep -c .)
FILES_CHANGED=$(( TRACKED + UNTRACKED ))

# Stage-specific extras pulled from pipeline artifacts
EXTRAS='{}'
case "$STAGE" in
  testing)
    if [ -f .pipeline/test-results.json ]; then
      # coverage.combined is the merged (surfaced, not gated) figure; fall back to the old flat
      # coverage object so pre-schema result files still log cleanly. Also record the
      # best-effort per-tier coverage (audit T4) so the log preserves unit vs
      # integration coverage instead of only the combined number — otherwise a thin
      # integration tier hidden behind a healthy combined figure is invisible.
      EXTRAS=$(jq -c '{coverage:(.coverage.combined // .coverage),
        coverage_by_tier:{unit:(.coverage.unit // null),integration:(.coverage.integration // null)},
        tests:{total:(.total // 0),passed:(.passed // 0),failed:(.failed // 0)},
        tests_by_type:(.tests_by_type // {}),
        test_strategy:(.test_strategy // "pyramid")}' \
        .pipeline/test-results.json 2>/dev/null || echo '{}')
    fi
    ;;
  security)
    if [ -f .pipeline/security-status.json ]; then
      EXTRAS=$(jq -c '{critical_findings:(.critical_count // 0),warning_findings:(.warning_count // 0)}' \
        .pipeline/security-status.json 2>/dev/null || echo '{}')
    fi
    ;;
esac

# Notes: a short human-readable summary of the stage outcome. The Stop-hook
# wiring only passes <stage> <model>, so $5 is virtually always empty — derive a
# note from the same artifact that feeds status/extras (zero-LLM, deterministic).
# An explicit note (when one is ever passed) wins. Stages with no machine-readable
# outcome artifact (planning, plan-audit, documentation, deployment) keep "".
if [ -z "$NOTES" ]; then
  case "$STAGE" in
    implementation)
      [ -f .pipeline/smoke-status.json ] && \
        NOTES="smoke $(jq -r '.status // "unknown"' .pipeline/smoke-status.json 2>/dev/null || echo unknown)"
      ;;
    security)
      [ -f .pipeline/security-status.json ] && \
        NOTES=$(jq -r '"\(.fixed_count // 0) fixed, \(.critical_count // 0) critical / \(.warning_count // 0) warning remaining"' \
          .pipeline/security-status.json 2>/dev/null || echo "")
      ;;
    testing)
      [ -f .pipeline/test-results.json ] && \
        NOTES=$(jq -r '
          ([.failures[]? | .name] | map(select(. != null and . != ""))) as $names
          | if (.failed // 0) > 0
            then "\(.failed) failed"
                 + (if ($names | length) > 0 then ": " + ($names | join(", ")) else "" end)
            else "\(.passed // 0)/\(.total // 0) passed" end' \
          .pipeline/test-results.json 2>/dev/null || echo "")
      ;;
    debugging)
      [ -f .pipeline/state.json ] && \
        NOTES=$(jq -r '"retries sanity=\(.debug_retry_count.sanity // 0) remediation=\(.debug_retry_count.remediation // 0) (cap \(.max_retries // 3))"' \
          .pipeline/state.json 2>/dev/null || echo "")
      ;;
  esac
fi

mkdir -p .pipeline
jq -nc \
  --arg  ts            "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg  feature       "$FEATURE" \
  --arg  stage         "$STAGE" \
  --arg  status        "$STATUS" \
  --arg  model         "$MODEL" \
  --argjson attempt    "$ATTEMPT" \
  --argjson retries    "$RETRIES" \
  --argjson files_changed "$FILES_CHANGED" \
  --arg  notes         "$NOTES" \
  --argjson extras     "$EXTRAS" \
  '{ts:$ts,feature:$feature,stage:$stage,status:$status,model:$model,attempt:$attempt,
    retries:$retries,files_changed:$files_changed,notes:$notes} + $extras' \
  >> .pipeline/run-log.jsonl

echo "[log-run] $FEATURE / $STAGE / $STATUS (model=$MODEL, files=$FILES_CHANGED)"
