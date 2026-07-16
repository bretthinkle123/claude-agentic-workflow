#!/usr/bin/env bash
# next-stage.sh — DETERMINISTIC pipeline transition function (L1).
#
# STATUS: ADVISORY. Wired into the pipeline-orchestration SKILL as the authoritative
# sequencer/context source, but not yet ENFORCED — the orchestrator is instructed to
# consult and obey it; nothing compels it (enforcement is L2). "Which stage runs next"
# is a PURE FUNCTION of .pipeline/* state, computable with zero model judgment, and
# testable exactly like loop-exit-invariant.sh (tests/suites/next-stage.sh).
#
# Contract: reads the .pipeline/ dir in CWD (override with PIPELINE_DIR), prints ONE
# action token to stdout, exits 0. The orchestrator would execute the printed action
# and re-invoke this to advance. Tokens:
#   error:not-bootstrapped                 — no .pipeline/state.json
#   stop:capped                            — circuit breaker terminal (loop-state capped)
#   run:planning | run:plan-audit | run:planning-revision
#   checkpoint:plan                        — waiting on the HUMAN plan-approved marker
#   run:implementation | run:debugging:smoke
#   run:security | run:debugging:<security-conjunct> | run:testing | run:debugging:test
#   mark:loop-completed                    — loop is GREEN; stamp loop-state done
#   run:design-review | run:dast           — advisory conditional stages (opt-in env files)
#   run:documentation
#   checkpoint:diff                        — waiting on the HUMAN diff-approved marker
#   run:deployment
# (The post-deploy CI-watch/merge phase is deliberately NOT modeled here — it depends on
#  REMOTE CI state, not local .pipeline/ files; that tail stays L2/human, see SKILL 6c.)
#
# TWO LEVERS this shows:
#   (a) WHEN to start an agent  — the cascade below (pure function of file existence +
#       the same jq predicates the deploy gate uses).
#   (b) WHAT context to pass    — sec_conjunct() computes the debugging prompt's payload
#       deterministically from state (which security conjunct failed), instead of an LLM
#       summarizing it. A full L1 would template every stage prompt the same way.
#
# DRIFT SAFETY: the GREEN decision reuses the canonical predicates verbatim — the test
# predicate via global-hooks/loop-exit-predicate.jq, and the security predicate as the
# SEC_PRED string byte-shared with deployment-gate.sh / SKILL / loop-exit-invariant.sh.
# tests/suites/next-stage.sh pins both, so a drift breaks the suite (same guarantee the
# loop-exit≡gate invariant already gives).
set -uo pipefail

P="${PIPELINE_DIR:-.pipeline}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Canonical test-results GREEN predicate (single source of truth on disk). It lives in
# global-hooks/ alongside this hook, so it PUBLISHES to ~/.claude/hooks/ with install-global
# and resolves at runtime — the tests/ dir is NOT published (F1: a tests/-relative default
# broke every live run by mis-routing green states to debugging).
TEST_PRED="${LOOP_EXIT_PREDICATE:-$HERE/loop-exit-predicate.jq}"
# Canonical security GREEN predicate — MUST stay byte-identical to deployment-gate.sh,
# the SKILL, and loop-exit-invariant.sh's SEC_PREDICATE (next-stage.sh test pins it).
SEC_PRED='.status=="clean" and ((.osv_max_cvss // 0) < 7 or (.osv_waiver // null) != null) and ((.input_surface.uncontrolled // []) | length == 0) and ((.data_surface.unprotected // []) | length == 0) and (.asvs.reconciled != false) and (.scan_reconciled != false)'

emit() { printf '%s\n' "$1"; exit 0; }
f()    { [ -f "$P/$1" ]; }                                   # file exists
jstat(){ jq -r "$1 // empty" "$P/$2" 2>/dev/null; }          # read a JSON field
fm()   { grep -m1 -E "^$1:" "$P/$2" 2>/dev/null | sed -E "s/^$1:[[:space:]]*//"; }  # read a frontmatter key

# Current change-set hash (what the tree looks like NOW). Injectable for tests; else
# computed the same way the gate + approve-diff.sh do, so "stale gate status" is detectable.
CHANGE_HASH="${PIPELINE_CHANGE_HASH:-}"
if [ -z "$CHANGE_HASH" ] && [ -x "$HERE/compute-change-hash.sh" ]; then
  CHANGE_HASH="$(bash "$HERE/compute-change-hash.sh" 2>/dev/null || true)"
fi
# A gate-status file is STALE when it records the hash it was computed over and that hash
# no longer matches the tree (so debugging's edits force a re-scan/re-test). If the file
# omits the hash field, treat it as fresh-if-present (backward compatible: the security
# contract now specifies scanned_change_hash, but older artifacts/fixtures may lack it).
stale() { # <recorded-hash>
  [ -n "$1" ] && [ -n "$CHANGE_HASH" ] && [ "$1" != "$CHANGE_HASH" ]
}

# Which security GREEN conjunct is failing — the deterministic debugging-prompt payload.
sec_conjunct() {
  jq -r '
    if .status != "clean" then "status-\(.status)"
    elif ((.osv_max_cvss // 0) >= 7 and (.osv_waiver // null) == null) then "cve-cvss-\(.osv_max_cvss)"
    elif (((.input_surface.uncontrolled // []) | length) > 0) then "input-surface"
    elif (((.data_surface.unprotected // []) | length) > 0) then "data-surface"
    elif (.asvs.reconciled == false) then "asvs-unreconciled"
    elif (.scan_reconciled == false) then "scan-unreconciled"
    else "unknown" end' "$P/security-status.json" 2>/dev/null
}

# ── the cascade — first match wins ────────────────────────────────────────────────
# 0. must be bootstrapped
f state.json || emit "error:not-bootstrapped"

# 1. circuit-breaker terminal (a cap-out beats everything: stop + escalate to human)
[ "$(jstat '.status' loop-state.json)" = "capped" ] && emit "stop:capped"

# 2. planning → plan-audit → (one-shot revision) → human plan checkpoint
f plan.md       || emit "run:planning"
f plan-audit.md || emit "run:plan-audit"
if [ "$(fm revision_recommended plan-audit.md)" = "true" ] && ! grep -q '## Revision notes' "$P/plan.md" 2>/dev/null; then
  emit "run:planning-revision"
fi
f plan-approved || emit "checkpoint:plan"

# 3. implementation + smoke sanity
f smoke-status.json                       || emit "run:implementation"
[ "$(jstat '.status' smoke-status.json)" = "fail" ] && emit "run:debugging:smoke"

# 4. run-to-condition loop (security ⇄ debugging ⇄ testing) — deterministic routing.
#    Ordering falls out of freshness: after debugging edits code the hash changes, so the
#    prior security/test verdicts go STALE and re-run in order (security first), which is
#    exactly the SKILL's "remediation re-runs BOTH gates".
f security-status.json               || emit "run:security"
stale "$(jstat '.scanned_change_hash' security-status.json)" && emit "run:security"
jq -e "$SEC_PRED" "$P/security-status.json" >/dev/null 2>&1 || emit "run:debugging:security:$(sec_conjunct)"

f test-results.json                  || emit "run:testing"
stale "$(jstat '.tested_change_hash' test-results.json)" && emit "run:testing"
jq -e -f "$TEST_PRED" "$P/test-results.json" >/dev/null 2>&1 || emit "run:debugging:test"

# 5. loop is GREEN — stamp completion (bookkeeping the driver owns, also deterministic)
if f loop-state.json && [ "$(jstat '.status' loop-state.json)" != "completed" ]; then
  emit "mark:loop-completed"
fi

# 6. advisory conditional stages — run iff the project opted in (env file present) and the
#    artifact isn't produced yet. Pure file-existence triggers; never gate (SKILL 4d/4e).
f ui.env   && ! f design-review.json && emit "run:design-review"
f dast.env && ! f dast-review.json   && emit "run:dast"

# 7. documentation → human diff checkpoint → deployment
f pr-description.md || emit "run:documentation"
f diff-approved     || emit "checkpoint:diff"
emit "run:deployment"
