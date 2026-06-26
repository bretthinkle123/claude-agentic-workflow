---
name: test-conventions
description: Project test layout, mocking strategy, unit-vs-integration boundary, runner and coverage commands, and coverage thresholds.
---

# Test conventions (project template)

> **Project-scoped template.** Fill every `<PLACEHOLDER>` for this project, then
> commit. The pipeline's testing agent preloads this file.

## File locations & naming

- Unit tests: `<e.g. tests/ as test_*.py (Python) | alongside source as *.test.js (JS)>`
- Integration tests: `<e.g. tests/integration/>`
- E2E / UI specs (frontend only): `<e.g. e2e/ as *.spec.ts (Playwright)>`

## Unit vs integration

- **Unit** — one function/module in isolation, dependencies mocked. One test
  file per module.
- **Integration** — interactions across components (API → service → DB). Use
  real or containerized dependencies where supported: `<describe what's available, e.g. testcontainers Postgres>`.
- **E2E** — author Playwright specs by **reading the frontend code** to derive
  routes/selectors; the runner executes them deterministically. Do **not** drive
  a live browser via MCP to discover selectors (snapshots are token-heavy).

## Mocking strategy

- `<e.g. pytest monkeypatch / unittest.mock for Python; jest.mock for JS>`
- Mock at the boundary you own (the repository/client interface), not deep
  internals. Never mock the unit under test.

## Runner & coverage

- Run: `<e.g. pytest --cov=src --cov-report=term-missing>`
- Coverage flag: `<e.g. --cov / --coverage>`
- Thresholds: lines `>= <N>%`, branches `>= <N>%`, functions `>= <N>%`.

## Results contract

Write `.pipeline/test-results.json` with: `status` (`pass`/`fail`), `ran_at`,
`scope` (`diff`/`full`), `since_commit`, `tested_change_hash` (see
`diff-scoping-conventions`), `total`/`passed`/`failed`, `failures[]`, and
`coverage { lines, branches, functions }`.
