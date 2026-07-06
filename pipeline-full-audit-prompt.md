►►► SESSION SETUP (operator — do this before pasting the rest) ◄◄◄
1. Be on the **latest `main`** first: `git checkout main && git pull` — the merged
   input-control, ASVS, and remediation work (and their plan docs) must be present, or the
   audit runs against a stale tree.
2. Start Claude Code **inside the repo**: `C:/Users/brett/OneDrive/Documents/GitHub/claude-agentic-workflow`
   (so the agent has direct file access to everything referenced below).
3. Pin the model: run `/model claude-fable-5`. Do **not** use `/fast` (that switches to Opus).
4. Paste this entire file as your first message. Let it run to completion — it is designed to
   work through every phase without stopping or asking for confirmation.
────────────────────────────────────────────────────────────────────────────────

You are a senior staff software engineer and application-security lead. Conduct a
**thorough, skeptical, evidence-based audit** of the multi-agent SDLC pipeline in this
repository — an "agentic software factory" of agent prompts + deterministic shell-hook
gates that drives planning → plan-audit → implementation → (security ⇄ debugging ⇄
testing loop) → documentation → deployment, with human checkpoints. The operator intends
this pipeline to build **professional, production-grade applications for public release,
including app stores.** Find everything that would stop it from doing that safely,
efficiently, and correctly, and recommend concrete improvements.

**SCOPE — audit ONLY this repository (the pipeline engine).** Do NOT open, run, or audit the
applications this pipeline has built (there is a sibling app repo — ignore it). Where a
perspective concerns the quality or security of the *output* (perspectives 2 and 3b), judge
it from the pipeline's **design and enforcement mechanisms** — the agent instructions, the
deterministic gates, the skills, the plan-audit/STRIDE checks — i.e. whether the pipeline
*would* produce professional, secure software and *forces/guides* the right controls. You are
auditing the factory, not a car it made.

═══════════════════════ OPERATING DISCIPLINE (read first) ═══════════════════════
- **Finish in one continuous pass. Do not stop, and do not ask for confirmation between
  phases.** This is a large audit; work through every phase autonomously and only stop
  when the full report is written. Write findings **incrementally** to
  `PIPELINE-AUDIT-REPORT.md` as you complete each phase, so a long run survives.
- **Verify against the actual code — never trust a summary, comment, doc, or memory
  claim.** Open the file, read it, cite `path:line`. Tag every finding
  **VERIFIED / PARTIAL / UNVERIFIED**. A finding needs a concrete failure scenario +
  evidence, not vibes. Rank by severity (Critical/High/Med/Low/Info).
- **Stay concrete and decomposed.** Prefer checklist-driven, file-by-file analysis over
  open-ended speculation. Quantify where you can (counts, token estimates, line refs).
- **This is a constructive, authorized review of the operator's OWN tooling — defensive
  security only.** You are hardening defenses. Do NOT write exploit code, malware, payloads,
  or offensive tooling. Name vulnerability classes and describe the **fix, gate, test, or
  detection** — never the attack. This keeps the review squarely defensive.
- **Work steadily and self-sufficiently through the whole scope; don't defer or hand off
  the analysis.** Read broadly, reason concretely, keep momentum to completion.

═══════════════════════ INPUTS — read these ═══════════════════════
Repo of record: `C:/Users/brett/OneDrive/Documents/GitHub/claude-agentic-workflow/`
- `global-agents/*.md` — the agent definitions (planning, plan-audit, implementation,
  debugging, security, testing, documentation, deployment). Read frontmatter (model,
  maxTurns, tools, hooks, skills) AND the body.
- `global-hooks/*.sh` — the deterministic gates + telemetry (deployment-gate,
  loop-guard, compute-change-hash, log-run, record-clean, guard-approval-markers,
  guard-source-markers, lockfile-check, smoke-check, stamp-ran-at, semgrep-scan,
  trivy-scan, generate-sbom, write-review-manifest, approve-diff, infra-validate,
  post-deploy-check).
- `global-skills/*/SKILL.md` and `global-project-skills/*/SKILL.md` — the skill library.
- `scripts/` — bootstrap-project.sh, install-global.sh, run-log-digest.sh,
  run-summary.sh, list-skills.sh.
- `tests/` — the eval harness. **Run it:** `bash tests/run-eval.sh` (and `-v`). Read the
  suites + fixtures + `helpers/loop-exit-predicate.jq`.
- `templates/`, `.agents/`.
- Prior analysis (CONTEXT, not gospel — re-derive and challenge): `pipeline-june-analysis.md`,
  `audit-remediation-plan.md`, `input-controls-enforcement-plan.md`, `m2-test-plan.md`,
  `m2-run-2-test-plan.md`.
Published/live copy: `C:/Users/brett/.claude/` (`agents/`, `hooks/`, `skills/`,
  `pipeline-templates/`). **Diff it against the repo — publish drift is a real defect
  class** (a fix can live in one copy and not the other).
Operator memory: `C:/Users/brett/.claude/projects/c--Users-brett-OneDrive-Documents-GitHub-claude-agentic-workflow/memory/MEMORY.md` and its
  linked files — records settled decisions. Don't relitigate them without cause, but DO
  challenge any that look wrong, and verify anything it asserts about a file still holds.

═══════════════════════ PHASE 0 — BUILD CONTEXT BEFORE JUDGING (do this first) ═══════════════════════
Do NOT start writing findings until you have an accurate mental model. Work through this
orientation, then write a short "Orientation notes" section at the top of
`PIPELINE-AUDIT-REPORT.md` (what the pipeline is, its stages, its interlock files, its trust
model) — proving you understand it before you critique it.
1. **Map the repo.** List `global-agents/`, `global-hooks/`, `global-skills/`,
   `global-project-skills/`, `scripts/`, `tests/`, `templates/`, `.agents/`. Note counts and
   the naming pattern.
2. **See the skill routing.** Run `bash scripts/list-skills.sh` (and `--annotate` if
   supported) to see which skills are PRELOAD vs on-demand and by which agent.
3. **Watch the deterministic layer work.** Run `bash tests/run-eval.sh -v` and read what the
   suites assert — this is the ground truth of how the gates behave, and your correctness
   baseline.
4. **Read the operator's settled context.** Read
   `C:/Users/brett/.claude/projects/c--Users-brett-OneDrive-Documents-GitHub-claude-agentic-workflow/memory/MEMORY.md` and its linked files
   (settled decisions, deferrals, known constraints). Treat as claims to verify, not gospel.
5. **Internalize the pattern.** Read 2–3 agent defs in full (e.g. `planning`, `security`,
   `testing`) and 3–4 hooks in full (`deployment-gate.sh`, `loop-guard.sh`,
   `compute-change-hash.sh`, `log-run.sh`) so you know the conventions before the systematic
   sweep. Read `global-skills/pipeline-orchestration/SKILL.md` for the stage order + the
   `.pipeline/*` interlock-file contracts.
6. **Check publish drift.** Diff `global-hooks/*` vs `C:/Users/brett/.claude/hooks/*` and the
   `global-agents`/`global-skills` trees vs their `~/.claude` copies. Divergence = an integrity
   finding.
7. **Skim the prior analysis** (`pipeline-june-analysis.md`, `audit-remediation-plan.md`,
   `input-controls-enforcement-plan.md`, `m2-test-plan.md`, `m2-run-2-test-plan.md`) to learn
   history and open items — then independently verify or challenge them; do not inherit their
   conclusions.

═══════════════════════ PERSPECTIVES (audit each; add any missing) ═══════════════════════

**1. Token / context efficiency.** Where is the pipeline spending tokens it needn't?
   - Skill loading: which skills are PRELOAD vs on-demand (`scripts/list-skills.sh`)? Is
     each preload justified, or is a large skill loaded on every run of an agent that
     rarely needs it? Are on-demand skills correctly gated?
   - Per-stage model assignment (opus/sonnet/haiku in each agent's frontmatter) vs need —
     is opus used only where reasoning truly warrants it (planning/debugging/security), or
     over-assigned? Estimate the relative cost weight per stage.
   - Context handoff via `.pipeline/*` artifacts — are they lean, or bloated with content
     the next stage re-reads wholesale? Is the "fresh-context handoff" rule actually
     minimizing re-derivation, or causing re-reads?
   - `maxTurns` budgets — right-sized? Undersized budgets cause cap-outs → resume/rework
     (pure waste); oversized invite meandering.
   - Agent-def and skill prose length — verbose instructions cost tokens every invocation.
     Flag bloat and redundancy across agents/skills.
   - Retry/loop waste — quantify the realistic token cost of a typical run incl. the
     security⇄debugging⇄testing loop; where's the biggest avoidable spend?

**2. Software-development performance & output quality (production/industry standard).**
   Does this pipeline actually produce professional-grade software?
   - Does the stage sequence map to a real SDLC? What's missing (CI wiring, release/rollback,
     observability, load/perf in a realistic environment, data migration safety, feature
     flags, code review depth)?
   - Gate rigor: are the gates deterministic, fail-closed, and non-bypassable? Verify the
     `loop-exit ≡ gate` invariant (`tests/suites/loop-exit-invariant.sh`) actually holds and
     that the three predicate copies (deployment-gate.sh, the orchestration SKILL, and
     `loop-exit-predicate.jq`) are truly equivalent.
   - Test rigor: does the testing stage produce REAL tests across the pyramid (unit,
     integration, property, concurrency, perf, mutation) — and adversarial shapes that catch
     shaped-to-pass suites? Is coverage measured honestly (per-tier, branch, mutation scope)?
   - Do the implementation agent's instructions + `code-standards` + the gates actually
     compel real engineering (facades, SOLID, real error handling, meaningful tests) — or
     would they let plausible-but-shallow code pass? Judge this from the instructions and
     gate predicates themselves, not from a built app.
   - Are the human checkpoints placed to catch what automation can't, without becoming rubber
     stamps?

**3. Security — TWO distinct targets.**
   **3a. The pipeline's own security.** Can an agent forge a green gate, fabricate a human
   approval, or smuggle a change past review?
   - The gates trust agent-written status files (`security-status.json`, `test-results.json`,
     `test-quality.json`). Assess that trust model: what stops an agent from writing
     `status:"clean"` dishonestly? Which checks are independently deterministic vs
     agent-asserted? (Be precise — this is the crux.)
   - Marker/approval forging: read `guard-approval-markers.sh`, `guard-source-markers.sh`,
     `approve-diff.sh` (TTY-only), and the settings deny. Find any residual bypass beyond the
     documented obfuscated-Bash one.
   - Prompt-injection surface: repo content / tool results / MCP results feeding agents — can
     a malicious string in a dependency, a file, or a scan result steer a gate or an agent?
   - Secrets handling in bootstrap/hooks/agents; the change-set hash determinism; publish
     drift as an integrity gap.
   **3b. The security of the APPLICATIONS the pipeline builds** — the operator's core goal:
   app-store-grade apps that avoid the classic AI/"vibe-coded" security failures. For EACH
   of these classes, determine whether the pipeline **forces** the control (deterministic
   gate), **strongly guides** it (skill/plan-audit/STRIDE), or **misses** it — and cite where:
   - Broken **object-level authorization / IDOR (OWASP API1 / BOLA)** — the #1 real-world AI
     app failure. Is per-object owner/tenant scoping actually enforced and tested, or assumed?
   - Input validation + output encoding at the sink (injection/XSS/SQLi/command/path/SSRF).
   - Rate limiting / anti-automation (per-identity, post-auth — verify the two-tier design in
     `api-edge-conventions` is coherent and testable).
   - Broken authentication / session / token handling; MFA where relevant.
   - Secrets in source / config / logs; secret management at runtime.
   - Mass assignment / over-posting; insecure deserialization.
   - Security headers, CORS, cookie flags, TLS.
   - Verbose error / stack-trace leakage; PII in logs.
   - Dependency vulns (OSV) + the CVE-severity floor; SBOM; supply-chain (lockfile) integrity.
   - Missing authz on internal/queue/file-ingest surfaces (not just HTTP).
   - Verify the ASVS 5.0 verification layer + the input-surface reconciliation gate actually
     bite, and find the gaps they don't cover.

**4. Correctness & functionality (does it work as coded; good practice).**
   - Run `bash tests/run-eval.sh`; report pass/fail and read what each suite actually asserts
     (do the assertions test the real property, or a proxy?).
   - Do agent defs reference hooks/skills that exist? Any dangling reference, wrong path, or
     mis-wired hook (PreToolUse/Stop)?
   - Read each hook for real bugs: `set -euo pipefail` interactions, unquoted expansions,
     locale/CRLF/odd-filename issues, jq fallbacks, fail-open paths, race conditions.
   - Internal contradictions across agents/skills (e.g. a middleware-ordering rule that
     defeats its own keying advice). Hunt for these — one already existed.

**5. Internal coherence & maintainability.**
   - Consistency of terminology, schemas (the `.pipeline/*` file contracts), and severities
     across agents/hooks/skills.
   - Drift risks: duplicated content in two homes (e.g. `.agents/skills/` vs
     `global-project-skills/`), repo-vs-published divergence, hand-maintained mirrors.
   - Documentation quality and whether a new operator could run and trust the pipeline.
   - Change-management: how are gate predicates kept in sync; is the invariant harness
     sufficient?

**6. Production / app-store readiness (coverage gaps).**
   Judge honestly what's NOT covered for shipping a public product:
   - Frontend / mobile build, signing, store-compliance (privacy manifests, permissions).
   - Observability: logging/metrics/tracing/alerting/error-tracking in production.
   - CI/CD, release, rollback, migrations against real data, feature flags.
   - Privacy / compliance (PII handling, GDPR/CCPA, data retention), accessibility (a11y),
     i18n, licensing.
   - DR / backup; performance/load under realistic conditions.
   Mark each as covered / partial / absent, and whether absence is a deliberate deferral
   (check memory) or an unflagged gap.

═══════════════════════ SKILLS & MCP RECOMMENDATIONS ═══════════════════════
- **Skills:** recommend NEW skills and ADDITIONS to existing skills that would measurably
  improve model performance and/or the security of built apps. Be concrete (name, trigger,
  what it encodes, which agent loads it, preload vs on-demand). Prioritize gaps you found —
  e.g. authorization/BOLA, deeper threat modeling, observability, privacy/compliance,
  accessibility, DB index/query review, performance profiling, mobile/app-store.
- **MCP servers:** recommend MCP servers that would help (e.g. up-to-date library docs, a
  vulnerability/advisory source, cloud/IaC knowledge, a docs/reference server), each with:
  the concrete benefit, which stage/agent uses it, preload/on-demand, and the **security
  trade-off** of adding it (an MCP server is added attack surface + a prompt-injection vector
  + a supply-chain dependency). Note anything that should NEVER be an MCP (e.g. the
  deterministic gates must stay shell, never LLM/MCP-judged).

═══════════════════════ DELIVERABLE — write to PIPELINE-AUDIT-REPORT.md ═══════════════════════
1. **Executive summary + overall verdict.** A production-readiness grade for building
   app-store-grade software today, with the 3–5 things that most hold it back.
2. **Per-perspective findings ledger.** For each finding: `{id, perspective, claim,
   VERIFIED/PARTIAL/UNVERIFIED @ path:line, severity, concrete failure scenario, recommended
   fix}`. Most-severe first.
3. **Prioritized remediation roadmap** — P0 (ship-blockers for the operator's goal) / P1 / P2,
   each with the exact file(s) and a proposed change.
4. **Recommended skills** (new + additions) and **recommended MCP servers**, each with
   rationale + trade-offs, ranked by leverage.
5. **Highest-leverage single change per perspective.**
6. **What you could NOT verify**, and the exact instrumentation/access needed to close it.

═══════════════════════ RULES ═══════════════════════
Verify against code; cite `path:line`; quantify; prioritize; produce actionable diffs/specs.
Run the eval harness. Check publish drift. Challenge the prior analysis docs and the memory
where they look wrong. Keep every security recommendation defensive (fix/gate/test/detection,
never an exploit). Do not stop until `PIPELINE-AUDIT-REPORT.md` contains the full report.
