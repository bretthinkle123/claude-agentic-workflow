---
name: testing-coverage-contract
description: The pipeline's test-strategy + coverage contract (test_strategy/tests_by_type/nested coverage) and how skill preload-vs-on-demand is determined.
metadata:
  type: project
---

As of 2026-06-29, the testing/coverage contract in `.pipeline/test-results.json` is:
`test_strategy` (`pyramid` default | `integration-heavy`), `tests_by_type {unit,
integration, e2e}`, and a **nested** `coverage` object: `combined` (the only gated
figure) plus best-effort per-suite `unit`/`integration`. Planning declares
`test_strategy` in `plan.md` (default `pyramid`; `integration-heavy` only for
orchestration/glue-heavy features, with a one-line rationale); plan-audit flags it
when missing/unjustified; testing reads it as a tier-priority bias. `hourglass`/
`inverted` are deliberately NOT selectable shapes.

Skill **loading mode** is controlled ONLY by an agent's `skills:` frontmatter
(listed = preload; absent = on-demand via the Skill tool). The `SKILL.md` file
carries no self-marker. `scripts/list-skills.sh` prints the classification, and
`--annotate` writes a drift-free generated `<!-- loading: ... -->` breadcrumb into
each skill. Re-run `--annotate` after changing any agent's `skills:` list.

**Why:** these are non-obvious conventions a fresh session would otherwise
re-derive or get wrong (e.g. summing per-suite coverage, or hand-editing
breadcrumbs that then drift from the agent frontmatter).

**How to apply:** edit agents in `global-agents/*.md` (the `.codex/agents` Codex
mirror was deleted 2026-06-29 — Anthropic-only environment, no Codex mirror to keep
in sync); edit project skills in BOTH `global-project-skills/` and `.agents/skills/`.
Gate only on `coverage.combined`; never sum per-suite coverage. See [[project-context]].
