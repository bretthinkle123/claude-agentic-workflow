# Pipeline assessment — June 2026 (post PR A–E)

> Independent assessment written 2026-06-30, after the five "pipeline revision" PRs (#2–#6)
> merged. Author: Claude (Opus 4.8), at Brett's request. Grounded in a deep read of the agents,
> hooks, skills, gate logic, and loop machinery — flagged where it reasons about *design* vs.
> things observed actually running. Report-only snapshot; revise as the pipeline evolves.

---

## 1. What this build actually *is* (this frames the whole verdict)

This is **not an application pipeline that ships software**. It is a **code-authoring-and-review
framework**: agent prompts + deterministic shell gates that drive Claude subagents from "feature
request" to **a PR on GitHub**. The flowchart says it outright — `PR on GitHub (pipeline ends
here)` → `CI/CD after merge (out of scope)`. Everything after merge — deploy, migrate prod data,
observe, roll back, operate — is deliberately outside the system (`post-deploy-check.sh` is
`[UNIMPLEMENTED]`; observability is parked in the deferred production-debugger workstream).

Judge it as **"a senior-engineer-in-a-box that produces well-structured, security-reviewed pull
requests,"** not "a system that builds and runs production apps." On the former it is strong. On
the latter it covers roughly the first 60%.

---

## 2. Genuine strengths (real and well-executed)

- **Deterministic fail-closed gates.** `security=clean`, `tests=pass`, and `criteria_covered`
  are checked by `jq` in shell, not by an LLM's say-so. Can't be talked past. The single best
  decision in the repo.
- **Defense-in-depth security.** Semgrep (SAST/SCA/secrets) + OSV (CVEs) + Checkov (IaC) + Trivy
  (containers) + STRIDE threat modeling + **STRIDE-delta attack-surface reconciliation against the
  implemented diff (6f)** + manual checks, criticals folding into one gate; every finding logged in a
  **Complete findings inventory** regardless of severity/exploitability. A more serious security
  posture than most human teams run.
- **Traceability contracts.** Acceptance criteria → mapped tests → deploy gate; plan-audit catches
  slopsquatted deps and untraced criteria. "Did we build what we said" is machine-checked.
- **Bounded autonomy.** Circuit breaker + one-shot plan revision: self-corrects without infinite
  burn. Good judgment about where to trust the LLM vs. shell.
- **Token discipline.** On-demand skills + conditional no-op modes keep cost proportional to what a
  feature actually uses.

---

## 3. What you're missing (prioritized, honest)

**1. Gates verify *presence and structure*, not *semantic quality*. Biggest risk.**
`criteria_covered` confirms each criterion has *a* mapped test — not whether it is rigorous or
asserts `assert True`. Coverage thresholds are gameable. An agent under pressure to go green writes
*plausible, shallow* tests and the pipeline passes them. No mutation testing, no adversarial
"is this test meaningful?" review, no second model grading the first. **Green means "shape is
right," not "code is correct."**

**2. Apparently unproven end-to-end on a real product.** The actual k6/Hypothesis/concurrency
harnesses, Dockerfiles, Terraform are *generated per-project at runtime and not committed*. Output
quality rides entirely on the agents producing good artifacts against these prompts. Reads as a
meticulously-designed *specification* that may never have built and run a real app. The
highest-value unknown.

**3. "Scalable" is asserted, never validated.** Scale appears as *advisory convention text*
(multi-AZ, ASG, health checks) and a *smoke-sized* k6 run ("a regression signal, not a load
campaign"). Nothing proves the app holds under load, the auto-scaling policy fires, or the data
tier survives real concurrency.

**4. The entire delivery + operations half is absent.** No staging, no real deploy, no prod
migration execution, no canary/blue-green *execution* (only notes), no rollback automation, no
monitoring/alerting/SLOs, no incident path. For *live users*, the half that keeps the app up.

**5. Human code review is thin for production.** Two checkpoints: plan-approval (hard) + a soft
pre-deploy glance. Substantive review is delegated to the security + testing agents. Production
work normally needs a human reviewing the *diff*, not just approving a plan.

**6. Data + supply-chain safety are conventions, not gates.** Migrations tested on a *scratch* DB,
never prod-shaped data; no backup/restore. No lockfile-enforcement gate, no SBOM, no artifact
signing — plan-audit checks deps *advisorily*, which doesn't stop a bad dep at build.

**7. Single-feature, single-branch model.** `.pipeline/*` assumes one feature at a time. (For a
**personal/single-device** pipeline this is largely fine — see remediation §6 — so deprioritized.)

---

## 4. Functionality verdict — for professional, production, scalable, live-user apps

- **As a scaffolder/accelerator for a skilled developer** who then hardens, load-tests, deploys,
  and operates the result: **very functional. ~8/10.** Faster than from scratch, security-conscious,
  traceable, catches classes of mistakes humans miss.
- **As an autonomous "build me a production app for live users" system: ~4/10** — and the missing 6
  is the *hard, high-stakes* 6 (correctness depth + the last mile).

The architecture is genuinely sophisticated; the deterministic-gate philosophy is excellent. The
danger is **mistaking a green pipeline for a production-ready app.** Green = "well-formed, scanned,
traceable." It does *not* mean "correct, performant under load, safely operable."

**Highest-value next move:** stop adding capabilities; drive it end-to-end on one real, non-trivial
feature (a migration + an auth path + a perf budget) and watch where the generated artifacts are
shallow or wrong. One real run teaches more than five roadmap PRs.

---

## 5. Remediation plans for §3 "what you're missing"

> Sequenced by leverage. Tags: **[pipeline]** = lives in this repo's agents/hooks/skills;
> **[per-project]** = wired into each app/infra at runtime, pipeline only guides it.
> Single-device/personal context assumed (no multi-tenant concerns).

### M1 — Semantic quality grading (addresses #1 — do this first) **[pipeline]**
A new **`test-quality` / red-team review stage** between testing and documentation, fresh context,
read-only over the diff + generated tests. Two complementary mechanisms:
- **Mutation testing (deterministic):** run `mutmut` (Python) / `Stryker` (JS) on changed modules;
  a surviving-mutant ratio above a threshold = the tests don't actually constrain behavior →
  reported, and gated when the change declares a correctness-critical acceptance criterion.
- **Adversarial test review (a second model):** an agent whose *only* job is to find the assertion
  the test *should* make but doesn't, the edge case skipped, the `assert True` tautology. Emits
  findings; material ones route to debugging like any gap.
Why first: it directly attacks the "shallow tests pass green" failure that undermines every other
guarantee. New `test-quality.json`; folds into the existing gate via a `quality_ok` field rather
than a brand-new gate hook (keep the no-new-gate discipline).

### M2 — Prove it on a real feature (addresses #2) **[process, not code]**
Pick one real feature (migration + auth + perf budget). Run the whole pipeline. Commit the
*generated* artifacts into a `examples/` reference app so future audits have a real corpus, and log
every spot the output was shallow/wrong into this file's §8 "observed failures." This converts the
biggest unknown into data. Gate adding new capabilities on having done this at least once.

### M3 — Real load + scale validation (addresses #3) **[per-project + pipeline]**
- Pipeline: upgrade testing step 5f from "smoke-sized" to an *optional* sustained-load profile
  (`LOAD_PROFILE=campaign`) that runs against a **prod-shaped ephemeral environment** (testcontainers
  or a throwaway stack), not localhost.
- Per-project: a `load-test/` convention + a CI job (post-merge) that runs the campaign against
  staging and posts p95/throughput vs. budget. Scale primitives (ASG/multi-AZ) get an *actual*
  failover test in staging, not just a Checkov check.

### M4 — Delivery + operations (addresses #4 — the last 40%, see §7 roadmap) **[per-project + pipeline]**
The big one. Detailed standalone roadmap in §7.

### M5 — Human diff review checkpoint (addresses #5) **[pipeline]**
Add a real **pre-deploy hard checkpoint** that presents the *diff* + the security/test/quality
reports together and requires an explicit `touch .pipeline/diff-approved` — not just the current
soft glance. Optionally wire `/code-review` (the multi-agent reviewer) as an automated pre-step so
the human reviews an already-triaged diff. Cheap, high-value for production confidence.

### M6 — Supply-chain + data safety gates (addresses #6) **[pipeline]**
- **Lockfile enforcement:** a deterministic hook that fails if `package-lock.json`/`poetry.lock`
  changed without the manifest, or if an unpinned dep entered the tree.
- **SBOM:** generate CycloneDX (Trivy/Syft already in the Docker toolchain) as a deployment
  artifact; attach to the PR.
- **Data safety:** elevate the migration round-trip from scratch-DB to a *prod-shaped seed* and add
  a backup-before-migrate convention to `deployment-checklist-and-rollback`.

### M7 — Single-feature model (addresses #7 — **deprioritized for personal use**)
On one device, one feature at a time is the normal mode. Only revisit if you ever run parallel
pipeline branches. Lowest priority; noted for completeness.

### M8 — Eval / regression harness for the pipeline *itself* (not in §3 — surfaced after) **[pipeline]**
The pipeline *is* prompts, and they're edited constantly; nothing currently catches when an agent/
hook/skill edit silently makes output *worse*. Build a set of **golden fixture features** that run
through the pipeline on every change to `global-agents/`, `global-hooks/`, or `global-skills/`,
with deterministic assertions on the artifacts: did the right gate fire, did `criteria_covered`
map, did each conditional resilience mode trigger (and no-op when it should), did the breaker bound
the loop. Turns "I think PR E didn't regress anything" into a test. Seeds its first fixtures from
the M2 real run.

### M9 — Threat-model the pipeline-as-target / prompt injection (not in §3 — surfaced after) **[pipeline]**
The agents ingest **untrusted input**: `PROJECT.md`, cloned repos, dependency READMEs, reference
screenshots (front-end workstream). A malicious one could try to hijack an agent. Run one STRIDE
pass treating the *pipeline itself* as the attacked system; confirm/extend the existing guards (the
`smoke.env` git-tracked refusal, "treat image text as untrusted") into a coherent posture. Natural
precursor to both a future DAST stage and the red-team app — see [[redteam-app-goal]].

### D1 — Doc fixes (carried over from the conversation) **[docs]**
Small, known doc-debt: (a) the **sequence diagram** in `system_architecture.md` (~line 683) omits
the conditional one-shot plan revision — add an `opt revision_recommended == true` block re-invoking
planning so it matches the flowchart; (b) soften the "**Conditional revision loop**" label (line 251)
since it's explicitly one-shot/no-recursion, not a loop. Low effort, closes a cross-diagram
inconsistency found during the PR-E-era review.

---

## 6. The path from 8/10 → 10/10 as a scaffolder/developer pipeline

The 8→10 gap is **correctness depth + reviewer trust**, not more features. In order:
1. **M1 quality grading** — the missing semantic check; turns "tests exist" into "tests bite."
2. **M5 human diff checkpoint** — a real review surface; the thing that makes a human *trust* a
   green run for production.
3. **M2 prove-it run** — replace assumed quality with measured quality; harden the prompts against
   what you actually observe failing.
4. **M6 supply-chain/data gates** — close the "bad dep / unsafe migration slips through" holes.
5. **Polish:** extract the long always-loaded checklist sections of `planning.md` / `plan-audit.md`
   into on-demand skills (they're at 250/223 lines — the same on-demand lever used everywhere else),
   recovering per-invocation tokens without losing capability.

Do those and the scaffolder verdict is a legitimate 10/10 — *for producing trustworthy PRs*. Note
that 10/10-as-scaffolder still ≠ a production-delivery system; that's §7.

---

## 7. Roadmap — extending past PR generation to full production delivery (the last 40%)

The pipeline today ends at the PR. A production app for live users needs the **delivery and
operations lifecycle** that begins after merge. This is mostly **[per-project]** infra + CI wiring
that the pipeline *guides* (conventions/skills) and optionally *triggers/triages from* — it is NOT
mostly new pipeline agents. Sequenced as it would actually be built:

### Phase 1 — CI as the merge gate (the natural next step after the PR)
The pipeline's deterministic gates stop at the PR; **CI re-runs them on the merge commit** as the
source of truth (a hostile/edited PR shouldn't trust the author's local green). 
- GitHub Actions: lint → build → the full test suite + coverage → Semgrep/OSV/Trivy → `criteria_covered`.
- This is where `post-deploy-check.sh` (currently `[UNIMPLEMENTED]`) finally lives — as a CI job,
  not a local hook.
- Pipeline change: a `ci-conventions` skill + a generated `.github/workflows/` template per project.

### Phase 2 — Build + artifact + supply-chain provenance
- Reproducible build, image push to a registry, **SBOM (M6)** + image signing (cosign).
- Artifact is immutable and traceable to the PR/commit.

### Phase 3 — Environments + progressive delivery
- **Staging** mirroring prod (IaC from `iac-conventions`, now *applied* not just planned).
- Migrations **executed** with expand/contract + backup-before-migrate (M6), against staging first.
- **Canary / blue-green execution** (the conventions already exist as notes; this runs them), with
  automated health/rollback on SLO breach.

### Phase 4 — Observability + operations (the deferred production-debugger workstream)
- Sentry SDK (backend + frontend), structured logs + OTel trace IDs actually shipping to
  CloudWatch/X-Ray, source maps/symbolication, alerting + SLO burn-rate alarms.
- Optional read-only **triage path**: give the debugging agent Sentry MCP to pull one incident's
  stack/breadcrumbs and propose a fix that **re-enters the normal pipeline** — never auto-deploys.

### Phase 5 — Load/scale validation + cost (M3) and DR
- Sustained load campaign against staging; failover test of multi-AZ/ASG; cost guardrails;
  backup/restore + disaster-recovery drill.

**Are these addable to *this* pipeline eventually? Yes — with the right mental model:** the
pipeline stays the *authoring + pre-merge review* brain; phases 1–5 are predominantly **per-project
infra/CI that the pipeline scaffolds, plus a few new skills** (`ci-conventions`, `delivery-conventions`,
the observability wiring already half-specified in `logging-conventions`). The one genuinely new
*pipeline* surface is the optional post-merge triage agent in phase 4. Nothing here forces breaking
the fresh-context / file-handoff / deterministic-gate invariants — it extends them rightward across
the merge boundary.

---

## 8. Observed failures — M2 run #1 (Linkly, 2026-06-30)

> First real end-to-end run: greenfield URL-shortener (`linkly-pipeline-test`), shipped as a clean
> PR. Independently audited from disk (not from the producing session's self-report). **Headline:
> the §3 #1 hypothesis — "shallow tests pass a green gate" — was largely DISCONFIRMED.** The
> generated tests are genuinely rigorous (real Alembic up→down→up; real Hypothesis with 500 examples
> incl. an injectivity/no-collision property; 10 truly-concurrent `asyncio.gather` requests asserting
> exactly one DB row). Architecture was cleanly layered; security found+fixed 3 real issues
> (log-forging + 2 exception leaks), verified 9 STRIDE mechanisms; the plan-audit→one-revision loop
> fired (2 material flags → pinned `structlog`, traced AC15 → `revision_recommended:false`); the
> deploy gate actually blocked junk and the commit shipped clean. So the engine is better than the
> design-level pessimism assumed. The real defects found:

- **F1 — partial verification counted as full coverage (the M1 gap, narrowed).** AC18's budget is
  "p95 < 50 ms **under 100 req/s**." The perf test measures p95 at **concurrency = 1** (serial ASGI
  loop); `perf.measured.throughput_rps` is `null`, yet `perf.status:"pass"` and AC18 `covered:true`.
  The *load* half of the criterion was never exercised, but the gate counts the criterion fully
  covered. This is the real shape of the quality gap: not tautological tests, but **a test that
  verifies a weaker condition than its criterion claims, scored as complete** — with the unmet field
  (`throughput_rps:null`) sitting right there ungated. *(Reframes M1: less "are tests fake," more
  "does the test actually cover the whole criterion + is branch coverage honest.")*
- **F2 — pre-existing initial commit breaks the greenfield change-hash/currency assumption (real
  pipeline bug).** The repo was created on GitHub (auto `README.md` commit). That non-empty initial
  commit broke the deploy gate's greenfield staging-hash assumption, forcing a **manual correction at
  the deploy gate** (regenerate the currency anchor). Reproducible for *anyone* who bootstraps into a
  GitHub-created repo. Fix: make `compute-change-hash.sh` / the currency check handle a repo with a
  prior unrelated commit, or have bootstrap detect+absorb the initial commit.
- **F3 — deployment self-re-anchored the currency hash post-review (integrity soft spot).** To get
  past F2, the deployment agent modified the working tree (`.gitignore`) *after* documentation wrote
  `review-manifest.json`, then **regenerated `reviewed_change_hash` itself**. Benign here (only junk
  exclusion; committed tree verified clean), but it shows the gate's "what ships == what was reviewed"
  guarantee can be satisfied by the deployer re-anchoring rather than re-review. Worth a guard.
- **F4 — `maxTurns` too tight + a telemetry blind spot.** `implementation` and `documentation` are
  **absent from `run-log.jsonl`** (a capped stage's Stop hook never fires), and the operator reported
  every stage needed a manual resume. `testing` (maxTurns 10) wrote 148 tests across 13 files on that
  budget. Bump per-stage `maxTurns` (testing especially); separately, cap-outs being invisible in the
  run-log means you can't measure them — log-run can't see a cap, so a *missing* stage line is the
  only signal.
- **F5 — the gated coverage figure is the weaker one.** Combined **lines 86.03%** (gated, passes)
  but **branches 70.97%** (ungated) — ~29% of branches untested, and branches are where logic bugs
  hide. The deploy gate rides the more flattering number.
- **F6 — data-integrity nits.** `test-results.json` and `security-status.json` both stamp
  `ran_at:"2026-06-30T00:00:00Z"` (a placeholder midnight, not the real time the run-log records);
  `loop-state.json` is left `status:"running"` after a GREEN exit (only cap-out writes a terminal
  status), so the file never reflects "completed."

**Net M2 verdict:** the pipeline produces **substantially better output than the design-level audit
feared** — the correctness-depth worry is real but **narrower and more specific** than "shallow
tests" (it's F1 + F5). M1 should be retargeted accordingly: enforce *criterion-complete* coverage
(every measurable dimension of an AC actually exercised — e.g. fail F1 because `throughput_rps` is
null while the budget names it) and surface branch coverage, rather than hunting tautologies. F2 is a
genuine bug to fix before the next run; the `maxTurns` bump (F4) is a one-line quick win.

---

## 9. Sequencing note — front-end and production-debugger workstreams

Both are already scoped as deferred workstreams (front-end: design-spec/design-system/visual-regression/
a11y; production-debugger: Sentry/observability/triage). Recommended ordering (placed concretely in
the §10 master roadmap): **correctness depth (M1) and proving-it (M2) come before either**, because
they harden the engine both workstreams rely on; **front-end is an independent parallel track** that
can slot whenever a UI project demands it (it does not move production-readiness for the pipeline as a
whole); the **production-debugger is really Phase 4 of §7** and should follow CI + environments, not
precede them.

---

## 10. Master roadmap — the path to a 10/10 pipeline (PR-sequenced)

The single ordered path forward, continuing the merged A–E PR sequence. Rationale for each item is
in this doc (§3 gaps, §5 M1–M9, §7 delivery lifecycle, §8 the M2 findings F1–F6). Effort: **S** ≈
hours, **M** ≈ a focused session/day, **L** ≈ multi-session. Status: ✅ done · ◐ in progress ·
⬜ not started. Calendar dates omitted — this is a dependency order, not a date promise.

**Two definitions of "10/10":**
- **10/10 *scaffolder*** (produces trustworthy PRs a human can confidently merge) = **PRs F–J done.**
- **10/10 *fully-functional pipeline*** (builds *and* safely ships + operates production software for
  live users) = **also PRs L–P done** (the last 40%, §7).

**Critical path:** `M2 ✅ → PR F ✅ → PR G (M1) → PR H (M8) → PR I (M5·M6·F3) → PR J (Polish)` →
[10/10 scaffolder] → `PR L (CI) → PR M (build) → PR N (envs+load) → PR O (observability) → PR P (scale/DR)`
→ [10/10 fully-functional]. **PR K (M9)** and the **side-tracks** (front-end FE, api-edge AE, parallel-impl PI, doc-consolidation DOC; DB ✅ and SEC ✅ done) run in parallel — none on the critical path.

### Done (2026-06-30)
- ✅ **M2 run #1** — pipeline built + shipped `linkly-pipeline-test` PR #1 end-to-end, independently
  audited. Findings in §8. *Headline: test rigor was better than feared; the real gaps are F1/F5.*
- ✅ **PR F — M2 fast-fixes** (branch `feature/pr-f-m2-fixes`, not yet merged): **F2** bootstrap
  `.gitignore` now excludes Python test/coverage/db artifacts (kills the currency-anchor break); **F4**
  per-agent `maxTurns` bumped (testing 10→30, impl 25→40, docs 10→25, etc.) + `system_architecture.md`
  synced. *Remaining M2 nits F3, F6 are folded into PR I / PR G below.*

### Track 1 — harden the authoring engine → **10/10 scaffolder**

| PR | Item | Effort | Depends on | Closes | Why here |
|---|---|---|---|---|---|
| **F** ✅ | M2 fast-fixes (`.gitignore` + `maxTurns`) | S | M2 | F2, F4 | Unblocks a clean second run; done. |
| **G** ⬜ | **Quality + criterion-completeness gate (M1, retargeted by M2)** — enforce that every *measurable dimension* of an acceptance criterion is actually exercised (fail F1: a perf budget naming `throughput_rps` while the test only measures serial latency); **surface branch coverage** (F5); add mutation testing (mutmut/Stryker) + an adversarial "what does this test *not* catch" review; fix results-file integrity nits (real `ran_at`, terminal `loop-state`) (F6). New `test-quality.json`, folds into the existing gate via a `quality_ok`/criterion-complete check — **no new gate hook.** | L | F | F1, F5, F6 | **The #1 gap and the biggest single lever.** M2 proved tests aren't tautological but *can* under-cover a criterion while scoring it complete. Build this against the real Linkly artifacts. |
| **H** ⬜ | **Pipeline eval/regression harness (M8)** — golden fixtures (Linkly is fixture #1) run on every `global-agents`/`global-hooks`/`global-skills` change, asserting gate fired, criteria mapped, each conditional mode triggered/no-op, breaker bounded, cap-outs visible. | M | G | — | You edit agent prompts constantly; nothing catches a regression today except a full manual run. |
| **I** ⬜ | **Review + supply-chain + data safety (M5 + M6 + F3)** — a hard human **diff-review** checkpoint (`diff-approved`, optionally `/code-review` pre-step); **lockfile enforcement + SBOM**; **prod-shaped migration seed + backup-before-migrate**; and a **guard so deployment can't self-re-anchor** the currency hash post-review (F3). | M | F | F3 | Makes a green run *trustworthy* and closes "bad dep / unsafe migration / silent re-anchor." |
| **J** ⬜ | **Token/altitude polish** — extract the long always-loaded checklist sections of `planning.md` (250 ln) / `plan-audit.md` (223 ln) into on-demand skills. | S | — | Recovers per-invocation tokens; no capability loss. Optional but cheap. |

> **After PRs F–J: 10/10 as a scaffolder.** The pipeline produces PRs whose green state means
> *correct + criterion-complete + reviewed*, not merely *well-formed*.

### Parallel side-tracks (don't block the critical path)

| PR | Item | Effort | Depends on | Why parallel |
|---|---|---|---|---|
| **K** ⬜ | **Threat-model the pipeline-as-target (M9)** — STRIDE over untrusted inputs (`PROJECT.md`, cloned repos, dep READMEs, screenshots); harden/confirm the guards. *(A future DAST / red-team *stage* is a later L-effort follow-on, gated on G + K.)* | S–M | — | Precursor to the [[redteam-app-goal]]; hardens the engine before it ingests adversarial input. |
| **FE** ⬜ | **Front-end workstream** — design-spec stage + design-system skill + visual-regression + a11y budget (see [[deferred-frontend-workstream]]). | L | — | A parallel quality axis; does **not** move production-readiness. Slot it when an active build has a UI. |
| **AE** ⬜ | **`api-edge-conventions` skill** — DRAFTED (`global-skills/api-edge-conventions/SKILL.md`): rate limiting/throttling, CORS, security headers, error-envelope facade, idempotency, outbound timeouts/retries. Wire as **on-demand**: add its trigger to the *on-demand skills* prose paragraph in the `planning` + `implementation` agent **bodies** (NOT `skills:` frontmatter — that forces preload; both agents already carry the `Skill` tool). Then `list-skills.sh --annotate` + `install-global.sh` + restart; optional `scaffold/middleware.py`. | S | — | Per-project HTTP-hardening axis; the *implementation* counterpart to STRIDE's DoS/Tampering. Just-in-time enabler for the [[redteam-app-goal]] (HTTP surface). Not critical path. |
| **PI** ⬜ | **Parallel implementation mode (opt-in)** — design removed 2026-07-01 (was `docs/pipeline-parallel-implementation.md`, superseded by `docs/pipeline-code-quality-audit.md`; recoverable from git history): orchestrator fans out implementation across N worktree agents against frozen contracts; planning emits `parallel_units`; per-unit quality gate + serial integration + `/code-review`. | L | planning work-breakdown | Latency optimization for large fan-shaped features, contained in the implementation stage. **Opt-in per run, never default** (trades tokens for wall-clock — against the token-first posture). Non-critical. |
| **DOC** ⬜ | **Documentation consolidation / de-clutter** — the repo's `.md` set has proliferated (`docs/` spec + companions, root-level `pipeline-june-analysis.md` / `pipeline-revision-plan.md` / `m2-test-plan.md`, the memory mirror). Audit, dedupe, and consolidate into a coherent structure: one index, clear source-of-truth-vs-historical separation, archive or retire superseded docs. | M | — | Pure housekeeping — touches no agents/hooks/gates, blocks nothing. Deliberately **last**: do it once the Track 1 churn settles, so you're not reorganizing docs that are still changing. |
| **DB** ✅ | **Debugging-agent upgrade** — `opus`/`xhigh` was **already live** (applied in the §3.1 retune); on 2026-07-01 bumped `maxTurns` 25→30 to match the other reasoning stages (planning/testing/security 30, impl 40). Fires only on failure so absolute cost is negligible. **Distinct from PR O** (the production-debugger / Sentry workstream). *Needs `install-global.sh` to publish.* | S | — | Done. Cheap capability parity for an existing stage. |
| **SEC** ✅ | **Security-agent upgrade (2026-07-01)** — model `sonnet`→**`opus`** (**overrides** the 2026-06-29 `sonnet/high` settled decision — 6f added independent reasoning; knowingly accepts the higher all-models-cap draw, and revert-to-Sonnet stays clean if that cap becomes the bottleneck); new **step 6f — STRIDE delta / attack-surface reconciliation** (reconciles the implemented diff's new/changed surface against the plan's threat model — exploitable-and-fixable gaps patched in place, design-level gaps raised critical → debugging); **Complete findings inventory** (every finding reported regardless of severity/exploitability/remediation) + `total_findings`/`stride_new_threats` status fields; **`surface-delta.md` hybrid** (implementation emits an attack-surface hint, security reconciles it against the diff — diff is the source of truth). Specs (`system_architecture.md`, `agentic-pipeline-plan.md`) + decision docs synced. *Needs `install-global.sh` to publish.* | M | — | New capability (not an M-item): closes "the built app drifts from the planned threat model," strengthens §2. **Distinct from PR K**, which threat-models the *pipeline*, not the built app. |

### Track 2 — extend past the PR → **10/10 fully-functional (the last 40%, §7)**

Mostly per-project CI/infra the pipeline *scaffolds*, plus a few skills — not new pipeline agents.
Strictly dependency-ordered; each presupposes the prior.

| PR | Item | Effort | Depends on | Why here |
|---|---|---|---|---|
| **L** ⬜ | **CI as the merge gate (P1)** — re-run all deterministic gates on the *merge commit*; `post-deploy-check.sh` finally lives here as a CI job. | M | Track 1 stable | The true source-of-truth re-check; gates everything downstream. |
| **M** ⬜ | **Build + artifact provenance (P2)** — reproducible build, registry push, SBOM, image signing. | M | L, I(SBOM) | Immutable, traceable artifact. |
| **N** ⬜ | **Environments + progressive delivery + real load (P3 + M3)** — staging, *executed* migrations, canary/blue-green with auto-rollback, **sustained load + failover tests** against a prod-shaped env. | L | M | First real deploy; proves "scalable" instead of asserting it. |
| **O** ⬜ | **Observability + ops (P4 = production-debugger workstream)** — Sentry, OTel→CloudWatch, alerting/SLOs, optional read-only triage agent that re-enters the normal pipeline. | L | N | Can only observe what's deployed. |
| **P** ⬜ | **Scale validation + DR (P5)** — campaign-scale load, backup/restore drill, cost guardrails. | M | N | Closes the availability/DR gap. |

> **After PRs L–P: 10/10 fully-functional.** The pipeline authors, reviews, ships, and helps operate
> production software for live users — without breaking the fresh-context / file-handoff /
> deterministic-gate invariants; it extends them rightward across the merge boundary.

### What to do next
1. **Merge PR F** (already built) and re-run `install-global.sh` so a second M2 run gets the fixes.
2. **Build PR G (M1)** — the highest-leverage remaining work; design it against the real Linkly
   test/results artifacts in `linkly-pipeline-test`, not in the abstract.
3. Optionally run a **second M2** (e.g. the container/Dockerfile variant) once PR F is live, to feed
   §8 more data and exercise PR E's Trivy path.

### Tomorrow's exact next steps (2026-07-01)
DB is already done in-repo (`opus`/`xhigh` was live; `maxTurns` bumped 25→30) — it only needs the
publish in Step 2 below. Do the steps in order.

**Step 1 — Wire AE (`api-edge-conventions`) as an on-demand skill (~15 min edits).**
It is NOT added to `skills:` frontmatter (that forces preload). Add its trigger to the *on-demand
skills* prose paragraph in each agent body — both already carry the `Skill` tool:
- `global-agents/implementation.md` (the paragraph at ~line 30, after the `iac-conventions` entry):
  add `` `api-edge-conventions` when the change exposes or consumes an HTTP surface (routes, public
  API, webhooks, outbound calls). ``
- `global-agents/planning.md` (the paragraph at ~line 26, in the same list):
  add `` `api-edge-conventions` when the feature exposes or consumes an HTTP surface (new routes,
  public API, webhook receiver, outbound third-party calls); ``
- *(Optional)* draft `global-skills/api-edge-conventions/scaffold/middleware.py` if you want buildable
  starter code like `auth-patterns`/`logging-conventions` ship.

**Step 2 — Publish DB + AE + SEC together, then restart.**
```
bash scripts/list-skills.sh --annotate      # regenerates the loading breadcrumbs (AE → on-demand)
bash scripts/install-global.sh              # publishes agents+skills to ~/.claude (carries DB + AE + SEC: security opus+6f, implementation surface-delta)
# then restart Claude Code / IDE so ~/.claude/agents + skills reload
```

**Step 3 — Deep-focus block: build PR G (M1) — the highest-leverage work.**
Design it against the real Linkly artifacts in `linkly-pipeline-test`, not in the abstract:
- Enforce **criterion-completeness** (fail F1: AC18's perf budget names `throughput_rps` but the test
  measures serial p95 only → `throughput_rps:null` must not score the AC `covered:true`).
- **Surface branch coverage** (F5) alongside the gated `combined` line.
- Add **mutation testing** (mutmut/Stryker) + an **adversarial "what does this test not catch"** review.
- Fix results-file integrity nits (F6): real `ran_at`, terminal `loop-state` on GREEN exit.
- Fold into the existing gate via a `quality_ok`/criterion-complete field — **no new gate hook.**
- New artifact: `test-quality.json`.

**Deferred (don't start tomorrow):** **PI** (a dedicated session — needs planning's `parallel_units`
+ orchestrator fan-out; design in git history — the doc was removed 2026-07-01). **FE** only if tomorrow
actually starts a UI build — pair with AE for the red-team app.

**Honest note:** Steps 1–2 (AE/DB) are capability *breadth*; only Step 3 (PR G) moves the scaffolder
8→10 (correctness *depth*). If you have one focused block tomorrow, spend it on Step 3.
