---
name: deployment-checklist-and-rollback
description: Pre-flight gate checks, the commit-then-push-then-PR GitHub handoff sequence, and a pointer to CI for production delivery and rollback.
---

# Deployment checklist and rollback

Your job is to get the reviewed, gate-verified change onto GitHub as a pull
request — **nothing beyond that**. Production delivery (terraform apply, app
deploy, migrations, App Store) runs in CI after the PR is merged.

## Pre-flight — the four gate conditions

`deployment-gate.sh` (a `PreToolUse` hook on your Bash tool) enforces these
before your first command. Confirm them mentally too; if a command is blocked,
**report why — never work around the gate**:

1. **Tests pass** — `.pipeline/test-results.json` `status == "pass"`.
2. **Security clean** — `.pipeline/security-status.json` `status == "clean"`.
3. **Docs produced** — `.pipeline/pr-description.md` exists.
4. **Currency** — the working tree still matches documentation's
   `reviewed_change_hash` in `.pipeline/review-manifest.json`. This is checked on
   the **commit**; once the tree is clean, push/PR pass through.

## Deploy sequence

1. **Commit** — `git add -A && git commit -m "<concise summary from pr-description.md>"`.
   This is the pipeline's single commit, capturing the exact reviewed state.
   First confirm `.pipeline/` is gitignored — if `git status` shows `.pipeline/`
   files staged, stop and report it; they must not be committed.
2. **Push** — `git push` (or `git push -u origin HEAD` if no upstream). This
   **prompts for explicit human approval** — it is intentionally not in the
   allow-list. Wait for approval.
3. **Open PR** — `gh pr create --title "<title>" --body-file .pipeline/pr-description.md`
   (also prompts). Use GitHub MCP instead of `gh` if configured.
4. **Report the PR URL and stop.**

## Rollback

The pipeline never auto-rolls-back production. A post-deploy failure (detected in
CI) surfaces a **manual** rollback decision — investigate first, because a
rollback against a forward-only migration can lose data. The concrete rollback
commands (ECS task-definition revert, Lambda alias, Alembic downgrade, git
revert) live in `pipeline-deployment-targets.md` — pull them when wiring CI.
