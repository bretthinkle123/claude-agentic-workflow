# M3-series fixtures (runs 1–3, Meterly validation)

Preserved 2026-07-07 from `meterly-pipeline-test/.pipeline/` (gitignored,
session-fragile) per unified plan v2.1 pre-flight step 0. These are the golden inputs
for U-01/U-03/U-09/U-14/U-16/U-23 acceptance tests.

## Layout

- `run3-pipeline/` — the `.pipeline/` directory as it stood after run 3
  (feature/usage-dashboard) completed design-spec-through-review. NOTE: most JSON
  artifacts are run 3's; the scanner outputs are deliberately the **stale** ones that
  prove the U-09 evidence-class (`semgrep.json` = run 2's @ 2026-07-06T23:03Z,
  `osv.json` = run 1's @ 19:10Z, `checkov.json`/`trivy-config.json` = run 1's @
  18:4xZ, `gitleaks.json` = run 3's @ 2026-07-07T03:35Z). `run-log.jsonl` contains all
  three runs' lines.
- `decisions/main/` — run 1's archived planning set (plan, acceptance, plan-audit,
  security-report, run-summary). No test-results.json was ever archived.
- `decisions/feature/usage-dashboard/` — run 3's archived set incl. design-spec.md.
- `reconstructed/` — artifacts whose original bytes were overwritten before
  preservation, rebuilt from this audit's verified full reads (provenance in each
  file). Run 2 has NO archive (it was never deployed; `docs/decisions/` archiving
  happens at deployment).

## Known-lost originals

- Run 1 + run 2 `test-results.json` (overwritten in place by later runs) —
  `reconstructed/r1-test-results.json` carries the gate-relevant fields verbatim from
  the audit session's full Read (2026-07-06): the 24/24-vs-AC20-false criteria block,
  perf block, status.
- Run 2 `plan.md` (overwritten by run 3's) — `reconstructed/r2-plan-provable-claim.md`
  preserves the verified line-186 claim for the U-03 proof-claim replay.
- Run 1/run 2 per-pass `security-report.md` (overwritten per pass — the exact defect
  U-09's archiving fixes).
