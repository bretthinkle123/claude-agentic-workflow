---
name: agentic-pipeline-project
description: "Brett's Claude Code multi-agent SDLC pipeline — architecture, settled decisions, and current build status"
metadata:
  type: project
---

Brett is building a reusable Claude Code multi-agent SDLC pipeline. All authoritative files are in the repo at `c:\Users\brett\OneDrive\Documents\GitHub\claude-agentic-workflow\`.

**All four spec/companion files are in the repo (not in Downloads or anywhere else):**
- `agentic-pipeline-plan.md` — the main spec (~2600 lines). Read this for the full design.
- `pipeline-alternatives.md` — non-default scaffolds (Cognito, GCP observability, JS backend, Go/Java). Documentation-only; never loaded at runtime.
- `pipeline-deployment-targets.md` — CI/CD patterns after the pipeline ends at a PR (GitHub Actions, ECS, Lambda, Alembic, App Store, Google Play, rollback). Documentation-only.
- `pipeline-mcp-config.md` — per-agent MCP server mapping + §7 token-vs-performance verdict table. Documentation-only.

**Architecture (settled — do not relitigate):**
- 7 subagents: planning, implementation, debugging, security, testing, documentation, deployment.
- File-based handoff via `.pipeline/*` artifacts (subagents start blank; state passes through files only).
- Deterministic shell-hook gates: `smoke-check.sh` (implementation Stop), `record-clean.sh` (testing Stop), `deployment-gate.sh` (deployment PreToolUse).
- Human checkpoint: `.pipeline/plan-approved` marker; implementation refuses to start without it.
- Diff-scoping: working tree vs last commit (`git diff HEAD --name-only` + `git ls-files --others --exclude-standard`). No `last_clean_commit` pointer.
- Deployment agent makes the pipeline's ONLY commit (as its first step, after gate passes).
- Currency anchor is documentation's `reviewed_change_hash` (in `.pipeline/review-manifest.json`, hashed over the post-documentation tree), NOT testing's `tested_change_hash`. The deploy gate enforces currency on the commit only; once the tree is clean it lets push/PR through. (Settled in the second audit — documentation writes docs after testing, so testing's hash is the wrong reference.)

**Key settled decisions:**
- Defaults: AWS (cloud/infra) + Firebase Auth (default, cloud-agnostic) + Python backend + JS frontend. ONE documented runtime path.
- Non-defaults (Cognito, GCP, JS backend, Go/Java) live in `pipeline-alternatives.md` — zero runtime tokens.
- Skills: 13 total (down from 16). 8 preloaded (1–2 per agent), 5 on-demand. 11 global (`~/.claude/skills/`), 2 project-scoped templates (`.claude/skills/` in repo: `test-conventions`, `semgrep-ruleset-guide`).
- MCP: per-agent `tools:` scoping. SAST stays a shell hook. Context7/GitHub/AWS Knowledge/Terraform/Sentry are default-on; Firebase and Playwright are opt-in.
- Deployment agent scope: commit + push + open PR only. No `terraform apply`, no DB migrations, no app deploy.

**Current build status (as of 2026-06-25, second audit):**
- DESIGN phase complete. A deeper readiness audit found 3 real blockers — all now fixed in the spec:
  1. **Deployment-gate currency was unsatisfiable.** It anchored to testing's `tested_change_hash`, but documentation writes README/architecture files AFTER testing, so the commit never matched; and the PreToolUse-on-every-Bash gate re-fired after the commit and blocked push/PR. FIX: documentation now writes `.pipeline/review-manifest.json` with `reviewed_change_hash` (post-doc tree); the gate checks that, and skips currency once the tree is clean (`git status --porcelain` empty) so push/PR pass through. NEW settled rule — see below.
  2. **smoke-check.sh greenfield fallback was dead code** (`HEALTH_URL` always defaulted, so the `-z` branch never ran). FIX: greenfield is now detected by absence of any commit (`git rev-parse --verify HEAD`).
  3. **state.json absent in thin-slice sanity debug** (only security created it, but sanity debugging runs before security). FIX: state.json is initialized at bootstrap + reset; debugging tolerates absence.
- Also fixed: PROJECT.md auth default (now Firebase, was wrongly Cognito-on-AWS); `gh pr create` documented as an intentional prompt; stale phrasing (npm/:3000→Python/8000, clean-commit stamping, post-deploy "Stop hook"→CI); Part I "16 skills"→13; stale per-section skill numbers removed; duplicate `key-resources` TOC anchors; security-tool install pointers added; documentation agent gained `Edit`.
- LOAD-BLOCKER CLEARED: all 13 skills are written. 11 global at `C:\Users\brett\.claude\skills\` (NOT committed to the repo — shared across projects); 2 project templates committed in-repo at `.claude/skills/` (`test-conventions`, `semgrep-ruleset-guide`, still carry `<PLACEHOLDERS>` to fill at pilot). Siblings written: code-standards/examples.md, stride/examples.md, doc-conventions/{readme-template,pr-description-template,diagram-examples}.md, auth-patterns/scaffold/ (firebase py+js), logging-conventions/scaffold/ (structlog), iac-conventions/baseline.md. All `name:` fields verified against folder names.
**BUILD COMPLETE (2026-06-25):** the pipeline is scaffolded into the repo's `.claude/`:
- 7 agents (`.claude/agents/*.md`), 5 hooks (`.claude/hooks/*.sh`, executable, all pass `bash -n`), `.claude/settings.json` (valid JSON) — all copied from the spec with the audit fixes applied (documentation has Edit + writes review-manifest; deployment-gate uses reviewed_change_hash + porcelain skip; smoke-check uses no-HEAD greenfield detection; debugging tolerates absent state.json).
- Bootstrap done: `.pipeline/` created with `state.json` initialized, `.pipeline/` + `*.tfstate`/`*.tfvars` appended to `.gitignore` (which was a stock Python .gitignore).
- 13 skills already built (11 global in `~/.claude/skills/`, 2 project templates in-repo).
- **Prereqs still to install:** `jq`, `semgrep`, `osv-scanner` (MISSING). Present: git, curl, gh, node, npx. NOTE: the **thin slice** (planning→checkpoint→implementation→smoke) needs none of the missing tools — only smoke-check/infra-validate hooks run, and neither uses jq. jq is needed once testing/deployment run; semgrep+osv-scanner once security runs.
- Remaining before a FULL run: install jq+semgrep+osv-scanner; write a `CLAUDE.md` (+`PROJECT.md` for greenfield) for the pilot project; fill the 2 project-template `<PLACEHOLDERS>`.
- Pilot via the `pipeline-orchestration` skill / the *Running the pipeline* sequence in the spec.

**8 preloaded skills (write these first — they block their agents):**
All live in `~/.claude/skills/<name>/SKILL.md` (global).
1. `stride-threat-model-template` — planning (~120 lines)
2. `code-standards` — implementation (~110 lines, merged SOLID+Clean+facade)
3. `test-conventions` — testing (~70 lines, project template with placeholders)
4. `semgrep-ruleset-guide` — security (~60 lines, project template with placeholders)
5. `diff-scoping-conventions` — security + testing (~55 lines)
6. `doc-conventions` — documentation (~100 lines, merged docs+Mermaid)
7. `debugging-escalation-protocol` — debugging (~70 lines)
8. `deployment-checklist-and-rollback` — deployment (~50 lines)

**5 on-demand skills (write before first feature that needs each):**
9. `auth-patterns` — planning, implementation (auth features)
10. `logging-conventions` — planning, implementation (observable-event features)
11. `iac-conventions` — planning, implementation, security (infra/ changes)
12. `ddia-patterns` — planning (storage/messaging changes)
13. `pipeline-orchestration` — orchestrator/main thread

See [[brett-profile]] for Brett's preferences and default stack.
