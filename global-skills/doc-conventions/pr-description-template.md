# <Concise change title>

> PR-description template → written to `.pipeline/pr-description.md`.
> The deployment gate requires this file to exist.

## Summary

One paragraph: what changed and why. Link the plan: see `.pipeline/plan.md`
(includes the STRIDE threat model).

## Changes

- <Layer / area>: <what changed, one line each>

## Decisions & tradeoffs

- <Any non-obvious decision the reviewer should know, with the why>

## Testing

- Suites run and pass/fail summary from `.pipeline/test-results.json`.
- Combined coverage (lines / **branches** / functions) — call out the branch figure
  explicitly; note per-suite unit vs. integration when recorded.
- Test-pyramid shape: the `test_strategy` followed and the realized
  `tests_by_type` (unit / integration / e2e) counts.
- **Test quality** (advisory, from `.pipeline/test-quality.json` when present):
  mutation score over the changed core modules and the notable adversarial gaps
  (`what the tests do not catch`). Surface it for the reviewer; it does not gate.

## Security

- Scope (diff/full) and finding counts from `.pipeline/security-report.md`.

## Threat model

- Reference the `## Threat Model` section of `.pipeline/plan.md`; call out any
  High-severity threat and its mitigation.
