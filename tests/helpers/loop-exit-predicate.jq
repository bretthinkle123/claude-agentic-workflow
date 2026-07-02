# Canonical GREEN loop-exit predicate for test-results.json (the harness's own copy
# of the truth). The run-to-condition loop exits GREEN iff security-status is clean
# AND this predicate is true on test-results.json. It MUST stay byte-equivalent to
# the gate's checks (deployment-gate.sh) and the orchestrator's inline jq
# (pipeline-orchestration SKILL.md) — loop-exit-invariant.sh asserts exactly that.
.status == "pass"
and ((.criteria_covered.covered // 0) >= (.criteria_covered.total // 0))
and ( ((.perf.status // "n/a") == "n/a")
      or ( (.perf.budget.p95_ms == null         or .perf.measured.p95_ms != null)
       and (.perf.budget.throughput_rps == null or .perf.measured.throughput_rps != null)
       and (.perf.scenario != null) ) )
