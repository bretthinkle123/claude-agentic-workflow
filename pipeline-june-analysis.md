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
soft glance. `/code-review` (the multi-agent reviewer) is wired as a **standard review-only
pre-step** (PR I) so the human reviews an already-triaged diff. Cheap, high-value for production confidence.

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
  - **F2-node (found 2026-07-02, prepping M2 run #2).** PR F's greenfield `.gitignore` fix was
    **Python-only** — `bootstrap-project.sh` emitted no `node_modules/`, `dist/`, `coverage/`, or
    `.stryker-tmp/`. Because the change-set is `git ls-files --others --exclude-standard` (honors
    `.gitignore`), an un-ignored `node_modules/` would flood the change-hash, `lockfile-check.sh`, the
    SBOM, and the human diff review on any Node run. **Fixed:** bootstrap now emits the Node build
    ignores **unconditionally** (it runs before any `package.json` exists — implementation creates it
    mid-run — so stack-detection there would miss it; the entries cost nothing in a Python project).
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

> **MILESTONE (2026-07-06): Track 2 COMPLETE — the pipeline is a 10/10 fully-functional system.**
> PRs **L ✅ (CI merge gate, #28) → M ✅ (build+provenance, #29) → N ✅ (envs+progressive delivery+load, #30)
> → O ✅ (observability + read-only triage agent, #31) → P ✅ (scale/DR+cost+continuous-vuln, #32)** are all
> merged and live. The pipeline now **authors → reviews → ships → operates → validates scale/DR** without
> breaking the fresh-context / file-handoff / deterministic-gate invariants — it extends them rightward
> across the merge boundary. `eval` is a required check on `main`; harness 21 suites / 355 assertions. The delivery half is
> per-project scaffolding (opt-in / self-skipping workflows), so its true proof is a supervised first run on
> a real containerized app (the M2 rule) — deliberately not faked. **Remaining ⬜ is off the critical path:**
> the macOS-bound **iOS gate adapters** + **SB Swift slice**, and the
> pure-housekeeping **DOC** / **SK** (**CQ** landed 2026-07-06). Both "10/10" milestones (scaffolder *and* fully-functional) are reached.

**Critical path:** `M2 ✅ → PR F ✅ → PR G ✅ (M1) → PR H ✅ (M8) → PR I ✅ (M5·M6·F3) → PR J ✅ (Polish)` →
**[10/10 scaffolder reached]** → `PR L ✅ (CI) → PR M ✅ (build) → PR N ✅ (envs+load) → PR O ✅ (observability) → PR P ✅ (scale/DR)`
→ **[10/10 fully-functional reached]**. **PR K (M9)** and the **side-tracks** run in parallel — none on the
critical path. Done: **K ✅, AE ✅, ASVS ✅, DS ✅ (design-spec stage), DP ✅ (data-protection), DB ✅,
SEC ✅, DEP ✅, ASVS-DET ✅ (Slices A–D), STORE ✅ (Layers A–E merged as PR #27, 2026-07-06;
SC-6/7/9 follow-up built 2026-07-06 — the plan is fully delivered)**. Partial: **EG ◑ (egress — slices done, proxy operator-provisioned), SB ◑
(scanner breadth — slices 1–3 done, Swift slice 4 deferred to iOS), FE ◑ (design-review Layer 4
built 2026-07-05; the Playwright capture is runtime-bound — needs a browser install), DAST ◑
(Layer 1 merged as PR #26, 2026-07-06; Layers 2–4 remain — L4 content-only, L2/L3 unblocked now
that PR L's CI and PR N's staging exist)**. **CQ ✅ (CodeQL CI job, built 2026-07-06)**. Still ⬜:
**iOS gate adapters (macOS-bound; assurance stamp built), DOC, SK**.

> **Status (2026-07-01):** **Track 1 is COMPLETE — the pipeline is a 10/10 scaffolder.** PRs F, G, G6,
> H, I, J are all **merged and live** (F #7, G #8, G6+AE #9, H #10, I #11, J #12). Harness on `main` is
> **101 assertions green**. A green run now means *correct + criterion-complete + reviewed*, with lean
> authoring agents. Remaining work is all parallel/optional: Track 2 (L–P, the last 40% = delivery +
> ops) and the side-tracks (K, FE, DOC, SK) — all still ⬜.

> **Status update (2026-07-05):** the security + front-end side-tracks advanced substantially since
> the 2026-07-01 snapshot. **Merged to `main`:** **PR K** (engine threat model + marker guard);
> **ASVS 5.0.0** enforcement + ASVS-DET Tier-1 SAST; the **design-spec stage** (DS — untrusted
> design bundle → human-vouched `design-spec.md` + injection report + forgery guard) and the **native
> iOS/SwiftUI planning layer**; **DP** (per-field at-rest enforcement, a new loop-exit gate floor);
> **EG** (default-deny egress — allow-list + detection built, Layer-2 proxy operator-provisioned);
> **SB** (Gitleaks + `trivy fs` + Semgrep stack menu; Swift slice deferred); **ASVS-DET Slices C/D**
> (T1-5…T1-8 + Tier-2 T2-3…T2-6), the **reduced-assurance stamp** (`run-summary.sh`), and **FE
> Layer 4 design-review** (deterministic budget compare + runtime-bound Playwright capture). The
> eval harness at that point was **17 suites** (added `asvs`, `waiver-guard`, `asvs-sast`,
> `design-spec`, `egress`, `assurance`, `design-review`). Track 2 (L–P delivery/ops), the macOS-bound
> **iOS gate adaptation** + **SB Swift slice**, and **CQ** (CodeQL CI) are the outstanding forward work.

> **Status update (2026-07-05, later — two runtime-security side-tracks reached PRs):** the two
> remaining ⬜ security/mobile side-tracks were **built, self-audited, and pushed as stacked PRs**
> (not yet merged):
> - **DAST — PR #26 (open, base `main`).** Layer 1 (post-GREEN local advisory ZAP passive baseline,
>   two-script runtime/pure split, opt-in via `dast.env`, fail-safe no-op). Self-audit caught + fixed
>   a **false-clean** (unreachable target → empty report → "within budget"; added a reachability
>   precheck) and removed a copied egress-network opt-in that would have blocked `host.docker.internal`.
> - **STORE — PR #27 (open, base `feat/dast-runtime-security`; stacked on #26, auto-retargets to
>   `main` when #26 merges).** Layers A–E (deterministic `store-compliance.sh` gate + Google Play
>   skill + planning/plan-audit/test-conventions prose + the Android reduced-assurance arm). Went
>   through a **hard audit pass** that found and fixed, in order: a **HIGH `git ls-files` tracked-only
>   bug** (the hook and the assurance stamp no-oped on a real app because its files are *uncommitted*
>   when they run — the deploy agent commits last; now scans tracked **and** untracked), a
>   **spaced-path** word-split, an **SC-2 comment false-positive**, then **added SC-5's Gradle
>   `release`-buildType `debuggable` form** (block-aware so the legitimate `debug { debuggable true }`
>   never fires) and fixed a **string-literal false-positive** in that detector (string-aware brace
>   walker). `store-compliance` suite grew **15 → 22** assertions along the way.
>
> The eval harness is now **19 suites / 318 assertions** (added `dast-review`, `store-compliance`;
> `hash-determinism` was already present). **Both PRs are advisory/opt-in or target-gated — neither
> can fire on a non-mobile / non-opted-in project.** Merge order: **#26 before #27.** After they land,
> every ⬜ *non-Track-2, non-macOS* side-track is closed except **DOC** and **SK** (both pure
> content/housekeeping, off the critical path). The next real forward investment is **Track 2 — PR L
> (CI as the merge gate)**, which is also the DAST/CQ home (re-homes DAST into CI, blocking-on-High).

### Done (2026-06-30)
- ✅ **M2 run #1** — pipeline built + shipped `linkly-pipeline-test` PR #1 end-to-end, independently
  audited. Findings in §8. *Headline: test rigor was better than feared; the real gaps are F1/F5.*
- ✅ **PR F — M2 fast-fixes** (**merged as PR #7**, 2026-07-01): **F2** bootstrap `.gitignore` now
  excludes Python test/coverage/db artifacts (kills the currency-anchor break); **F4** per-agent
  `maxTurns` bumped (testing 10→30, impl 25→40, docs 10→25, etc.). Shipped as a **combined PR** that
  also carried **SEC** + **DEP** (see the side-track rows) and the implementation `opus`→`sonnet`
  revert; `system_architecture.md` + `agentic-pipeline-plan.md` + decision docs synced. *Remaining M2
  nits F3, F6 are folded into PR I / PR G below.* **Merged but not yet live — still needs
  `install-global.sh` + restart.**

### Track 1 — harden the authoring engine → **10/10 scaffolder**

| PR | Item | Effort | Depends on | Closes | Why here |
|---|---|---|---|---|---|
| **F** ✅ | M2 fast-fixes (`.gitignore` + `maxTurns`) | S | M2 | F2, F4 | Unblocks a clean second run; **merged as PR #7** (bundled SEC + DEP + the impl revert). Needs publish to go live. |
| **G** ✅ | **Quality + criterion-completeness gate (M1, retargeted by M2)** — enforce that every *measurable dimension* of an acceptance criterion is actually exercised (fail F1: a perf budget naming `throughput_rps` while the test only measures serial latency). **Decisions (2026-07-01):** the *only* new hard gate check is the **deterministic perf-pairing** (a non-null `perf.budget.*` must have a non-null `perf.measured.*`), folded into the existing `deployment-gate.sh` and mirrored into the loop-exit (loop-exit ≡ gate) — **no new gate hook.** Mutation testing (mutmut/Stryker, **scoped to changed core modules**) + an adversarial "what does this test *not* catch" review land in a new **advisory** `test-quality.json` (**no gate reads it**; documentation surfaces it). Branch coverage (F5) is **surfaced, not gated.** **F6 split out** into its own PR (integrity plumbing, not gate logic). | L | F | F1, F5 | **The #1 gap and the biggest single lever.** M2 proved tests aren't tautological but *can* under-cover a criterion while scoring it complete. Built against the real Linkly artifacts. **Merged as PR #8; published + live.** |
| **G6** ✅ | **Results-file integrity nits (F6)** — a **real** `ran_at`: agents are told to write it via `date -u`, and a deterministic **`stamp-ran-at.sh` Stop hook** (first on testing + security) re-stamps it to real UTC as the enforcement layer (two-layer, like the perf gate — never a placeholder midnight). Plus the orchestrator stamps a **terminal `loop-state`** on GREEN exit (`loop-guard.sh done` → `status:"completed"`, which refuses to overwrite a `capped` cap-out; previously only cap-out wrote a terminal status). Carved out of PR G to keep the gate-logic change isolated (don't-bundle rule). **Shipped with AE** (both cheap non-gate plumbing). **Merged as PR #9; published + live.** | S | G | F6 | Small integrity plumbing; no gate logic, so it ships separately from the PR G gate change. |
| **H** ✅ | **Pipeline eval/regression harness (M8)** — **built** as `tests/` (hand-rolled bash + jq, zero new deps, **deterministic-only** by decision — no model calls). `bash tests/run-eval.sh` runs 6 suites against a golden Linkly fixture (fixture #1): `static` (hooks parse; every agent-wired hook resolves; predicates compile), `gate` (green pass + each block reason incl. **perf F1**), `loop-guard` (caps → `capped`; `done` → `completed`; won't overwrite `capped`), **`loop-exit-invariant`** (`deployment-gate.sh` verdict ⟺ the canonical loop-exit predicate across a matrix + a SKILL substring drift-guard — the highest-value test), `stamp-ran-at` (placeholder→UTC; no-op paths), `record-clean`. Locks in G's perf-completeness, G6's terminal `completed`, and the enforced `ran_at`. Proven to catch all three regression classes (gate break, SKILL drift, hook rename). Exit-code CI-ready (PR L wires it). Repo tooling — **not** published to `~/.claude`. *Deferred: live LLM golden-runs; gate jq-missing + currency checks (manual).* **Merged as PR #10; extended to 101 assertions by PR I.** | M | G | — | You edit agent prompts constantly; nothing catches a regression today except a full manual run. |
| **I** ✅ | **Review + supply-chain + data safety (M5 + M6 + F3)** — built as **one PR**, **merged as PR #11** (2026-07-01). **M5+F3:** hard human **diff-review** gate — `approve-diff.sh` (TTY-only, so a subagent can't approve via the helper — direct-fabrication hardening tracked in PR K) writes `diff-approved` carrying the approved change-set hash, which **becomes the deploy gate's currency anchor** (replacing the deployer-regenerable `reviewed_change_hash` → removes the F3 vector); **`/code-review` wired as a standard automated review-only pre-step** so the human reviews an already-triaged diff. **M6 supply-chain:** deterministic `lockfile-check.sh` (manifest-without-lockfile blocks via `critical_count`; unpinned deps warn) + best-effort CycloneDX `generate-sbom.sh` (`sbom.cdx.json`), both run by security; documentation surfaces them. **M6 data-safety:** testing's migration round-trip (5c) elevated to a **prod-shaped seed** (assert seeded rows survive down+up) + a **backup-before-migrate** convention in `deployment-checklist-and-rollback`. Harness extended (`diff-approved`, `lockfile-check` suites; git-backed fixture) — 101 assertions green. | M | G | F3 | Makes a green run *trustworthy* and closes "bad dep / unsafe migration / silent re-anchor." |
| **J** ✅ | **Token/altitude polish** — **merged as PR #12** (2026-07-01). Extracted long always-loaded reference blocks out of `planning.md` (254→226 ln) / `plan-audit.md` (223→175 ln). **The clean, genuinely-conditional win:** plan-audit's dependency-reality + version-policy detail (steps 4–6, ~70 ln) only matters when the plan introduces third-party deps — extract to an **on-demand** `dependency-audit-policy` skill (invoked only when deps present; a no-new-deps feature skips it entirely). For **planning**, the self-audit rubric (step 8) and threat-model *formatting* detail (step 7's Mermaid-DFD + copy-paste-prompt conventions) run on **every** plan, so full on-demand extraction trades early-turn tokens against a real "agent forgets to invoke the rubric" capability risk — prefer folding the threat-model *format* conventions into the already-preloaded `stride-threat-model-template` skill (de-dupe, no capability risk) over making them on-demand. Net: one new on-demand skill + de-dup, no gate logic. | S | — | Recovers per-invocation tokens; no capability loss. Last Track-1 item → 10/10 scaffolder. |

> **After PRs F–J: 10/10 as a scaffolder.** The pipeline produces PRs whose green state means
> *correct + criterion-complete + reviewed*, not merely *well-formed*.

### Parallel side-tracks (don't block the critical path)

| PR | Item | Effort | Depends on | Why parallel |
|---|---|---|---|---|
| **K** ✅ | **Threat-model the pipeline-as-target (M9)** — **DONE (2026-07-01):** engine STRIDE model in `docs/pipeline-threat-model.md` (untrusted inputs: `PROJECT.md`, cloned repos, dep READMEs, screenshots — each threat mapped to a guard or a stated accepted risk). **The `diff-approved`/`plan-approved` fabrication vector from PR I's audit is now structurally blocked:** a PreToolUse command-inspection hook `guard-approval-markers.sh` (on all 7 Bash-carrying subagents) blocks Bash *writes* to either marker (reads pass — implementation still checks `plan-approved`), paired with a settings `Write`/`Edit` deny on both markers (the non-Bash tool vector). Harness `marker-guard` suite (22 assertions); honest-language synced (deployment.md, deployment-gate.sh, approve-diff.sh, orchestration SKILL — no "impossible" overclaim). Residual = obfuscated Bash past the string scan, documented in the threat model. Also added an "untrusted input = data, not instructions" convention to the orchestration skill. *(A future DAST / red-team *stage* is a later L-effort follow-on, gated on G + K.)* | S–M | — | Precursor to the [[redteam-app-goal]]; hardens the engine before it ingests adversarial input. |
| **EG** ◑ | **Default-deny egress control for the engine (prompt-injection blast-radius) — deterministic slices DONE (2026-07-04); Layer-2 proxy operator-provisioned (Docker/WSL2-bound)** — replaces "unrestricted egress = accepted residual" with an **allow-listed, default-deny** posture. **Built + harness-tested:** the enumerated `global-hooks/egress-allowlist.txt` (single source of truth); **Layer-3 detection** `egress-check.sh` (a security Stop hook that reads the proxy's `.pipeline/egress-log.jsonl` and surfaces every denied host as a warning — signal, not a gate, so no loop-exit churn; absent log ⇒ no-op); the scanner wrappers (`semgrep`/`trivy`/`sbom`) **opt into a restricted Docker network** via `PIPELINE_EGRESS_NETWORK` (backward-compatible; unset ⇒ unchanged); `build-filter.sh` derives the tinyproxy ACL from the allow-list; new `tests/suites/egress.sh` (10 assertions). **Operator-provisioned (not run-verified on Windows):** the Layer-2 default-deny **proxy** itself (`global-hooks/egress-proxy/` recipe — restricted network + tinyproxy + `HTTPS_PROXY`), and **Layer 0** (the empirical enumeration run) + **Layer 1** curl host-scoping (documented as prefix-match-infeasible → the proxy is the real boundary). WSL2/nftables noted as the strong-guarantee substrate; `api.anthropic.com` out of scope. **Threat-model §4 updated:** the "unrestricted curl egress (accepted)" residual → a default-deny control + denied-attempt logging, residual narrowed to "an allow-listed host abused as the channel." **→ Full spec: `docs/egress-control-plan.md`.** | S–M (per slice) | K | Follow-on to K; hardens the engine before it consumes runtime secrets or the [[redteam-app-goal]]'s adversarial input. Contains injection's #1 payload (exfiltration) without trusting the model to resist it. |
| **DP** ✅ | **Data-classification + at-rest protection enforcement (built apps) — DONE (2026-07-04)** — forces, not just advises, that every stored field carrying sensitive user data has a named at-rest control. All six layers built on the input-surface/BOLA accountability model: a `data-protection-conventions` skill (classification taxonomy → KDF for passwords / KMS envelope field-encryption for sensitive PII / SSE for personal + crypto-facade rule); planning classifies each stored field + emits a `data_protection` criterion per sensitive field in `acceptance.md`; **plan-audit material flag** for any sensitive field with no named mechanism; a persisted-form test shape in `test-conventions` (raw stored value is ciphertext/hash, not plaintext) riding `criteria_covered`; a security-agent `data_surface.unprotected` reconciliation with a **deterministic deploy-gate floor** mirrored into the loop-exit predicate (SKILL + `loop-exit-invariant.sh` SEC_PREDICATE/battery/matrix + green fixture — `loop-exit ≡ gate` intact, invariant 22 / gate 26); STRIDE Info-Disclosure now requires a named at-rest control per sensitive field. **Closes the real hole:** a non-exploitable unencrypted sensitive column that today ships as an ASVS *warning* (Checkov only forces *infra-layer* SSE/TLS, and only when `infra/` exists) is now a *block*, regardless of exploitability. **→ Full spec: `docs/data-protection-enforcement-plan.md`.** | S–M (per layer) | — | The app-security counterpart to input-controls; closes "sensitive data stored/moved without encryption ships green." Just-in-time enabler for any app handling PII/money/health (incl. [[redteam-app-goal]]). |
| **SB** ◑ | **Security-scanner breadth (local-loop coverage) — slices 1–3 DONE (2026-07-04); slice 4 (Swift) deferred to the iOS row** — broadens the security agent's deterministic scanning **without** a redundant SAST. **Built:** **(1) Gitleaks** — dedicated secrets scan via `gitleaks-scan.sh` (native-binary-first, Docker-fallback like semgrep/trivy), security step 2b, folded into `critical_count`; a second opinion beyond regex-grep (6a) + Semgrep `p/secrets`. **(2) Trivy `fs` mode** — security step 4c runs `trivy fs --scanners vuln,secret,misconfig .` for broad multi-ecosystem SCA + secret + misconfig, a second SCA opinion alongside OSV, reusing the Docker wrapper. **(3) Semgrep `<STACK CONFIGS>`** — the `semgrep-ruleset-guide` placeholder is now a real **stack→ruleset menu** (p/python, p/django, p/react, p/nodejs, p/golang, p/dockerfile, …) the agent selects from, so framework depth isn't left unscanned. **Deferred:** **(4) Swift SAST adapters** (Semgrep-Swift + SwiftLint + adapt 6c/6g to SwiftUI) — macOS/iOS-bound, tracked in the **iOS** row + `docs/ios-swiftui-target-plan.md`. Every tool folds into the existing `critical_count`/`warning_count` + `security-status.json` exactly like OSV/Checkov/Trivy — **no new gate/predicate, zero loop-exit-invariant churn**. **CI-depth complement = CodeQL (CQ, Track 2).** | S–M (per slice) | — | Adds coverage only on axes that yield a *new* signal (secrets depth, multi-ecosystem SCA, per-stack rules); deliberately avoids a redundant second SAST. Enabler for the iOS target + [[redteam-app-goal]]. |
| **FE** ✅◑ | **Front-end workstream** (see [[deferred-frontend-workstream]]) — **shippable slices, mostly built:** the **design-spec stage + design-system skill BUILT (row DS)**; **design-review Layer 4 (visual-regression + a11y budget) BUILT (2026-07-05)** — deterministic budget compare (`design-review-check.sh` + `tests/suites/design-review.sh`) + advisory PR surfacing; the Playwright capture (`ui-capture.sh`/`.mjs`) is **runtime-bound** (needs a browser install), fail-safe no-op otherwise. Remaining ◑: the **iOS/SwiftUI target's macOS gate work (row iOS)**. | L | — | A parallel quality axis; does **not** move production-readiness. Slot it when an active build has a UI. |
| **AE** ✅ | **`api-edge-conventions` skill** (`global-skills/api-edge-conventions/SKILL.md`): rate limiting/throttling, CORS, security headers, error-envelope facade, idempotency, outbound timeouts/retries. **WIRED as on-demand** — trigger added to the *on-demand skills* prose paragraph in the `planning` + `implementation` agent **bodies** (NOT `skills:` frontmatter — that forces preload; both agents already carry the `Skill` tool); folder committed; `list-skills.sh --annotate` registers the breadcrumb. **Shipped with G6.** Optional `scaffold/middleware.py` still deferred. **Merged as PR #9; published + live.** | S | — | Per-project HTTP-hardening axis; the *implementation* counterpart to STRIDE's DoS/Tampering. Just-in-time enabler for the [[redteam-app-goal]] (HTTP surface). Not critical path. |
| **ASVS** ✅ | **OWASP ASVS 5.0.0 verification layer — first-class & enforced (2026-07-03)** — a deep 17-chapter L1/L2/L3 checklist (`global-skills/stride-threat-model-template/asvs-5.0-checklist.md`, on-demand sibling) threaded through the pipeline: **planning** emits a `## ASVS Compliance` block (triggered chapters, in-scope L3, waivers) + a STRIDE→ASVS map; **plan-audit** material-flags a missing block; **implementation** builds L1/L2 + in-scope-L3 as definition-of-done; **security step 6g is ENFORCING** — an unmet, unwaived **code/config** L1/L2 (or in-scope L3) item is a **critical** → blocks via the existing `status` gate (documentation/org-level items advisory). Emits an `asvs` reconciliation object; `status:clean` requires `asvs.reconciled`. **Policy: L1+L2 universal, L3 project-specific.** Rides the existing gate (no new predicate → zero loop-exit-invariant churn); new `tests/suites/asvs.sh` (10 assertions, harness green). Complements the Top 10 (SAST net) + STRIDE. First shipped advisory (2026-07-02), promoted to enforced (2026-07-03). **Hardened (2026-07-04):** a deterministic `asvs.reconciled` **deploy-gate + loop-exit floor** (so a `status:clean` that contradicts an unreconciled ASVS state can't ship — mirrored, `loop-exit ≡ gate` intact); a **fail-safe classification** (ambiguous item → blocking, never silently advisory); and **Option B human-owned waivers** — `record-waiver.sh` (TTY-only) writes `.pipeline/waivers.json`, `guard-approval-markers.sh` + settings deny block agent writes, and the gate rejects any `osv_waiver`/`asvs.waivers` the agent claimed without a human record (`tests/suites/waiver-guard.sh`; also hardens `osv_waiver`). | M | — | Makes verifiable security requirements as first-class as STRIDE/Top 10; enabler for [[redteam-app-goal]]. |
| **DS** ✅ | **Design-spec stage — untrusted design bundle as authoritative-but-vouched input (2026-07-04)** — a **conditional pre-planning stage** (runs iff a `design/` dir / a PROJECT.md design-source declaration / a wired Figma MCP is present; skipped entirely otherwise, so default runs are unchanged). New **`design-spec` agent** (opus; `Read, Write, Skill, mcp__figma`) normalizes a Claude Design / Figma export / screenshots (or a Figma MCP pull) into **`.pipeline/design-spec.md`** — screen/component/token inventory, layout & interaction intent, a REQUIRED *needs-native-mapping* section, and a **provenance + injection report** (every instruction-shaped string embedded in image/HTML/layer-name text is quoted and marked NOT ACTED ON — the design bundle is **untrusted data**, the highest-risk injection carrier). New **`design-system-conventions`** skill is the extraction schema. A **human `design-approved` checkpoint** (in-session; orchestrator writes JSON `{approved_at, note, design_spec_hash}`) vouches for **visual intent only**; **planning** treats the spec as authoritative **only if the marker exists AND the recomputed spec hash matches** (currency, mirrors F3), else falls back to reading a raw export directly — and traces design→plan→AC. **Forgery-guarded** like plan/diff-approved: `design-approved` added to `guard-approval-markers.sh` + settings `Write`/`Edit` deny (stops the Write-holding design-spec agent self-approving). **No design content ever reaches a `jq` gate → zero loop-exit-invariant churn** (the checkpoint gates *authority*, not a deploy). New `tests/suites/design-spec.sh`; harness green. Implements Layers 0–3 of `docs/design-spec-stage-plan.md`; **Layer 4 (post-build visual-regression design-review) was BUILT 2026-07-05** — see the FE row. | M | K (marker-guard) | The design-input channel the front-end workstream lacked; secures the screenshot/design path (injection report + human vouch); enabler for [[redteam-app-goal]] (adversarial design input). |
| **iOS** ◑ | **Native iOS/SwiftUI target — planning/build competence + honest gate adaptation (DEFERRED, macOS-bound)** — **planning/skills layer is BUILT** (PR #21: `planning.md`/`implementation.md` iOS routing + faithful-replication rule; the 4 skills `swift-conventions`/`apple-hig-compliance`/`claude-design-to-swiftui`/`app-store-submission-requirements`). **What remains and is DEFERRED is Layer 3 — the honest gate adaptation** (`docs/ios-swiftui-target-plan.md`): `xcodebuild build/test` smoke on a **macOS runner**, a Semgrep-**Swift** ruleset + Swift-package SCA (the security slice = SB(4)), and an `xccov`/llvm-cov coverage adapter. **The `assurance: "reduced (swift adapters absent)"` stamp IS BUILT (2026-07-05)** — `run-summary.sh` detects a Swift target with absent adapters and stamps `run-summary.json` so an iOS run **self-declares "not gate-verified"** instead of a vacuous green (documentation/orchestration honor it; `tests/suites/assurance.sh`). **Hard external dependency for the rest:** the `xcodebuild`/`xccov`/Semgrep-Swift adapters are macOS/Xcode-bound and **cannot be built or validated on the Windows dev host** — they need a macOS runner + an actual iOS project, so they're deferred by construction. Until they land, iOS runs are honest-but-reduced-assurance (now *stamped* as such). | L | DS, SB(4), macOS runner (external) | Only pays off when an actual native-iOS app is built; deferring avoids shipping unverifiable, platform-bound gate code. Full plan already written (`docs/ios-swiftui-target-plan.md`). |
| **ASVS-DET** ✅ | **ASVS determinism promotions (Tier 1/2) — DONE, Slices A–D (2026-07-04/05)** — promote high-value ASVS requirements from agent-reasoned (6g) to **deterministic**. **Slice A:** `asvs-sast.sh` (JWT `alg:none` 9.1.2, password-KDF 11.4.2, CSPRNG 11.5.1, insecure-cipher 11.3.1) — a security Stop hook + a deploy-gate `critical>0` floor (deploy-only, no loop-exit churn), `tests/suites/asvs-sast.sh`. **Slice B:** Tier-2 **T2-1 auth-required** + **T2-2 safe-error** as plan-audit **material flags** + `test-conventions` shapes (ride `criteria_covered`). **Slice C (2026-07-05):** T1-5 cookie-flag disable (critical) + T1-6 debug/stack-trace (advisory); Tier-2 T2-3…T2-6 (token expiry/audience, session rotation/logout, txn rollback, breached password). **Slice D (2026-07-05):** T1-7 CORS/CSP/X-Frame + T1-8 sensitive-in-URL (advisory warnings). **→ Full spec: `docs/asvs-determinism-roadmap.md` (all rows ✅).** Already-done pre-slice: 8.2.2 IDOR/BOLA, input-controls (2.2.x/2.4.1), injection/secrets/CVE. Only Tier-3 judgment items remain under 6g, by design. | M (per slice) | ASVS | Narrows the agent-trusted surface to genuinely-semantic items; closes the "agent under-reports a miss" residual the waiver guard can't. Hardening for [[redteam-app-goal]]. |
| **DAST** ◑ | **Dynamic app-security testing (runtime) — `docs/dast-plan.md`** — closes the audit's #1 security gap: every existing control (Semgrep/OSV/Trivy/Gitleaks/ASVS) analyzes code **at rest, pre-merge**; nothing attacks the **running** app. **Layer 1 ✅ BUILT (2026-07-05):** a post-GREEN local advisory stage, two-script split like design-review Layer 4 — `dast-capture.sh` (runtime-bound: boots the app, runs OWASP ZAP passive baseline in Docker, opt-in via `dast.env`, fail-safe no-op) + `dast-review.sh` (deterministic: severity tally vs `dast-budget.json` → advisory `dast-review.json`); templates, orchestration stage 4e, documentation PR-surfacing, `tests/suites/dast-review.sh` (12 assertions). Advisory, never a gate, not in loop-exit. Docker-only at Layer 1 — with PR L's CI merged the blocking-on-High CI re-home is now unblocked. **Self-audited** (fixed a false-clean via a reachability precheck; removed an egress-network opt-in that would block `host.docker.internal`) and **merged as PR #26 (2026-07-06).** **Layer 4 ✅ BUILT (2026-07-06, PR #33):** the `dast-conventions` skill (layer guarantees + opt-in mechanics + tuning/false-positive protocol), planning's DAST-readiness ACs for any served HTTP surface (DAST-1 served OpenAPI schema; DAST-2/3 seeded test user + auth context when authenticated), and a plan-audit **material flag** for a served-HTTP plan missing them — so apps arrive at the fuzz layer ready, not as a broken job. **⬜ Remaining:** Layer 2 (Schemathesis API fuzz) → Layer 3 (authenticated ZAP active scan — nightly vs staging); their staging dependency shipped with PR N (#30). Records the pen-test-tool decision: build both; give the separate Burp-based tool a **headless CI mode** so it can *become* this DAST engine later. | S–M (per layer) | **L1 done (PR #26); L4: content-only (ready)**; L2/L3: L (CI) + N (staging) | Runtime-security axis, parallel to M–P like CQ; the every-merge automated complement to manual pentesting + the [[redteam-app-goal]]. **Was absent from Track 2 — this row adds it.** |
| **STORE** ✅◑ | **App-store compliance gate (Apple + Google Play) — `docs/store-compliance-plan.md` — merged as PR #27 (2026-07-06)** — makes store-submission requirements accountable at planning/gate time for a declared store target, reusing the ASVS Tier 1/2/3 pattern. **Layers A–E ✅ BUILT + AUDIT-HARDENED (2026-07-05):** **E** reduced-assurance stamp now covers Android (was mis-stamped `standard`); **C** deterministic `store-compliance.sh` (security Stop hook, own JSON, deploy-gate `critical>0` floor, repo-state scoped, `tests/suites/store-compliance.sh` **22 assertions**) — SC-1 privacy manifest, SC-2 usage strings, SC-3 ATS, SC-4 targetSdk floor, SC-5 debuggable (**manifest *and* the block-aware Gradle `release`-buildType form**), SC-8 export key; **A** `google-play-submission-requirements` skill (Play competence, mirrors the Apple skill); **B** planning store-target routing + store ACs; **D** Tier-2 plan-audit flags + `test-conventions` shapes (SC-T2-1 data-declaration reconciliation first, DP-unblocked). Mobile-target detection narrowed to platform-specific markers so a JVM/Gradle backend or desktop app is never mis-scoped. **Audit trail (found + fixed in-branch):** a **HIGH `git ls-files` tracked-only bug** (hooks no-oped on a real app — its files are uncommitted at the security/GREEN stages since the deploy agent commits last; now scans tracked **and** untracked), a spaced-path word-split, an SC-2 comment false-positive, and — for the new SC-5 Gradle form — a string-literal false-positive (fixed with a string-aware brace walker so the legit `debug { debuggable true }` never blocks a deploy). **Layer-C follow-up ✅ BUILT (2026-07-06, PR #33):** SC-9 Required-Reason API ↔ `NSPrivacyAccessedAPITypes` compare (critical — what Apple's upload tooling actually enforces; runs only against an existing manifest so it never double-counts SC-1, release source only), SC-6 permission declared↔used both directions (advisory, conservative API map), SC-7 debug-log flood + hardcoded localhost/emulator endpoints (advisory, threshold-based, ://-aware comment strip so URLs survive); suite 22 → **32 assertions**. The store-compliance plan is now fully delivered. | S–M (per layer) | ASVS-DET (pattern), DP (SC-T2-1), per-store competence (iOS + Android skills built) | The "sellable on an app store" accountability axis; parallel to the mobile/front-end work. Gate-time accountability only — never a guarantee of store acceptance (human review). |
| **DOC** ⬜ | **Documentation consolidation / de-clutter** — the repo's `.md` set has proliferated (`docs/` spec + companions, root-level `pipeline-june-analysis.md` / `pipeline-revision-plan.md` / `m2-test-plan.md`, the memory mirror). Audit, dedupe, and consolidate into a coherent structure: one index, clear source-of-truth-vs-historical separation, archive or retire superseded docs. | M | — | Pure housekeeping — touches no agents/hooks/gates, blocks nothing. Deliberately **last**: do it once the Track 1 churn settles, so you're not reorganizing docs that are still changing. |
| **DB** ✅ | **Debugging-agent upgrade** — `opus`/`xhigh` was **already live** (applied in the §3.1 retune); on 2026-07-01 bumped `maxTurns` 25→30 to match the other reasoning stages (planning/testing/security 30, impl 40). Fires only on failure so absolute cost is negligible. **Distinct from PR O** (the production-debugger / Sentry workstream). *Needs `install-global.sh` to publish.* | S | — | Done. Cheap capability parity for an existing stage. |
| **SEC** ✅ | **Security-agent upgrade (2026-07-01)** — model `sonnet`→**`opus`** (**overrides** the 2026-06-29 `sonnet/high` settled decision — 6f added independent reasoning; knowingly accepts the higher all-models-cap draw, and revert-to-Sonnet stays clean if that cap becomes the bottleneck); new **step 6f — STRIDE delta / attack-surface reconciliation** (reconciles the implemented diff's new/changed surface against the plan's threat model — exploitable-and-fixable gaps patched in place, design-level gaps raised critical → debugging); **Complete findings inventory** (every finding reported regardless of severity/exploitability/remediation) + `total_findings`/`stride_new_threats` status fields; **`surface-delta.md` hybrid** (implementation emits an attack-surface hint, security reconciles it against the diff — diff is the source of truth). Specs (`system_architecture.md`, `agentic-pipeline-plan.md`) + decision docs synced. *Needs `install-global.sh` to publish.* | M | — | New capability (not an M-item): closes "the built app drifts from the planned threat model," strengthens §2. **Distinct from PR K**, which threat-models the *pipeline*, not the built app. |
| **DEP** ✅ | **Deployment-agent upgrade (2026-07-01)** — model `haiku`→**`sonnet`** (maxTurns 8→15) to support a new **read-only pre-commit content inspection** step: scan the change set for secrets, build/dependency junk, `.pipeline/` interlock files, and conflict/debug markers before the pipeline's single commit, stopping for a human on a hit (pairs with an expanded `deployment-checklist-and-rollback` skill). Overrides the earlier `deployment=haiku` allocation — the inspection is real judgment Haiku handles poorly. Docs synced. *Needs `install-global.sh` to publish.* | S | — | A safety win on the highest-stakes stage: stops secrets/junk landing in the PR at the commit boundary. |
| **SK** ⬜ | **Skill-file enrichment (mine public skills)** — systematically beef up the agents' backing `SKILL.md` files by mining high-quality public skills (primary source: [anthropics/skills](https://github.com/anthropics/skills), **mixed-license — see caveat in the detail below**; secondary: permissively-licensed community skills) and splicing **only the *additive* techniques/checks** into our local skills, **adapted to pipeline vocabulary** (interlock files, gate semantics, STRIDE-mechanism rigor) — never verbatim copy that drags in foreign concepts. **First-pass order:** `planning` → `implementation` → `security` (rationale + exact skill inventory in the detail below); **remaining agents in a later pass.** **Content-only: no gate logic, no model/frontmatter changes** — does not relitigate the model-allocation notes below. **→ Full plan: "SK — Skill-file enrichment plan (detail)" after the Model-allocation notes.** | M | — | Quality axis on the authoring agents; touches skill *content* only, so it blocks nothing and stays off the critical path. Main risk is preload token tax — bounded by the per-addition bar + an on-demand-first preference. |

> **New plan docs (2026-07-05) — Track 2 now has detailed specs, not just one-liners.** The
> post-merge delivery half is written up: **`docs/ci-merge-gate-plan.md`** (PR L — the keystone;
> resolves the "CI re-runs vs. re-reads artifacts" question, adds design-record retention as a
> prerequisite) and **`docs/delivery-operations-plan.md`** (PRs M–P — artifact/provenance,
> environments/canary/load, observability + read-only triage agent, scale/DR, plus the audit's
> continuous-vuln-management / WAF / feature-flag / synthetics items). **DAST** and **STORE** are new
> rows in the table above (DAST was previously absent from the roadmap). L and M–P stay in **Track 2**
> below (they are the delivery critical path, not parallel), now backed by those docs; the `Depends on`
> and readiness detail live in each doc.

> **Model-allocation notes (2026-07-01):** security → `opus` (SEC row) and deployment → `sonnet` (DEP row). **Implementation was evaluated for `opus/xhigh` and deliberately kept on `sonnet/high`** — the plan carries the open-ended reasoning, the Linkly run (§8) produced rigorous output on Sonnet, and it is the highest-volume stage (the largest all-models-cap draw); the quality investment belongs in the audit / M1 layer (PR G), not in maxing the generator. `maxTurns` was bumped repo-wide (planning 30, plan-audit 20, implementation 40, debugging 30, security 30, testing 30, documentation 25, deployment 15).

#### SK — Skill-file enrichment plan (detail)

**Goal.** Raise the ceiling of the *authoring* agents by enriching the `SKILL.md` files they load
— importing the genuinely-additive techniques, checklists, and framings from mature public skills,
adapted to this pipeline's vocabulary. This is a **content** axis (better instructions per stage),
distinct from the SEC/DB/DEP rows (which changed *models/frontmatter*). It never touches gate logic.

**Sources & licensing (check before every import).**
- **Primary — [anthropics/skills](https://github.com/anthropics/skills): mixed-license.** Most skills
  are **Apache-2.0** (fine to adapt with attribution), but the document skills (`skills/docx`,
  `skills/pdf`, `skills/pptx`, `skills/xlsx`) are **source-available, NOT open source — do not import
  from those.** Confirm the per-skill license at import time; the repo root can change.
- **Secondary** — permissively-licensed community skills (Agent Skills are an open standard,
  `agentskills.io`, since Dec 2025). Accept **only** permissive licenses (MIT/Apache/BSD); skip
  anything unlicensed or copyleft.
- **Record source URL + license + commit/date per import**, so a future audit can trace provenance.
  Adapt ideas freely; flag any near-verbatim text with its source.

**Target inventory & first-pass order.** Preloaded skills come first within each agent — they cost
context on *every* invocation, so they carry both the highest leverage and the strictest token bar;
on-demand skills are secondary. Several on-demand skills are **shared** across planning +
implementation (`auth-patterns`, `logging-conventions`, `secrets-management`, `iac-conventions`,
`api-edge-conventions`) — enrich each once, both agents benefit.
1. **planning** — preload: `stride-threat-model-template`. On-demand: `ddia-patterns`,
   `auth-patterns`, `logging-conventions`, `secrets-management`, `iac-conventions`,
   `api-edge-conventions`, `containerization-conventions`. *(First: the STRIDE template — richest
   public prior art and it runs on every plan.)*
2. **implementation** — preload: `code-standards`. On-demand: `auth-patterns`, `logging-conventions`,
   `secrets-management`, `iac-conventions`, `api-edge-conventions`. *(First: `code-standards`.)*
3. **security** — preload: `semgrep-ruleset-guide`, `diff-scoping-conventions`. On-demand:
   `iac-conventions`.

Order rationale: planning is the highest-leverage authoring stage (its output constrains every
downstream stage) and its preloaded skill has the most external prior art; security is third only
because its skills are narrower/more tool-specific, not lower value. **Later pass** covers the
remaining agents (`plan-audit`, `testing`, `documentation`, `deployment`, `debugging`) and the
shared/on-demand skills not reached above — this is the "every agent eventually" scope.

**Method per skill (repeat for each).**
1. Pin source + record license/attribution (per the licensing rules above).
2. Fetch candidates, diff against our current `SKILL.md`, extract **deltas only** (what ours lacks).
3. **Token-budget triage** — a *preloaded* skill's addition must clear a "worth paying on every
   invocation" bar; if it doesn't, fold it into an **on-demand** skill instead. See the
   preload-vs-on-demand contract in [[testing-coverage-contract]].
4. Reword into pipeline vocabulary (interlock files, gate semantics, STRIDE-mechanism rigor); no
   foreign concepts, no contradictions with our gates/conventions.
5. Propose a **reviewable diff per file** with a one-line "why it earns its place"; Brett approves
   before it lands.
6. Dogfood through `bash tests/run-eval.sh` before merge (see the eval-drift caution below).

**Guardrails.**
- **Preload token tax is the main risk** — every line added to a preloaded skill is paid on every
  run of that agent. On-demand-first; measure line-count deltas.
- **Adapt, don't copy** — imports must read as ours; a copy-paste that introduces foreign vocabulary
  or a convention we don't follow is a defect, not an enrichment.
- **Eval-drift caution** — the `tests/run-eval.sh` `static` suite asserts every agent-wired skill
  still resolves, and PR H's `loop-exit-invariant` suite includes a **SKILL substring drift-guard**
  (it pins an exact substring of a SKILL body). Editing a guarded skill will fail the harness — the
  drift-guard currently targets the loop-exit text in `pipeline-orchestration` (a *later-pass*
  target, not one of the first three), but re-run the harness after any SKILL edit and update the
  guard string deliberately if it legitimately changed.
- **No scope creep** — content only; no gate logic, no model/frontmatter/`skills:` list changes
  (those are separate decisions). Enriching a skill's *body* is in scope; moving a skill between
  preload and on-demand is a frontmatter change → out of scope for SK (raise separately).

**Definition of done (first pass).** For each of planning / implementation / security: every
preloaded skill has either a merged enrichment diff or a logged "already sufficient" assessment;
their shared on-demand skills are at least triaged; all imports have source+license recorded;
`tests/run-eval.sh` is green. Then the side-track continues into the later-pass agents.

**Why it matters.** Better authoring skills compound — planning's threat-model rigor and
implementation's coding standards gate everything downstream, and richer security skills feed the
[[redteam-app-goal]]. It is deliberately off the critical path: the pipeline is already a 10/10
scaffolder without it.

### Track 2 — extend past the PR → **10/10 fully-functional (the last 40%, §7)**

Mostly per-project CI/infra the pipeline *scaffolds*, plus a few skills — not new pipeline agents.
L→M→N→O→P are strictly dependency-ordered (each presupposes the prior); **CQ and SC run parallel
to M–P** — added assurance, not delivery steps, and neither is on the 10/10 line.

| PR | Item | Effort | Depends on | Why here |
|---|---|---|---|---|
| **L** ✅ | **CI as the merge gate (P1) — BUILT + MERGED (2026-07-05, PR #28); full spec: `docs/ci-merge-gate-plan.md`** — all four layers: **Layer 1** `.github/workflows/eval.yml` (the engine's own merge gate — make `eval` a required check); **Layer 0** design-record retention (documentation copies plan/acceptance/plan-audit/security-report → `docs/decisions/<branch>/` before the review manifest, riding the human-approved hash); **SCAN_BASE CI re-run mode** in `asvs-sast.sh`/`guard-source-markers.sh`/`lockfile-check.sh` (a naive CI re-run was VACUOUS twice over: empty `git diff HEAD` on a merge commit + absent gitignored `state.json`; fail-closed on a bad ref; `tests/suites/ci-scan-base.sh` 15 assertions); **Layer 2** `templates/ci/pipeline-ci.yml` + bootstrap wiring (re-run scripts copied into each project's `scripts/ci/`); **Layer 3** the `ci-conventions` skill (honest-scope table + branch-protection checklist). **The first real CI run caught a real engine bug:** every `.sh` was committed 0644 (Windows `core.fileMode=false`) → `deployment-gate.sh`'s direct sibling invocation hit Permission denied on Linux → gate blocked green states. Fixed threefold (exec bits committed, sibling invocations bash-explicit, static-suite mode guard — self-enforcing now that the harness runs in CI). Harness **20 suites / 334 assertions**. `post-deploy-check` job is inert until PR N's `DEPLOY_HEALTH_URL`. | M | Track 1 stable | The true source-of-truth re-check; gates everything downstream. **Delivered exactly the class of bug it exists to catch, on day one.** |
| **M** ✅ | **Build + artifact provenance (P2) — BUILT + MERGED (2026-07-05, PR #29); `docs/delivery-operations-plan.md`** — `templates/ci/build-provenance.yml` chains on `pipeline-ci` success (`workflow_run`), self-skips without a Dockerfile: hadolint pre-build + dockle on the built image (S4), immutable commit-SHA tag → ECR via the OIDC role, image SBOM (CycloneDX) attested to the registry, **cosign keyless sign**, **SLSA provenance** (`attest-build-provenance`), all actions SHA-pinned. New **`delivery-conventions` skill** (17th): tag/digest rules, verify-before-rollout (PR N enforces it — signing without verification is theater), hardening baseline, continuous vuln management (S2: Renovate + weekly re-scan). **Audit fixes in-branch:** dispatch arm ref-guarded to main (an un-guarded `workflow_dispatch` from a branch would have SIGNED unreviewed code) + STS account lookup (`ecr:DescribeRegistry` exceeds a push-only role). **Honest limit:** structure lint-verified (actionlint) + bootstrap smoke-tested; first end-to-end execution needs a real containerized app + ECR role (PR N territory). D2/D3 rubrics deferred to N by design. | M | L, I(SBOM) | Immutable, traceable artifact. |
| **N** ✅ | **Environments + progressive delivery + real load (P3 + M3) — BUILT + MERGED (2026-07-06, PR #30); `docs/environments-delivery-plan.md`** — `templates/ci/deploy.yml` (inert until `DEPLOY_ENABLED=true`) chains build-provenance → deploy: **verify signature** (cosign, identity-pinned to this repo's build workflow — refuse unsigned) → **staging** (tf apply envs/staging → RDS snapshot → migrate → rollout → health) → **prod** behind the GitHub `production` environment rule (the post-merge human checkpoint) → **ALB weighted canary 10/50/100** with alarm-watched soaks + auto-rollback to blue. `templates/ci/load-campaign.yml` (dispatch+weekly, vs staging): **k6** with p95/throughput/sustained-rate thresholds from the acceptance budget (**closes F1** — real numbers, not a serial-loop best case) + a **failover job** (kill a task, assert self-heal — multi-AZ by action). Skills: delivery-conventions (D2 migration sequence, D3 canary rubric + rollback runbook, flags), iac-conventions (envs/ split, deploy alarms, prod CloudFront+WAF/S3), containerization-conventions (graceful shutdown/R2). **Two audit passes:** #1 (build) ref-guarded the dispatch arms + SSM-URL masking; #2 (deep) proved the canary rollback via a mocked-aws 4-scenario sim (fixed a **stuck-at-partial-weight** bug on transient API failure) and fixed **container-select-by-name** (index [0] would deploy to a sidecar). **Honest limit:** lint + simulation + bootstrap verified; first true end-to-end run needs a real containerized app + AWS envs (the M2 "prove on a real repo" step). | L | M | First real deploy; proves "scalable" instead of asserting it. |
| **O** ✅ | **Observability + ops (P4 = production-debugger workstream) — BUILT + MERGED (2026-07-06, PR #31); `docs/delivery-operations-plan.md` + `docs/triage-agent-plan.md`** — the one genuinely new pipeline surface: a **read-only `triage` agent** (operator-invoked with one Sentry issue → writes `.pipeline/incident-brief.md` → stops; a fix only happens if a human starts a normal run). **Safety by tool absence** (no Bash/Edit — nothing to execute an injected instruction into), untrusted-telemetry posture (quote-never-obey + injection report + redaction), machine-enforced by `tests/suites/triage.sh` (21 assertions — fails loud if Bash/Edit is ever added). Skills: `triage-conventions` (brief schema/redaction/injection-report/read-only-MCP checklist) + `observability-conventions` (Sentry release-tagging, OTel→CloudWatch, SLO burn-rate alarms that feed N's canary, synthetics, mobile crash reporting); `sentry` MCP entry (read-only, inert until wired). **Audit fix:** corrected an overstated Write-surface claim (marker-deny is global + gate files always regenerated by their stage + human diff-approval — not a bypass). | L | N | Can only observe what's deployed. |
| **P** ✅ | **Scale validation + DR (P5) — BUILT + MERGED (2026-07-06, PR #32); `docs/delivery-operations-plan.md`** — **scale-ceiling** job in `load-campaign.yml` (ramp beyond budget; k6's abort = the ceiling; the deterministic assertion is scale-out fired); **`dr-drill.yml`** (monthly + dispatch, `DR_DRILL_ENABLED`) — an *executed* restore of the latest snapshot into a throwaway instance, a **positive-count** verify (an empty restore fails), RTO/RPO asserted against budgets, then teardown (never touches prod); **continuous vuln (S2)** — `scheduled-rescan.yml` (weekly OSV+Trivy detects) + `renovate.json` (remediates through the gates); **cost guardrails** in `iac-conventions` (Budgets + cost-allocation tags). **Audit fixes:** verify rejected empty restores (was `grep '^[0-9]+$'`, matched 0), fragile cred colon-split → separate PGUSER/PGPASSWORD SSM params, and an IAM blast-radius note (scope `DeleteDBInstance` to `db:dr-drill-*`). All opt-in/self-skipping; lint + bootstrap verified. | M | N | Closes the availability/DR gap. |
| **CQ** ✅ | **CodeQL deep SAST in CI (security depth + Swift) — BUILT (2026-07-06), audit-hardened same day** — the `codeql` job in `templates/ci/pipeline-ci.yml` (`docs/ci-merge-gate-plan.md` Layer 4's reserved slot, now filled): a per-language matrix `include` pairing `<CODEQL_LANGUAGE>` with `<CODEQL_BUILD_MODE>`, **security-extended** queries, SHA-pinned `codeql-action` **v4.36.2**, `security-events: write` per-job elevation. Semantic taint/dataflow analysis deeper than Semgrep's pattern-matching, across C/C++, C#, Go, Java/Kotlin, JS/TS, Python, Ruby, **and Swift** (Swift needs a macOS runner + autobuild/manual — iOS row); results surface as **code-scanning alerts** on the PR/merge commit (job fails on analysis error, not findings — alert-only by default; `ci-conventions` documents the blocking option + the public-repo/GHAS licensing constraint + the default-setup conflict). Kept **out of the security⇄debug⇄test loop** by design — it builds a database and is slow; CI is the right home. The engine repo itself doesn't run it (no bash support; `eval` is the engine's gate). **Self-audit found + fixed:** a universal `build-mode: none` that would fail Go projects (none is unsupported for Go — now per-language via the matrix), and a 4-day-old v4.36.3 pin violating the repo's own 14–30-day dependency cooldown (→ v4.36.2, 32 days). **Static-depth sibling of the runtime-depth DAST row.** | M | L (CI merge-gate exists) | The CI-depth complement to **SB**; runs **parallel to M–P** and is not on the L–P "10/10" line — added assurance, not a delivery step. First real execution happens on the M3 app's PR. |
| **SC** ✅ | **App-store compliance gate — DELIVERED as the STORE side-track row above (merged as PR #27, 2026-07-06; SC-6/7/9 deferred there). This row was the original Track-2 spec placement; the as-built record lives in the STORE row.** Original spec: **(Apple App Store + Google Play), PROJECT.md-scoped** — makes the store-submission requirements behind the post-merge Fastlane/Gradle recipes (`pipeline-deployment-targets.md`) **accountable inside the pipeline**, at planning/gate time instead of at upload. Reuses the proven channels end-to-end, **no new mechanism**: **Layer E** (first — safety fix: extend `run-summary.sh`'s reduced-assurance target detection to Android, which today sails through stamped `standard`); **Layer A** a `google-play-submission-requirements` skill (mirror of the shipped Apple one — Play currently has **no** competence layer at all); **Layer B** planning routing (PROJECT.md store target → load skill(s), emit store ACs riding `criteria_covered`); **Layer C** `store-compliance.sh` — Tier-1 deterministic manifest/config checks (privacy manifest + Required-Reason API reconciliation, usage strings incl. `project.pbxproj`, target-SDK floor with Gradle-indirection resolution, debuggable release; SC-1…SC-9) wired **exactly like `asvs-sast.sh`** (security Stop hook writing its own `store-compliance.json` + deploy-only `critical>0` gate floor, absent ⇒ no-op, zero loop-exit churn), scoped by a deterministic PROJECT.md-grep + file-signal key (fails open — declaring a target only *adds* checks); **Layer D** Tier-2 test shapes via plan-audit material flags (data-declaration ↔ DP `data_surface` reconciliation first — its dependency shipped 2026-07-04 — then account deletion, Sign in with Apple, store billing). All Windows-buildable (plain file/text checks — **not** blocked on the macOS-bound iOS Layer 3). Honest bar: designs out known rejection causes, **never guarantees acceptance** (human review stays Tier 3, post-merge). **→ Full spec: `docs/store-compliance-plan.md`** (incl. the per-layer file-touch inventory). | S–M (per layer) | — (DP shipped; parallel to L–P) | Extends the **iOS** row's Layer-4 accountability to Google Play and gives both stores deterministic teeth; upstream counterpart to the post-merge submission recipes, so it runs **parallel to L–P** (not required for the "10/10" line). Enabler for any store-shipped app. |

> **After PRs L–P: 10/10 fully-functional.** The pipeline authors, reviews, ships, and helps operate
> production software for live users — without breaking the fresh-context / file-handoff /
> deterministic-gate invariants; it extends them rightward across the merge boundary.

### What to do next (2026-07-01, post-PR I) — HISTORICAL, superseded below
Track-1 is one PR from complete. PRs F–I are all merged, published, and live (§10 status note above).

1. **PR J (in progress) — the last scaffolder item.** Token/altitude polish (row above). The clean win
   is extracting plan-audit's dependency/version-policy detail into an on-demand `dependency-audit-policy`
   skill (only loaded when a plan introduces deps); plus de-duping planning's threat-model *format*
   conventions into the already-preloaded `stride-threat-model-template` skill. No gate logic, no
   capability loss. Dogfood it through `tests/run-eval.sh` (the `static` suite verifies every
   agent-wired hook/skill still resolves) before merging. **After J → 10/10 scaffolder.**
2. **Then choose the next axis** (all parallel, none blocking):
   - **PR K (M9)** — threat-model the pipeline-as-target; includes the `diff-approved` fabrication
     vector (structural hardening of the deployer's `.pipeline/` write access). Natural precursor to
     [[redteam-app-goal]]. **Its follow-on is EG (default-deny egress control, `docs/egress-control-plan.md`)** —
     contains prompt-injection's exfiltration payload by removing the route out; do this before the
     pipeline consumes runtime secrets or adversarial red-team input.
   - **Track 2 (L→P)** — begin the delivery/ops half, starting with **PR L (CI as the merge gate)**,
     which also wires `tests/run-eval.sh` as a CI job.
   - **A second M2 run** (container/Dockerfile variant) to feed §8 more real data now that F–I are live.
3. **DOC** consolidation is deliberately last — do it once Track-1 churn settles.

**Honest note:** PR J is *breadth/polish*, not depth — the depth work (M1) already shipped in PR G.
J closes the scaffolder milestone cleanly but the higher-leverage next investment is either PR K
(trust/hardening) or starting Track 2 (the last 40%).

### What to do next (2026-07-05, post DAST #26 + STORE #27) — HISTORICAL, superseded below

Two PRs are **open and awaiting merge**, and they're the immediate action:
1. **Merge #26 (DAST) then #27 (STORE), in that order** — #27 is stacked on #26 and auto-retargets to
   `main` once #26 lands. Both are green on the 19-suite harness; both are advisory/opt-in or
   target-gated (can't fire on a non-mobile / non-opted-in project). After they merge, publish with
   `install-global.sh` so the new hooks ride into `~/.claude`.

**Then, the genuinely-buildable options** (pick by appetite; none block each other):

- **Track 2 · PR L — CI as the merge gate** *(highest leverage; the keystone).* Start with **Layer 1
  (engine CI)**: wire `tests/run-eval.sh` as this repo's own GitHub Actions merge gate — an afternoon,
  zero risk, and it's the home DAST/CQ re-home into. Spec ready: `docs/ci-merge-gate-plan.md`. This is
  the first step of the *last 40%* (delivery/ops) and unblocks M–P, CQ, and DAST-in-CI.
- **DAST Layer 4 (content-only, today-buildable)** — planning hooks: an API-schema + seeded test-user
  acceptance-criteria surface. No CI/staging needed; the only remaining DAST layer buildable on the
  Windows host (L2/L3 need staging from PR N).
- **STORE SC-6/SC-7/SC-9 follow-up** — the deferred used-API↔declaration compares (permission
  declared-vs-used, debug-logging-in-release, Required-Reason API). Higher false-positive risk, so
  they were held back; the block-aware SC-5 work just built the parsing muscle these would reuse.
- **DOC (housekeeping) or SK (skill enrichment)** — both pure-content, off the critical path; DOC is
  best done once Track-1/side-track churn fully settles (a `docs/DOC-consolidation-plan.md` draft
  already exists untracked in the tree).

**Recommendation:** **PR L Layer 1** is the single best next move — it's small, risk-free, converts
the harness into an enforced merge gate, and opens the whole Track-2 delivery half. Do it right after
merging #26/#27.

### What to do next (2026-07-06, post Track 2 — CURRENT)

Everything above happened: #26/#27 merged, then **Track 2 landed in full** (L #28 → M #29 → N #30 →
O #31 → P #32). Both "10/10" milestones are reached; harness **21 suites / 355 assertions**, `eval`
is the CI merge gate. What remains, in recommended order:

1. **M3 validation run (the M2 rule applied to the delivery half).** The Track-2 workflows are
   lint/simulation/bootstrap-verified but **never executed end-to-end** — a supervised first run on a
   real containerized app (pipeline-ci → build-provenance → deploy → canary → load campaign → DR
   drill) is the highest-value unknown left, exactly as the M2 run was for the authoring half. A
   plan draft exists at `docs/m3-validation-run-plan.md` (untracked).
2. **CQ — CodeQL in CI.** ✅ Done (2026-07-06) — the `codeql` job ships in `pipeline-ci.yml`;
   first real execution happens on the M3 app's PR.
3. **DAST Layers 4 → 2/3.** L4 ✅ done (2026-07-06 — `dast-conventions` skill + planning ACs +
   plan-audit flag); L2 (Schemathesis) and L3 (authenticated ZAP active) remain, with their staging
   substrate from PR N.
4. **Housekeeping when churn settles:** **DOC** consolidation (`docs/DOC-consolidation-plan.md`) and
   **SK** skill enrichment. (STORE SC-6/7/9 ✅ done 2026-07-06 — the store plan is fully delivered.)
5. **Still external-blocked:** iOS gate adapters + SB Swift slice (need a macOS runner); EG Layer-2
   proxy (operator provisions Docker/WSL2).
