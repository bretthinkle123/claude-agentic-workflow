# Plan — DAST / runtime security testing (dynamic analysis against a running app)

> **Status: Layers 1–4 BUILT (L1 2026-07-05 PR #26; L2/L3/L4 2026-07-06 PR #33). L2/L3 are `templates/ci/dast-staging.yml`, inert until a staging env + `DAST_STAGING_ENABLED=true`; first real run is M3 Phase B.** Closes the biggest security gap named in the
> 2026-07-05 audit: every existing security control (Semgrep/OSV/Trivy/Gitleaks/ASVS-DET/ASVS-6g)
> analyzes code **at rest, pre-merge**; nothing ever attacks the **running** app. Companions:
> `docs/ci-merge-gate-plan.md` (PR L — provides the CI runner and the job slot this fills),
> `docs/delivery-operations-plan.md` (PR N — provides the staging environment DAST targets),
> `docs/egress-control-plan.md` (the engine-scope network posture; unrelated — this is app-scope).
> Needs a **running app instance**, but *where* it runs is a choice: **Layer 1 (passive baseline)
> can run TODAY as a local post-GREEN advisory stage** (boot an ephemeral instance the way
> `smoke-check.sh` already does, then scan it — the same runtime-bound-advisory pattern as
> design-review Layer 4), with **no dependency on CI or staging**. Only the deeper layers
> (authenticated + active fuzzing) need CI + a prod-shaped staging env (PRs L, N).

## Goal & honest scope

Add a runtime security layer that exercises the deployed app the way an attacker would — sending
real requests to a live instance and observing responses — catching the class of defect static
analysis structurally cannot: auth actually enforced on each route *as served*, security headers/
cookie flags *as emitted*, error leakage *under malformed input*, and schema-level fuzz crashes.

**Honest bar.** Automated DAST finds **regressions of known classes**, deterministically, every
merge. It does **not** find novel business-logic flaws or multi-step exploit chains — that is manual
pentesting's job (see "Relationship to a dedicated pen-testing tool" below). DAST is a **CI job that
gates**, not a replacement for a human red-teamer; claiming otherwise would be the same over-claim
the repo avoids elsewhere.

**Where DAST runs — and why not in the fast local loop.** Three possible homes, and the distinction
matters for what's buildable when:

- **NOT in the security⇄debug⇄test loop.** That loop re-fires every remediation cycle and must stay
  fast + deterministic; a multi-minute scan there would bloat cycle time and fight loop determinism
  (the same call the repo made for CodeQL). So DAST is **never a loop-exit predicate** → zero
  `loop-exit ≡ gate` churn, regardless of where it lives.
- **A post-GREEN local advisory stage (buildable today).** After the loop exits GREEN — the same
  slot as design-review Layer 4 — boot an ephemeral instance locally (docker-compose, exactly what
  `smoke-check.sh` already proves the app can do), run the passive baseline, write an **advisory**
  report documentation surfaces in the PR. **No CI, no staging, no Track 2 dependency.** This is
  Layer 1's fast path and the reason DAST is not actually blocked on PR L.
- **CI against staging (the eventual home for depth).** The authenticated + active layers need a
  prod-shaped, migrated, seeded instance and are slow — that is genuinely CI + staging (PRs L, N).
  Moving Layer 1 into CI later is a re-home, not a rebuild.

**So the honest dependency:** Layer 1 depends only on Docker (already assumed for Semgrep/Trivy);
Layers 2–3 depend on L + N. My earlier "DAST depends on L" over-stated it by scoping the whole
plan into CI — corrected here.

## Tooling (open-source, headless, JSON-emitting — the scanner-wrapper mold)

| Tool | Role | Why |
|---|---|---|
| **OWASP ZAP** (baseline + full-scan) | Passive + active web/HTTP scanning | Industry-standard, scriptable, JSON/SARIF out, Dockerized (same posture as Semgrep/Trivy wrappers) |
| **Schemathesis** | Property-based API fuzzing from the OpenAPI/GraphQL schema | Turns the app's own contract into thousands of adversarial cases; finds 500s, schema violations, auth gaps per-operation |
| **Nuclei** *(optional, later)* | Templated known-CVE / misconfig probes | Breadth on known issues; advisory-only to avoid noise |

All three run headless, exit non-zero on findings, and emit machine-readable output — so each wraps
like `semgrep-scan.sh` and folds into a CI job's pass/fail. No new gate *hook*; the CI job is the gate.

## Layers (staged like the ASVS / egress slices)

1. **Layer 1 — ZAP baseline (passive) — ✅ BUILT (2026-07-05), local advisory stage.** Delivered
   as a **two-script split** mirroring design-review Layer 4 (the proven pattern — a runtime-bound
   launcher + a pure-jq testable core), *not* the single `zap-baseline.py` call the original sketch
   implied:
   - `global-hooks/dast-capture.sh` (**runtime-bound**): opt-in via `.pipeline/dast.env`, boots an
     ephemeral instance (its own `DAST_START_CMD`, or an already-running server), runs OWASP ZAP's
     passive baseline in Docker against it, writes the raw ZAP report to `.pipeline/dast-capture.json`.
     Fail-safe no-op when `dast.env` or Docker is absent, **or the target never comes up** (a
     host-side reachability precheck skips ZAP rather than let an unreachable-target scan write a
     zero-alert report the review would read as clean — **never reports DAST-clean without actually
     scanning**). Handles the ZAP-container→host-app networking (loopback rewritten to
     `host.docker.internal` + `--add-host`), sources `dast.env` only if git-untracked (smoke.env
     posture), and honors `PIPELINE_EGRESS_NETWORK` (EG side-track).
   - `global-hooks/dast-review.sh` (**deterministic, pure jq**): tallies the ZAP report's alerts by
     severity (ZAP `riskcode`/`count` are strings — coerced) and compares to
     `.pipeline/dast-budget.json` per-severity caps (safe defaults if absent), writing the **advisory**
     `.pipeline/dast-review.json`. Absent/malformed capture ⇒ clean no-op (never emits an invalid file).
   Templates `templates/dast.env` + `templates/dast-budget.json`; orchestration stage **4e**
   (post-GREEN, conditional on `dast.env`); interlock row; documentation surfaces over-budget bands
   in the PR. **Advisory — never a gate, never in loop-exit** (post-GREEN, runtime-bound). Harness:
   `tests/suites/dast-review.sh` (12 assertions; the runtime ZAP half is not exercised, like
   ui-capture). **This is the path that needs no CI and no staging.** When PR L lands, the *same*
   scanner re-homes into the reserved `dast-baseline` CI job (SARIF to the Security tab) and can be
   promoted to **blocking on High**. **S–M — done.**
2. **Layer 2 — Schemathesis API fuzz (active, gates) — ✅ BUILT (2026-07-06, PR #33).** The
   `api-fuzz` job in `templates/ci/dast-staging.yml`: Schemathesis `run <schema> --checks all`
   (status-code conformance, response-schema conformance, server errors) against staging with the
   seeded DAST test-user's token (SSM via the staging OIDC role). A 500 or a schema violation fails
   the job. Highest-value layer — the app's own contract is the oracle, so coverage scales with the
   API. Consumes the DAST-1 (served schema) + DAST-2/3 (test user + auth) criteria Layer 4 emits.
   **M.**
3. **Layer 3 — ZAP active scan (authenticated, gates on High) — ✅ BUILT (2026-07-06, PR #33).** The
   `active-scan` job in the same workflow: `zap-full-scan.py` with the test-user token injected as an
   `Authorization` header via ZAP's replacer, against staging only (never a shared env — active scan
   sends real attack payloads). A deterministic jq gate (same severity semantics as `dast-review.sh`)
   **fails on High, annotates Medium**; a missing report is treated as failure, never silently clean.
   Scheduled nightly **and** dispatchable rather than every merge, because active scans are slow —
   the "recurring automated pentest," complementing the every-merge baseline. **M–L.**

Both jobs are **inert until `DAST_STAGING_ENABLED=true`** (deploy.yml opt-in pattern) and a staging
env exists — they self-skip otherwise, costing nothing. Lint- and (schema/manifest) shape-verified;
their **first true execution needs a real staging environment** (M3 Phase B), the same honest limit
every Track-2 deploy template carries.
4. **Layer 4 — the `dast-conventions` skill + planning hooks.** Planning, for an app with an HTTP
   surface, emits: the OpenAPI-schema-exists expectation, a seeded DAST test-user requirement, and
   the auth-context config as acceptance criteria (so a missing schema/test-user is a plan-audit
   material flag, not a CI surprise). Documents each layer's guarantee + the tuning/false-positive
   protocol. **S.** *(Sequencing note: although numbered last, this is a dependency of Layer 2 —
   Schemathesis needs the schema + test-user this layer guarantees — so it lands* **with or before**
   *Layer 2, not after. See Sequencing below.)*

## Relationship to a dedicated pen-testing tool (the Burp question, recorded)

**They are complementary; build both.** Automated DAST = regression coverage of known classes, every
merge, unattended. A manual/Burp-based tool = novel chains, business logic, the un-checklist-able —
but only on the days a human runs it, which reintroduces the "protected only when someone remembers"
failure mode the pipeline exists to remove. Industry standard is explicitly both.

**Design lever (do this from day one of the separate tool):** give that tool a **headless CI mode** —
non-interactive scan profile, config-file target/auth, JSON findings, meaningful exit codes. Then it
can *become* this plan's DAST engine later (wired exactly like ZAP/Schemathesis), and Layers 1–3
here are the interim/placeholder engines. That also makes the tool a better product ("runs in your
CI" sells). What to avoid: skipping DAST now on the tool's promise — the tool is a large project and
staging (PR N) exists long before it; ZAP baseline is ~a day once N is up.

## Sequencing

1. **Layer 1 (ZAP baseline)** — **now**, as a local post-GREEN advisory stage (Docker only, no CI).
   Ship advisory, tune on a real app. Re-homes into the CI job (and can go blocking-on-High) when L lands.
2. **Layer 4 (planning hooks + skill)** — next, *before* Layer 2, so apps arrive at the fuzz layer
   already carrying an OpenAPI schema + a seeded test-user (a missing one becomes a plan-audit flag,
   not a broken job). Content-only — also buildable today.
3. **Layer 2 (Schemathesis)** — ✅ built (template); the highest-value gating layer. Runs once
   staging (PR N) exists and the operator opts in.
4. **Layer 3 (authenticated active scan)** — ✅ built (template); scheduled nightly against staging,
   gated on High. Layer 5 (Nuclei) optional, advisory, any time after Layer 1.

Dependency order overall: **(Layer 1 + Layer 4, done) → L (re-home Layer 1 to CI, done) → N (staging) → (Layer 2 + Layer 3 templates, done — execute at M3 Phase B)**.

## Non-goals

- **Not a substitute for manual pentesting** before a real launch (do that too, pre-launch + recurring).
- **Not in the local loop** — CI/staging only; no `loop-exit` change.
- Not active-scanning production (staging only; a prod scan is an incident-shaped decision, not a job).
- Not client-side/mobile runtime testing (that's a mobile-DAST sibling; out of scope here).

## Tie-in

Fills the `dast-baseline` job slot from `docs/ci-merge-gate-plan.md`; targets the staging env from
`docs/delivery-operations-plan.md` (PR N). Add a DAST row to `pipeline-june-analysis.md` §10 (Track 2,
depends on L + N) when this moves from spec to build — it is currently **absent from the roadmap**
and should be added as part of approving this plan.
