---
name: agentic-pipeline-project
description: "Brett's Claude Code multi-agent SDLC pipeline — architecture, settled decisions, and current build status"
metadata: 
  node_type: memory
  type: project
  originSessionId: c20cf04b-1941-4022-bb3f-cffa93ee483c
---

Brett is building a reusable Claude Code multi-agent SDLC pipeline. All authoritative files are in the repo at `c:\Users\brett\OneDrive\Documents\GitHub\claude-agentic-workflow\`. The repo copy of this file is at `memory/project-context.md`.

**All four spec/companion files are in the repo:**
- `docs/agentic-pipeline-plan.md` — the main spec (~2600 lines). Read this for the full design.
- `docs/pipeline-alternatives.md` — non-default scaffolds (Cognito, GCP observability, JS backend, Go/Java). Documentation-only; never loaded at runtime.
- `docs/pipeline-deployment-targets.md` — CI/CD patterns after the pipeline ends at a PR. Documentation-only.
- `docs/pipeline-mcp-config.md` — per-agent MCP server mapping + §7 token-vs-performance verdict table. Documentation-only.

**Architecture (settled — do not relitigate):**
- 8 subagents: planning, plan-audit, implementation, debugging, security, testing, documentation, deployment. (`plan-audit` added 2026-06-27 — Haiku/effort medium, runs automatically after planning and before the human checkpoint; advisory-only, non-gating. Writes `.pipeline/plan-audit.md` flagging: ambiguous plan wording that could mislead downstream agents; hallucinated/slopsquatted deps verified against npm/PyPI registries via curl; version-policy violations (cooldown 14–30d minor / 30–90d major / 0–7d CVE, max n-1 obsolescence, exact-pin determinism, minimal-footprint fit). As of PR J (2026-07-01) the dependency reality-check + version policy live in the on-demand `dependency-audit-policy` skill (plan-audit gained the Skill tool and invokes it only when the plan introduces a new dependency); a no-new-deps plan never loads it. Distinct from the still-UNIMPLEMENTED scoring/revision "Planning quality loop" in `docs/pipeline-refinement-loops.md`.)
- File-based handoff via `.pipeline/*` artifacts (subagents start blank; state passes through files only).
- Deterministic shell-hook gates: `smoke-check.sh` (implementation Stop), `record-clean.sh` (testing Stop), `deployment-gate.sh` (deployment PreToolUse).
- Human checkpoint: `.pipeline/plan-approved` marker; implementation refuses to start without it.
- Diff-scoping: working tree vs last commit (`git diff HEAD --name-only` + `git ls-files --others --exclude-standard`). No `last_clean_commit` pointer.
- Deployment agent makes the pipeline's ONLY commit (as its first step, after gate passes).

**Key settled decisions:**
- Defaults: AWS (cloud/infra) + Firebase Auth (default, cloud-agnostic) + Python backend + JS frontend. ONE documented runtime path.
- Non-defaults (Cognito, GCP, JS backend, Go/Java) live in `docs/pipeline-alternatives.md` — zero runtime tokens.
- Skills: 14 total (the 2026-06-25 set of 13 + planning-only `containerization-conventions`). 8 preloaded (1–2 per agent), 6 on-demand. 12 global (`~/.claude/skills/`), 2 project-scoped templates (`.claude/skills/` in repo: `test-conventions`, `semgrep-ruleset-guide`).
- MCP (revised 2026-06-25): **project-scoped via a root `.mcp.json`, like project skills — nothing default-on.** A project with no `.mcp.json` loads zero MCP. Only **3 servers** are wired (via per-agent `tools:` `mcp__*` entries that resolve to nothing unless the project defines the server): **context7** → implementation only (current library APIs; NOT planning — no benefit for architecture reasoning); **aws-knowledge + terraform** → planning + implementation only, and only earn tokens on infra/AWS projects. **Security gets NO MCP** (deterministic Semgrep/OSV/Checkov scanners; trimmed 2026-06-26 — researching provider docs bought nothing). The broken inline `mcpServers:` blocks were removed from planning.md + implementation.md. Template: `templates/mcp.json`. GitHub/Sentry/Firebase/Playwright deliberately NOT wired (gh CLI replaces GitHub; Sentry is out of the pipeline's pre-merge scope; Firebase is 30+ heavy schemas covered by the auth-patterns skill; Playwright a11y snapshots are a budget hazard). SAST stays a shell hook, never MCP. `docs/pipeline-mcp-config.md` "Current wiring decision" box is authoritative.
- Deployment agent scope: commit + push + open PR only. No `terraform apply`, no DB migrations, no app deploy.

**Current build status (verified against repo + home dir 2026-06-25):**
- SCAFFOLD essentially complete. In repo: all 7 agents (`.claude/agents/`), 9 hooks (`.claude/hooks/`), `settings.json`, the 2 project skills (`test-conventions`, `semgrep-ruleset-guide`), `.pipeline/state.json`, `.gitignore` (ignores `.pipeline/`, `*.tfstate`, `*.tfvars`).
- SKILLS ALL EXIST. `~/.claude/skills/` (= `C:\Users\brett\.claude\skills\`) holds all 12 global skills. With the 2 project skills = all 14 exist. NO load-blocker. **Global skills are now version-controlled** in `global-skills/` in the repo; `scripts/install-global-skills.sh` is the install script (repo = source of truth, re-run script to publish changes to `~/.claude/skills/`). (NOTE: the Glob tool silently returns nothing for the home `.claude` dir — it's outside the workspace; use Bash `ls` to inspect global skills, not Glob. An earlier "skills are empty" claim was a Glob false-negative.)
- TOOLS (rechecked 2026-06-25): `jq` 1.8.2 and `osv-scanner` 2.4.0 are INSTALLED (winget) and on the persistent **user PATH** — the earlier "missing" reading was a stale-session-env artifact, NOT an absence. They become visible to hooks only after Claude Code/IDE is restarted (running session captured PATH at launch). `semgrep` runs via Docker wrapper (`semgrep-scan.sh`); Docker daemon confirmed RUNNING. `terraform` 1.15.7 (winget `Hashicorp.Terraform`) and `checkov` 3.3.2 (pip) INSTALLED 2026-06-26 — `checkov` runs as a bare command in git-bash (ships `checkov`/`checkov.cmd`, no `.exe`); `terraform` lands on PATH only after a Claude Code/IDE restart (stale-session PATH, same as jq/osv-scanner). `gh`/`npx`/`git`/`curl`/`sha256sum`/`docker` present. The deploy-gate fail-close on missing jq was reproduced empirically (clean state still exited 2 with `jq: command not found`).
- SPEC↔LIVE drift resolved 2026-06-25: deployment branch-creation step + planning `containerization-conventions` trigger ported into live `.claude/agents/{deployment,planning}.md`; `git checkout`/`git symbolic-ref` added to settings.json allow-list. `.claude/` is runtime source of truth; the spec doc (`docs/agentic-pipeline-plan.md`) is documentation — keep in sync.
- run-log.jsonl WIRED + LIVE (2026-06-26): `log-run.sh` is a `Stop` hook on all 7 agents; signature `log-run.sh <stage> <model> [status]` — `feature` auto-derives from git branch, `status`/`retries` auto-derive from each stage's `.pipeline/*` artifact, `model`+`files_changed` on every line, coverage/finding extras for testing/security. `smoke-check.sh` now writes `.pipeline/smoke-status.json` so the implementation stage logs a REAL smoke pass/fail (not a default). Testing `maxTurns` cut 15→10. Two greenfield bugs in `log-run.sh` fixed (pipefail abort + corrupted feature when no HEAD). KNOWN LIMIT: a `maxTurns` cap-out skips the Stop hook, so a missing stage line = suspect cap-out. `post-deploy-check.sh` still `[UNIMPLEMENTED]` (CI-era, not needed for first run).
- Next steps before test projects: (1) DONE — jq/osv-scanner/terraform/checkov installed (semgrep via Docker); (2) verify `.sh` hooks actually fire on Windows (CRITICAL — telemetry + gates both depend on Stop hooks firing); (3) per-project CLAUDE.md; (4) DONE — run-log wired. Thin slice target: planning → human checkpoint → implementation → smoke check.
- Repo hygiene (DONE 2026-06-26): GitHub secret scanning + push protection ENABLED, and Dependabot alerts + security updates (SCA auto-fix PRs) ENABLED — all via `gh api`. Repo + full git history scanned clean (no API keys/tokens; Claude Code's credential lives in `~/.claude`, outside the repo). `.gitignore` excludes `.env`/`.envrc`/`*.tfvars`/secrets.toml. Still optional/off: secret-scanning non-provider-patterns + validity-checks.
- Audit + hardening pass (2026-06-26): full file-by-file audit — verdict READY for a supervised trial run. Fixes applied: added `Skill` to `planning`/`implementation`/`security` `tools:` (on-demand skills — auth/logging/iac/ddia/containerization — need the Skill tool to load); centralized the change-set hash in shared hooks `compute-change-hash.sh` + `write-review-manifest.sh` (documentation calls the latter — no perm prompt; deployment-gate recomputes via the same script, verified byte-identical); added jq-presence guards to `deployment-gate.sh` (fail-closed exit 2) and `record-clean.sh` (fail-open exit 1, non-silent); widened `.env` deny to `Read(**/.env)`; re-published `doc-conventions`. Hooks now 9. ONLY remaining step before first run: restart Claude Code + IDE (loads new agent `tools:`/republished skills, and puts terraform on PATH).

**8 preloaded skills (ALL EXIST — these are what each agent loads at startup):**
6 live global in `~/.claude/skills/<name>/SKILL.md`; 2 (`test-conventions`, `semgrep-ruleset-guide`) are project-scoped in the repo.
1. `stride-threat-model-template` — planning (~120 lines)
2. `code-standards` — implementation (~110 lines, merged SOLID+Clean+facade)
3. `test-conventions` — testing (~70 lines, project template with placeholders)
4. `semgrep-ruleset-guide` — security (~60 lines, project template with placeholders)
5. `diff-scoping-conventions` — security + testing (~55 lines)
6. `doc-conventions` — documentation (~100 lines, merged docs+Mermaid)
7. `debugging-escalation-protocol` — debugging (~70 lines)
8. `deployment-checklist-and-rollback` — deployment (~50 lines)

**6 on-demand skills (ALL EXIST in `~/.claude/skills/`; loaded only when a feature needs each):**
9. `auth-patterns` — planning, implementation (auth features)
10. `logging-conventions` — planning, implementation (observable-event features)
11. `iac-conventions` — planning, implementation, security (infra/ changes)
12. `ddia-patterns` — planning (storage/messaging changes)
13. `containerization-conventions` — planning only (when a plan weighs packaging: Docker vs. process vs. serverless, k8s vs. managed runtime). Decision-guide for the planner. Deferred gap: no implementation/security wiring yet for authoring Dockerfiles/manifests or image scanning.
14. `pipeline-orchestration` — orchestrator/main thread

See [[brett-profile]] for Brett's preferences and default stack.
