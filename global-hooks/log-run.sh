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

# Hook start time — the freshness anchor for sibling-hook artifacts (F-M4-3): Stop hooks
# in the same event array run CONCURRENTLY, so an artifact another hook writes (smoke
# status) may not exist yet when this script reads it.
HOOK_START=$(date +%s)

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

# Feature: a STABLE slug for the in-progress change (U-16a). The M3 series split one
# feature's telemetry across two keys because `feature` was the git branch and the
# deployment agent creates the branch mid-run (lines flip "main" → the branch), which
# also restarted the per-(feature,stage) attempt counter. Prefer `.pipeline/state.json
# .feature` (set once at feature start, before branching) so the slug is contiguous;
# fall back to the branch as before. The branch is recorded separately below so nothing
# is lost.
BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null) || BRANCH=""
[ -n "$BRANCH" ] || BRANCH="unknown"
FEATURE=""
[ -f .pipeline/state.json ] && FEATURE=$(jq -r '(.feature // empty)' .pipeline/state.json 2>/dev/null || echo "")
[ -n "$FEATURE" ] || FEATURE="$BRANCH"

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
      # smoke-check.sh is listed earlier in the same Stop array, but same-event hooks
      # run CONCURRENTLY — frontmatter order is NOT execution order (F-M4-3: M4 logged
      # attempt 3 as "unknown" 5 s before smoke-status.json's pass stamp landed). Wait
      # (bounded) until smoke-status.json is at least as new as this hook's start
      # before trusting it; if it never freshens, log "pending-smoke" — an explicit
      # couldn't-know-yet, never a stale result and never a false "unknown".
      SMOKE_FRESH=""
      # LOG_RUN_SMOKE_WAIT_S: bound of the freshness wait (default 20 s; the eval suite
      # sets it low so the stale-smoke case doesn't stall the harness).
      for _i in $(seq 1 "${LOG_RUN_SMOKE_WAIT_S:-20}"); do
        if [ -f .pipeline/smoke-status.json ]; then
          SMOKE_MTIME=$(stat -c %Y .pipeline/smoke-status.json 2>/dev/null || echo 0)
          if [ "$SMOKE_MTIME" -ge $((HOOK_START - 2)) ]; then SMOKE_FRESH=1; break; fi
        fi
        sleep 1
      done
      if [ -n "$SMOKE_FRESH" ]; then
        STATUS=$(jq -r '.status // "unknown"' .pipeline/smoke-status.json 2>/dev/null || echo "unknown")
      else
        STATUS="pending-smoke"
      fi
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

# Deployment files_changed (U-16c): the deployment agent commits, so by the time its
# Stop hook fires the working tree is clean and the diff-based count above is 0 — the M3
# deployment lines all read files_changed:0. When the tree is clean and a HEAD exists,
# count the just-made commit's files instead, so the deployment line reflects what shipped.
if [ "$STAGE" = "deployment" ] && [ "$FILES_CHANGED" -eq 0 ] && git rev-parse --verify -q HEAD >/dev/null 2>&1; then
  COMMIT_FILES=$(git show --stat --name-only --format= HEAD 2>/dev/null | grep -c . || echo 0)
  [ -n "$COMMIT_FILES" ] && FILES_CHANGED="$COMMIT_FILES"
fi

# Stage-specific extras pulled from pipeline artifacts.
# U-16d: a CAPPED line carries NO fresh outcome artifact — the stage stopped mid-work, so
# any artifact on disk is the PREVIOUS run's (M3/feature-3 logged a capped testing line as
# "142/142 passed" with a prior run's coverage, and another as a partial mid-write 65/65).
# When status was explicitly passed as `capped` (or any explicit non-auto terminal that
# isn't a verified outcome), skip artifact-derived notes+extras entirely so stale/partial
# numbers can't masquerade as this attempt's result.
EXTRAS='{}'
if [ "${3:-auto}" = "capped" ]; then
  [ -z "$NOTES" ] && NOTES="capped"
else
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
        tests:{total:(.total // 0),passed:(.passed // 0),failed:(.failed // 0),
               skipped:(.skipped.count // .skipped // 0)},
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
fi   # end U-16d capped-guard

# Notes: a short human-readable summary of the stage outcome. The Stop-hook
# wiring only passes <stage> <model>, so $5 is virtually always empty — derive a
# note from the same artifact that feeds status/extras (zero-LLM, deterministic).
# An explicit note (when one is ever passed) wins. Stages with no machine-readable
# outcome artifact (planning, plan-audit, documentation, deployment) keep "".
if [ -z "$NOTES" ]; then
  case "$STAGE" in
    implementation)
      if [ "$STATUS" = "pending-smoke" ]; then
        NOTES="smoke result not yet on disk at log time (concurrent Stop hooks)"
      elif [ -f .pipeline/smoke-status.json ]; then
        NOTES="smoke $(jq -r '.status // "unknown"' .pipeline/smoke-status.json 2>/dev/null || echo unknown)"
      fi
      ;;
    security)
      [ -f .pipeline/security-status.json ] && \
        NOTES=$(jq -r '"\(.fixed_count // 0) fixed, \(.critical_count // 0) critical / \(.warning_count // 0) warning remaining"' \
          .pipeline/security-status.json 2>/dev/null || echo "")
      ;;
    testing)
      # U-16g: include a skipped count when present so "160/161 passed" stops hiding a
      # silently-vanished test (feature-3: 161 total / 160 passed / 0 failed / 1 unaccounted).
      [ -f .pipeline/test-results.json ] && \
        NOTES=$(jq -r '
          ([.failures[]? | .name] | map(select(. != null and . != ""))) as $names
          | (.skipped.count // .skipped // 0) as $sk
          | if (.failed // 0) > 0
            then "\(.failed) failed"
                 + (if ($names | length) > 0 then ": " + ($names | join(", ")) else "" end)
            else "\(.passed // 0) passed"
                 + (if $sk > 0 then " / \($sk) skipped" else "" end)
                 + " / \(.total // 0) total" end' \
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
  --arg  branch        "$BRANCH" \
  --arg  stage         "$STAGE" \
  --arg  status        "$STATUS" \
  --arg  model         "$MODEL" \
  --argjson attempt    "$ATTEMPT" \
  --argjson retries    "$RETRIES" \
  --argjson files_changed "$FILES_CHANGED" \
  --arg  notes         "$NOTES" \
  --argjson extras     "$EXTRAS" \
  '{ts:$ts,feature:$feature,branch:$branch,stage:$stage,status:$status,model:$model,attempt:$attempt,
    retries:$retries,files_changed:$files_changed,notes:$notes} + $extras' \
  >> .pipeline/run-log.jsonl

echo "[log-run] $FEATURE / $STAGE / $STATUS (model=$MODEL, files=$FILES_CHANGED)"
