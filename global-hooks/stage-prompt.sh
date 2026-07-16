#!/usr/bin/env bash
# stage-prompt.sh — DETERMINISTIC prompt/context registry (L1 PROTOTYPE, lever b).
#
# Pairs with next-stage.sh: that says WHICH stage runs next; this says WITH WHAT CONTEXT.
# Given an action token (as next-stage.sh emits), it prints the exact invocation the
# orchestrator performs — the agent name + a prompt string whose variable slots are
# filled from .pipeline/* by jq, NOT paraphrased by a model. So the prompt a stage
# receives is a reproducible pure function of state.
#
# STATUS: ADVISORY. Wired into the SKILL as the context source but not yet ENFORCED (L2).
# Codifies the SKILL's prompt strings so "prompts are for experiments, definitions are for
# keeps" (SKILL U-12) applies to the orchestrator's own prompts.
#
# Output (stdout):
#   for an agent stage:   AGENT=<name>\nPROMPT=<one-line prompt>
#   for a non-agent step: DIRECTIVE=<what the orchestrator/human does>
#
# The debugging payloads are the showcase: run:debugging:security:cve-cvss-7.5 pulls the
# actual CVSS + report path from security-status.json; input/data/asvs pull the offending
# lists — the failing conjunct's specifics, computed, never summarized.
set -uo pipefail

P="${PIPELINE_DIR:-.pipeline}"
ACTION="${1:-}"
[ -n "$ACTION" ] || { echo "usage: stage-prompt.sh <action-token>" >&2; exit 2; }

j()     { jq -r "$1 // empty" "$P/$2" 2>/dev/null; }
jlist() { jq -r "(($1) // []) | join(\", \")" "$P/$2" 2>/dev/null; }   # array → compact one-line "a, b"
SLUG="$(j '.feature' state.json)"; SLUG="${SLUG:-<feature>}"

agent()     { printf 'AGENT=%s\n' "$1"; }
prompt()    { printf 'PROMPT=%s\n' "$1"; }
directive() { printf 'DIRECTIVE=%s\n' "$1"; exit 0; }

case "$ACTION" in
  run:planning)          agent planning;     prompt "Plan $SLUG. Write .pipeline/plan.md (incl. STRIDE threat model) + .pipeline/acceptance.md." ;;
  run:plan-audit)        agent plan-audit;   prompt "Audit .pipeline/plan.md (completeness + deps). Write .pipeline/plan-audit.md." ;;
  run:planning-revision) agent planning;     prompt "Revise .pipeline/plan.md: address every [material] flag in .pipeline/plan-audit.md, append ## Revision notes." ;;
  run:implementation)    agent implementation; prompt "Implement .pipeline/plan.md.$( [ -f "$P/tasks.md" ] && printf ' Execute .pipeline/tasks.md per-task in dependency order; do the next task ONLY, then stop cleanly.' )" ;;
  run:security)          agent security;     prompt "Scan per diff-scoping-conventions. Write security-report.md + security-status.json (incl. scanned_change_hash)." ;;
  run:testing)           agent testing;      prompt "Add missing tests, run suite. Write test-results.json (criteria_covered + tested_change_hash)." ;;
  run:documentation)     agent documentation; prompt "Update docs for the diff. Write pr-description.md + review-manifest.json." ;;
  run:deployment)        agent deployment;   prompt "Commit the reviewed change and open a PR on GitHub." ;;

  run:debugging:smoke)
    agent debugging
    prompt "Smoke check failed after implementation (.pipeline/smoke-status.json). Root-cause and fix; the app must boot clean and the suite stay green."
    ;;
  run:debugging:test)
    agent debugging
    # Which half of the test predicate failed — computed from test-results.json.
    payload="$(jq -r '
      if (.status == "fail") then "Failing test(s): " + (((.failures // []) | map(.name)) | join(", ") | if . == "" then "see test-results.json" else . end) + ". Fix the CODE, not the test."
      elif ((.criteria_covered.by_id // null) != null
            and (((.criteria_covered.by_id | map(select(.covered != true and (.delegated // "") != "security"))) | length) > 0))
        then "Acceptance criteria not covered: " + ([.criteria_covered.by_id[] | select(.covered != true and (.delegated // "") != "security") | .id] | join(", ")) + ". Cover them."
      elif ((.perf.status // "n/a") != "n/a"
            and ((.perf.budget.p95_ms != null and .perf.measured.p95_ms == null)
              or (.perf.budget.throughput_rps != null and .perf.measured.throughput_rps == null)
              or (.perf.scenario == null)))
        then "Declared perf budget was not fully measured (a budget dimension or scenario is null). Measure it or mark the criterion uncovered."
      else "test-results.json is not GREEN — see the failing clause." end' "$P/test-results.json" 2>/dev/null)"
    prompt "${payload:-test-results.json is not GREEN — inspect it.}"
    ;;
  run:debugging:security:*)
    agent debugging
    conj="${ACTION#run:debugging:security:}"
    case "$conj" in
      status-*)   payload="Security reported status='${conj#status-}' (critical_count>0). Fix the critical findings in .pipeline/security-report.md." ;;
      cve-cvss-*) payload="An OSV dependency finding at CVSS ${conj#cve-cvss-} (>=7 High/Critical) remains with no recorded waiver. Patch the dependency (see .pipeline/security-report.md) or route a human waiver via record-waiver.sh." ;;
      input-surface)   payload="Input source(s) shipped without a validation contract + rate-limit: $(jlist '.input_surface.uncontrolled' security-status.json). Add the control (api-edge-conventions) or record a waiver." ;;
      data-surface)    payload="Sensitive stored field(s) with no at-rest mechanism: $(jlist '.data_surface.unprotected' security-status.json). Add field-level protection (data-protection-conventions) or a data_protection_waiver." ;;
      asvs-unreconciled) payload="Unmet ASVS requirement(s): L1/L2 [$(jlist '.asvs.l1_l2_missing' security-status.json)], in-scope L3 [$(jlist '.asvs.l3_in_scope_missing' security-status.json)]. Meet them or record a human waiver." ;;
      scan-unreconciled) payload="A per-tool scan count does not match its artifact recomputation (.pipeline/scan-reconciliation.json). Re-run the scanner through its wrapper and re-count." ;;
      *)          payload="Security GREEN predicate failed (conjunct: $conj). See .pipeline/security-status.json." ;;
    esac
    prompt "$payload"
    ;;

  run:design-review) directive "Advisory FE stage: run ui-capture.sh then design-review-check.sh (no agent). Surfaces over-budget screens/a11y in the PR; never gates." ;;
  run:dast)          directive "Advisory DAST stage: run dast-capture.sh then dast-review.sh (no agent). Passive baseline; surfaces over-budget severities; never gates." ;;

  checkpoint:plan)   directive "HUMAN checkpoint: review plan.md + plan-audit.md; page via notify-checkpoint.sh plan; the human runs approve-plan.sh (TTY). Pipeline waits — do not proceed until plan-approved exists." ;;
  checkpoint:diff)   directive "HUMAN checkpoint: run /code-review (review-only), present the diff + findings + security/test reports; page via notify-checkpoint.sh diff; the human runs approve-diff.sh (TTY). Wait until diff-approved exists." ;;
  mark:loop-completed) directive "Loop GREEN: run loop-guard.sh done, then run-summary.sh — stamp completion before documentation." ;;
  stop:capped)       directive "Circuit-breaker CAP: stop the loop, page notify-checkpoint.sh capped, escalate to the human. Never auto-clear loop-state." ;;
  error:not-bootstrapped) directive "No .pipeline/state.json — run bootstrap-project.sh in the target repo first." ;;

  *) echo "stage-prompt: unknown action '$ACTION'" >&2; exit 2 ;;
esac
