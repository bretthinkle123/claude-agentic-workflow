# Pre-build readiness audit prompt

Use this prompt to start a new session whose sole job is to audit the repo before
any building begins. Paste it in as the opening message.

---

## Prompt

You are auditing a Claude Code multi-agent SDLC pipeline design to determine whether
it is fully ready to build. This is a READ-ONLY session — do not create, edit, or
delete any files. Produce a written report only.

### Step 0 — Read all context files first (do this before anything else)

Read these files in order before forming any opinions:

**Memory / context (read first):**
- `memory/project-context.md` — who Brett is, settled decisions, current status
- `memory/brett-profile.md` — preferences and working style

**Main spec (read in full):**
- `plan/agentic-pipeline-plan.md` — the authoritative design doc (~2600 lines, three parts:
  orientation guide, main document, implementation appendix)

**Companion files (skim for cross-reference checks):**
- `docs/pipeline-alternatives.md` — non-default scaffolds (Cognito, GCP, JS backend, Go/Java)
- `docs/pipeline-deployment-targets.md` — CI/CD patterns (GitHub Actions, ECS, Lambda, etc.)
- `docs/pipeline-mcp-config.md` — per-agent MCP mapping + token-vs-performance verdict table

Do not begin the audit until you have read all six files.

---

### Who Brett is

Self-described beginner, building his first serious agentic workflow on Claude Code.
Highly token-cost-conscious — call out token tradeoffs when relevant.
Prefers thorough written reports over quick takes.
Settled design decisions must not be re-litigated — only flag genuine gaps or errors.

---

### What this project is

A reusable Claude Code multi-agent SDLC pipeline:
- 7 subagents (planning → implementation → debugging → security → testing →
  documentation → deployment), file-based handoff via `.pipeline/*`.
- Deterministic shell-hook gates between stages (no LLM judgment for pass/fail).
- Human checkpoint before implementation. Diff-scoping for token efficiency.
- The deployment agent makes the pipeline's only commit.

It is in the DESIGN phase. Nothing has been built yet. The goal of this audit is to
determine whether `plan/agentic-pipeline-plan.md` and the repo are fully ready to start
creating the actual files.

---

### What "ready to build" means

Building means creating real files in the repo:
- `.claude/agents/*.md` — 7 subagent definition files
- `.claude/hooks/*.sh` — 5 hook scripts
- `.claude/settings.json` — permissions and auto-approve
- `~/.claude/skills/<name>/SKILL.md` — 8 preloaded skills (the current load-blocker),
  plus 5 on-demand skills
- `.claude/skills/` — 2 project-scoped skill templates (test-conventions,
  semgrep-ruleset-guide)
- `.gitignore` entry for `.pipeline/`

The spec already contains the full text of the 7 agent files, 5 hook scripts, and
settings.json verbatim (they can be copy-pasted). The 13 skills need to be authored
from the spec's "Skill authoring plan" section.

---

### Audit checklist — check every item, report on each

**A. Internal consistency**
1. Do all cross-references between sections resolve correctly? (e.g., a section that
   says "see the X section" — does that section exist and say what's claimed?)
2. Are the interlock file schemas (`.pipeline/*.json/.md`) consistent across every
   agent that reads or writes them? Check: `security-status.json`, `test-results.json`
   (including `tested_change_hash`), `state.json`, `pr-description.md`,
   `plan-approved` marker.
3. Does the `deployment-gate.sh` hook check exactly the four conditions claimed
   everywhere in the doc? Do those conditions match what the testing and security
   agents actually write?
4. Are the hook wiring declarations in each agent's frontmatter (`Stop`, `PreToolUse`)
   consistent with the "Hook wiring" section and the hook scripts themselves?
5. Do the `tools:` lists in each agent's frontmatter match the tools actually used in
   that agent's body? (e.g., documentation uses `Bash` for `git diff` — is `Bash`
   in its `tools:` list?)
6. Are skill names consistent? Every skill listed in an agent's `skills:` frontmatter
   must match a skill name in the "Skill authoring plan" index exactly.
7. Is the `tested_change_hash` computation command identical everywhere it appears
   (security agent body, testing agent body, diff-scoping-conventions spec,
   deployment-gate.sh)?
8. Does the `record-clean.sh` hook correctly read `security-status.json` (not the
   markdown)? Does it match the field names in the schema?

**B. Completeness of the buildable pieces**
9. For each of the 7 agent files: is the frontmatter complete (name, description,
   tools, model, effort, maxTurns, skills, hooks where applicable)? Is the body
   complete and self-contained enough to copy-paste and use?
10. For each of the 5 hook scripts: is the script complete and syntactically correct
    as shown? Are all variables and exit codes consistent with what the agents and
    gates expect?
11. Is `settings.json` complete? Does it cover all the Bash commands the agents
    actually run, without accidentally allowing `terraform apply`, `git push`, or
    other deliberately ungated commands?
12. For each of the 8 preloaded skills: does the "Skill authoring plan" section give
    enough detail (sections, source, budget) to actually write the SKILL.md from?
    Flag any skill spec that is too vague to write from.
13. Is the `CLAUDE.md` template complete enough to fill in for a pilot project?
14. Is the `PROJECT.md` greenfield format complete enough for a first use?

**C. Gaps that would block or surprise a builder**
15. Are there any steps in "Running the pipeline (v1)" that reference something not
    yet defined or that depend on a piece not yet documented?
16. Are there any prerequisites listed that are ambiguous (unclear version, unclear
    install method, unclear config step)?
17. Are there any placeholders, TODOs, or `<fill in>` markers left in the buildable
    pieces (agent files, hooks, settings.json) that would need resolving before use?
18. Does the directory layout in the spec match what actually needs to be created?
    (Cross-check the layout tree against the agent files, hooks, and settings.json
    that reference specific paths.)
19. Is `.pipeline/` correctly marked for `.gitignore`? Is the spec explicit that this
    must be done before the first `git add -A` in the deployment agent?
20. Is the "thin slice" path (planning → human checkpoint → implementation → smoke
    check) fully self-contained? Could someone follow only those stages without
    needing anything from the security/testing/deployment stages?

**D. Spec quality and clarity**
21. Are there any sections that contradict each other after the 2026-06-25 major
    revision? (The revision touched git model, smoke-check, security-status.json,
    skill count, and deployment scope — check for stale phrasing from earlier drafts.)
22. Are there any claims in the orientation guide (Part I) that are inconsistent with
    the implementation appendix (Part III)?
23. Is the "Known gaps" section at the end of the appendix still accurate, or have
    any of the listed gaps been closed by subsequent edits?
24. Are there any numbered lists or tables where the numbering is now wrong due to
    edits? (The 13-skill index was recently corrected; check for any remaining
    old-scheme numbering.)

---

### Output format

Produce a structured written report with one section per checklist category (A–D).
For each item:
- **PASS** — no issue found, brief confirmation
- **ISSUE** — describe the problem precisely (section name, what it says, what it
  should say). Distinguish: *blocker* (would prevent building or cause a runtime
  failure) vs *minor* (cosmetic, stale phrasing, or low-stakes inconsistency).
- **UNCLEAR** — the spec is ambiguous; describe what's ambiguous and what
  clarification is needed before building.

End with a **verdict**: is the spec ready to build from as-is, or does it need
specific fixes first? If fixes are needed, list them in priority order (blockers
first). Be direct — Brett wants a thorough audit, not reassurance.
