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

- Suites run, pass/fail summary, and coverage (lines / branches / functions)
  from `.pipeline/test-results.json`.

## Security

- Scope (diff/full) and finding counts from `.pipeline/security-report.md`.

## Threat model

- Reference the `## Threat Model` section of `.pipeline/plan.md`; call out any
  High-severity threat and its mitigation.
