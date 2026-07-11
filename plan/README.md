# plan/ — the committed plan archive

Three directories, one rule each:

- **`plan/` (this directory, tracked)** — the committed plan archive: one-shot PR plans, run
  plans, audits, and design logs that have shipped or been published as part of a PR. Historical
  by nature — these files record *why* something was built the way it was; the living reference is
  `system_architecture.md`, the shipped record is `docs/pipeline-changelog.md` +
  `docs/pr-history.md`, and open work is `docs/roadmap.md`. Executed run plans live under
  `plan/eval/`.
- **`plans/` (gitignored)** — where new plans, analyses, and scratch `.md` files are written.
  Private by default (this is a public repo); promote a draft into `plan/` when a PR publishes it.
- **`docs/`** — curated, living documentation only, placed there by the operator. Never write new
  plans to `docs/` or the repo root.
