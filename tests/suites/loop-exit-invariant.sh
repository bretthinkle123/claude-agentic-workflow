#!/usr/bin/env bash
# loop-exit-invariant.sh — the no-drift guard between the orchestrator's GREEN
# condition and deployment-gate.sh. The loop must never exit GREEN on a state the
# gate would then reject (deadlock before deploy), so the two must be equivalent.
#
# There are THREE copies of the GREEN predicate that must agree:
#   1. deployment-gate.sh          (bash + jq — the deploy gate)
#   2. pipeline-orchestration/SKILL.md  (inline jq — what the human orchestrator runs)
#   3. loop-exit-predicate.jq      (this harness's canonical copy)
# This suite pins all three together, transitively:
#   (a) gate ⟺ canonical  — run deployment-gate.sh over a fixture matrix and assert
#       its verdict matches (security-clean AND canonical predicate).
#   (b) canonical ⟺ SKILL — EXTRACT the SKILL's own jq predicates (not a substring
#       grep) and assert they produce byte-identical verdicts to the canonical over
#       an exhaustive battery of boundary inputs.
# (a) ∧ (b) ⟹ gate ⟺ SKILL. A drift in ANY clause of the SKILL predicate — not just
# the perf fragments — now breaks this suite.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../helpers/assert.sh"

GATE="$HOOKS/deployment-gate.sh"
SKILL="$REPO_ROOT/global-skills/pipeline-orchestration/SKILL.md"
echo "-- loop-exit ≡ gate --"

# --- (a) gate ⟺ canonical over a fixture matrix -----------------------------------

# Evaluate the harness's canonical GREEN predicate for a given workdir.
# GREEN := security-status.status=="clean" AND loop-exit-predicate(test-results)==true
# GREEN security predicate (audit B6): clean AND no High/Critical OSV without a waiver.
# Kept byte-equivalent to deployment-gate.sh's CVE floor and the SKILL's security jq.
SEC_PREDICATE='.status=="clean" and ((.osv_max_cvss // 0) < 7 or (.osv_waiver // null) != null)'

pred_green() {
  local w="$1"
  if jq -e "$SEC_PREDICATE" "$w/.pipeline/security-status.json" >/dev/null 2>&1; then :; else echo no; return; fi
  if jq -e -f "$LOOP_EXIT_PREDICATE" "$w/.pipeline/test-results.json" >/dev/null 2>&1; then echo yes; else echo no; fi
}

# One matrix row: apply a test-results mutation ('' = none) and/or a security
# mutation, then assert gate verdict == predicate verdict.
row() {
  local desc="$1" tmut="${2:-}" smut="${3:-}"
  local w; w="$(mk_fixture)"
  [ -n "$tmut" ] && jq_edit "$w/.pipeline/test-results.json" "$tmut"
  [ -n "$smut" ] && jq_edit "$w/.pipeline/security-status.json" "$smut"

  ( cd "$w" && bash "$GATE" ) >/dev/null 2>&1
  local rc=$?
  local gate_pass="no"; [ "$rc" -eq 0 ] && gate_pass="yes"
  local pred_pass; pred_pass="$(pred_green "$w")"
  assert_eq "$pred_pass" "$gate_pass" "gate ⟺ loop-exit: $desc (pred=$pred_pass gate=$gate_pass)"
}

row "green (all pass)"                       ''                                          ''
row "tests fail"                             '.status="fail"'                            ''
row "criteria incomplete"                    '.criteria_covered.covered=(.criteria_covered.total-1)' ''
row "perf F1 (measured p95 null)"            '.perf.measured.p95_ms=null'                ''
row "perf F1 (measured tput null)"           '.perf.measured.throughput_rps=null'        ''
row "perf n/a short-circuit"                 '.perf.status="n/a" | .perf.measured.throughput_rps=null' ''
row "perf ran, scenario null (WS3-3)"        '.perf.scenario=null'                       ''
row "perf n/a, scenario null → ok"           '.perf.status="n/a" | .perf.scenario=null'  ''
row "security not clean"                     ''                                          '.status="issues-found"'
row "clean + High CVE, no waiver (B6)"        ''                                          '.osv_max_cvss=7.5'
row "clean + High CVE, waived (B6)"           ''                                          '.osv_max_cvss=7.5 | .osv_waiver={id:"GHSA-x",reason:"dev-only",approved_by:"human"}'
row "clean + below floor (B6)"                ''                                          '.osv_max_cvss=6.9'

# --- (b) canonical ⟺ SKILL: extract the SKILL's real predicates and compare ---------
#
# extract_skill_pred <marker> — pull the jq PROGRAM out of the `jq -e '<program>'
# <marker>` command the SKILL documents (multi-line safe). Captures the block that
# starts at a `jq -e '` line and ends on the line carrying <marker>; abandons a block
# that terminates on a different *.json (so the security predicate isn't mistaken for
# the test one). Emits the raw command block; the caller strips the jq wrapper.
extract_skill_pred() {
  awk -v marker="$1" '
    index($0, "jq -e '\''") > 0 { cap=1; buf="" }
    cap==1 {
      buf = (buf=="" ? $0 : buf "\n" $0)
      if (index($0, marker) > 0) { print buf; exit }
      else if (index($0, ".json") > 0) { cap=0 }
    }
  ' "$SKILL"
}

TMP="$(mktemp -d)"; _WORKDIRS+=("$TMP")

# test-results GREEN predicate: strip `...jq -e '` prefix and `' test-results.json` suffix.
raw_test="$(extract_skill_pred test-results.json)"
skill_test="${raw_test#*jq -e \'}"; skill_test="${skill_test%\'*}"
# security GREEN predicate.
raw_sec="$(extract_skill_pred security-status.json)"
skill_sec="${raw_sec#*jq -e \'}"; skill_sec="${skill_sec%\'*}"

if [ -n "$skill_test" ] && [ "$skill_test" != "$raw_test" ]; then
  _ok "extracted the SKILL's test-results GREEN predicate"
else
  _no "could not extract the SKILL's test-results GREEN predicate (SKILL structure changed?)"
fi
if [ -n "$skill_sec" ] && [ "$skill_sec" != "$raw_sec" ]; then
  _ok "extracted the SKILL's security GREEN predicate"
else
  _no "could not extract the SKILL's security GREEN predicate (SKILL structure changed?)"
fi

printf '%s\n' "$skill_test" > "$TMP/skill-test.jq"
printf '%s\n' "$skill_sec"  > "$TMP/skill-sec.jq"

# Exhaustive boundary battery for the test-results predicate: every combination of
# status, the three criteria orderings (<, ==, >), perf mode, each perf budget/measured
# null-vs-set pairing, and perf.scenario present-vs-null (audit WS3-3) — 384 inputs. The
# SKILL predicate and the canonical predicate must agree on every one.
jq -nc '
  ["pass","fail"][] as $s
  | ({c:1,t:2},{c:2,t:2},{c:3,t:2}) as $cr
  | ("n/a","measured") as $ps
  | (null,100) as $bp | (null,90) as $mp
  | (null,50)  as $bt | (null,45) as $mt
  | (null,{concurrency:50}) as $sc
  | {status:$s,
     criteria_covered:{covered:$cr.c,total:$cr.t},
     perf:{status:$ps,
           budget:{p95_ms:$bp,throughput_rps:$bt},
           measured:{p95_ms:$mp,throughput_rps:$mt},
           scenario:$sc}}
' > "$TMP/battery.jsonl"

n_test="$(grep -c '' "$TMP/battery.jsonl")"
jq -c -f "$LOOP_EXIT_PREDICATE" "$TMP/battery.jsonl" > "$TMP/canon.out" 2>/dev/null
jq -c -f "$TMP/skill-test.jq"   "$TMP/battery.jsonl" > "$TMP/skill.out" 2>/dev/null
if [ -s "$TMP/canon.out" ] && diff -q "$TMP/canon.out" "$TMP/skill.out" >/dev/null 2>&1; then
  _ok "SKILL test-predicate ≡ canonical across $n_test boundary permutations"
else
  _no "SKILL test-predicate DIVERGES from canonical — loop-exit ≠ gate. Reconcile SKILL.md with $LOOP_EXIT_PREDICATE"
fi

# The security predicate must not silently drift. Battery covers status variants AND the
# B6 CVE floor (max-cvss above/below/at 7.0, with and without a waiver). The reference is
# SEC_PREDICATE (byte-shared with pred_green + the gate + the SKILL).
{
  printf '{"status":"clean"}\n{"status":"issues-found"}\n{"status":"pending"}\n{}\n'
  printf '{"status":"clean","osv_max_cvss":6.9}\n{"status":"clean","osv_max_cvss":7}\n'
  printf '{"status":"clean","osv_max_cvss":7.5}\n'
  printf '{"status":"clean","osv_max_cvss":7.5,"osv_waiver":{"id":"x"}}\n'
  printf '{"status":"issues-found","osv_max_cvss":7.5}\n'
} > "$TMP/sec.jsonl"
jq -c -f "$TMP/skill-sec.jq" "$TMP/sec.jsonl" > "$TMP/sec-skill.out" 2>/dev/null
jq -c "$SEC_PREDICATE"       "$TMP/sec.jsonl" > "$TMP/sec-ref.out"   2>/dev/null
if [ -s "$TMP/sec-ref.out" ] && diff -q "$TMP/sec-ref.out" "$TMP/sec-skill.out" >/dev/null 2>&1; then
  _ok "SKILL security-predicate ≡ SEC_PREDICATE (status + B6 CVE floor)"
else
  _no "SKILL security-predicate diverges from the gate's CVE floor — loop-exit ≠ gate. Reconcile SKILL.md security jq with deployment-gate.sh"
fi

finish loop-exit-invariant
