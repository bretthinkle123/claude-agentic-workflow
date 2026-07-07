# Canonical GREEN loop-exit predicate for test-results.json (the harness's own copy
# of the truth). The run-to-condition loop exits GREEN iff security-status is clean
# AND this predicate is true on test-results.json. It MUST stay byte-equivalent to
# the gate's checks (deployment-gate.sh) and the orchestrator's inline jq
# (pipeline-orchestration SKILL.md) — loop-exit-invariant.sh asserts exactly that.
#
# Criteria clause (U-01): when `by_id` is present the summary integers are RECOMPUTED
# from it — every entry must be covered or delegated to "security" (the only valid
# delegate: its own clean/asvs checks are already gate conjuncts), the recorded
# `covered` must equal the count of covered==true entries (never inflated by
# delegation), and `total` must equal the by_id length. Legacy result files without
# `by_id` keep the original integer compare. The cross-FILE anchors (acceptance.md
# frontmatter criteria_total / delegated_criteria) are deploy-only gate checks, like
# waiver authenticity — deliberately NOT here.
.status == "pass"
and ( (.criteria_covered // {}) as $c
      | if ($c.by_id // null) == null
        then (($c.covered // 0) >= ($c.total // 0))
        else (($c.by_id | map(select((.delegated // null) != null and .delegated != "security")) | length) == 0)
         and (($c.by_id | map(select(.covered == true or .delegated == "security")) | length) == ($c.by_id | length))
         and (($c.covered // -1) == ($c.by_id | map(select(.covered == true)) | length))
         and (($c.total // -1) == ($c.by_id | length))
        end )
and ( ((.perf.status // "n/a") == "n/a")
      or ( (.perf.budget.p95_ms == null         or .perf.measured.p95_ms != null)
       and (.perf.budget.throughput_rps == null or .perf.measured.throughput_rps != null)
       and (.perf.scenario != null) ) )
