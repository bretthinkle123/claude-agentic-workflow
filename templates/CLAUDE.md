<!--
  TEMPLATE — copy this file to the ROOT of each test/real project as `CLAUDE.md`,
  then fill in every <placeholder>. Every pipeline agent reads CLAUDE.md first;
  without it they infer conventions (and the smoke check has nothing to probe).
  For a brand-new (greenfield) project, write a PROJECT.md spec instead/as well —
  planning reads PROJECT.md as the source of requirements when there's no code yet.
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
- Deploy: `<command, or "CI on merge — see pipeline-deployment-targets.md">`

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
