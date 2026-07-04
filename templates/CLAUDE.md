<!--
  TEMPLATE — copy this file to the ROOT of each test/real project as `CLAUDE.md`,
  then fill in every <placeholder>. Every pipeline agent reads CLAUDE.md first;
  without it they infer conventions (and the smoke check has nothing to probe).
  For a brand-new (greenfield) project, write a PROJECT.md spec instead/as well —
  planning reads PROJECT.md as the source of requirements when there's no code yet
  (bootstrap-project.sh writes a PROJECT.md stub, incl. a Design source line).

  FRONT-END FROM A DESIGN? If you have a Claude Design export, a Figma export, or
  reference screenshots, drop them in a `design/` folder at the repo root and add a
  `Design source:` line under ## Frontend design source below (or in PROJECT.md).
  That triggers the design-spec stage, which normalizes the design into a
  human-approved `.pipeline/design-spec.md` and makes planning REPLICATE it (as
  close to 1:1 as the platform allows) instead of designing the UI from scratch.
  No `design/` and no `Design source:` line ⇒ the stage is skipped entirely.
-->

# <Project name>

## Stack
- Cloud environment: <AWS by default (infra); planning may recommend another and flags it at the checkpoint>
- Language/runtime: <Python 3.12 backend / Node 22 frontend by default>
- Framework(s): <e.g. FastAPI (backend), React (frontend)>
- Data stores: <e.g. PostgreSQL, Redis>
- Migration tool: <e.g. Alembic (Python), Knex/Prisma (JS)>
- Cloud / IaC: <e.g. AWS + Terraform, or "none — app only">
- Auth provider: <Firebase Auth by default (cloud-agnostic SaaS — no GCP infra); Amazon Cognito is the AWS-native alternative, or "none">
- Observability: <CloudWatch + X-Ray (AWS) + Sentry by default>
- Packaging / runtime: <direct process by default; container (Docker) or serverless only if justified — see containerization-conventions>

## How to run / build / test
- Start: `<e.g. python -m uvicorn src.main:app --port 8000>` (smoke check expects HTTP 200 at `<http://localhost:8000/health>`)
- Test:  `<e.g. pytest --cov=src>` with coverage via `<flag>`
- Migrate: `<e.g. alembic upgrade head>` (run before deploying; also run locally after pulling schema changes)
- Deploy: `<command, or "CI on merge — see docs/pipeline-deployment-targets.md">`

## Frontend design source
<!-- OPTIONAL — delete this whole section if the project has no provided UI design.
     Fill it in to drive the front end from a design instead of designing it from scratch. -->
- Design source: <e.g. "see design/ (Claude Design export)" | "see design/ (Figma export)" |
  "see design/screens/ (reference screenshots)" | "Figma MCP (file <KEY>)" | "none">
- Target: <web (default) | native iOS (SwiftUI) — also record under ## Stack notes>
- Notes: <anything the design leaves ambiguous; the design-spec stage will flag the rest>
<!-- Presence of a `design/` folder OR a non-"none" Design source line triggers the
     design-spec stage → human-approved .pipeline/design-spec.md → planning replicates it. -->

## Conventions
- <naming, error handling, module boundaries beyond the code-standards defaults>
- Test locations: <e.g. tests/ as test_*.py (Python), alongside source as *.test.js (JS)>

## What "done" means
- Smoke check passes, security report clean, tests pass at >= <N>% coverage,
  docs updated for touched directories, PR description written.

<!--
  REMEMBER per project: the smoke-check.sh hook reads Start/health values above.
  Set them here, or export SMOKE_START_CMD / SMOKE_HEALTH_URL, or (frontend-only)
  swap in the build-check variant of smoke-check.sh from the spec.
-->
