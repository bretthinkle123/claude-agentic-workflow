# Pipeline fix plan — UNIFIED v2.1 (all three M3-series runs, self-audited), implementation-ready

One cohesive plan covering everything identified across the three validation runs:
**[R1]** = run 1 / M3 greenfield (feature 1, usage-metering ingest) · **[R2]** = run 2 /
brownfield control (feature 2, GET /v1/events) · **[R3]** = run 3 / first design-source
run (feature 3, usage dashboard, Claude Design export, pre-fix engine `43859c2`).
Every entry names its origin run(s) and its prior IDs. All audit corrections (plan
revisions R2–R4, both appendix self-audits) are folded into entry text — implement from
this document alone. The layered `pipeline-fix-plan.md` is the full audit trail.

Merges performed in this consolidation (nothing dropped): old FIX-03 + FIX-23/PD-N1 →
**U-03** (same plan-audit surface, already slated for one commit) · old FIX-13 + PD-X1
→ **U-13** · old FIX-24/PD-N2 + FIX-26/PD-N5 → **U-14** (same silent-skip class) · old
FIX-25/PD-N3 → into **U-16** (same file/suite as the telemetry bundle) · PD-N4 → into
**U-17** · PD-X2/X3/X4/X5 evidence → into U-21/U-06/U-16/U-15 respectively.

**Status: READY — implementation starts only on Brett's explicit go.** The only
unresolved inputs are decisions D1–D3 (they gate U-15/U-19 wording and one guard
comment; nothing else waits).

**Hard constraints (every entry):** gates stay deterministic (jq on status files, never
LLM-judged) · human checkpoints and marker-forgery guards never weaken · loop-exit
predicate stays byte-equal to the deployment gate's checks (any predicate change edits
`deployment-gate.sh` + SKILL.md + `tests/suites/loop-exit-invariant.sh` in ONE commit) ·
Meterly app code (all 30 deferred findings) out of scope.

**Repo-of-record rule:** land in `claude-agentic-workflow` first (`global-hooks/`,
`global-agents/`, `global-skills/`, `global-project-skills/`, `templates/`, `skills/`),
publish via `install-global.sh`, verify sha parity with `~/.claude/`.

**Validated controls — do NOT touch (each passed a live exercise):**
design-spec injection defense (two plants caught verbatim incl. off-screen div, no
self-vouch, currency hash verified, halted for human) [R3] · plan-audit → one-shot
planning-revision loop (3 material flags fixed in one pass, first live run) [R3] ·
compute/wall budget split (excludes human-wait as designed) [R1] · the design-approved
write path (un-blocked, currency-hashed; actor attested-not-evidenced — see U-15) [R3].

---

## OPEN DECISIONS (the only blockers)

| # | Decision | Options | Gates |
|---|---|---|---|
| D1 | Approval flow for plan/diff markers | in-session "continue" (orchestrator writes on un-hooked main thread — the design-approved flow, mechanism proven un-blocked in R3) vs human-typed `touch`/`approve-diff.sh` | U-15 wording |
| D2 | Gating dependency-CVE owner | debugging-as-remediation (what R1 did; recommended) vs security agent bumps manifests | U-19 wording |
| D3 | Stale-marker deletion | docs-say-human vs guard-explicitly-allows-rm (forgery = creation, stays blocked either way; `rm` is NOT in the guard's pattern today — the R2 "guard denies rm" claim was contradicted by source) | U-15 sub-item |

---

## PRE-FLIGHT (step 0)

1. **Preserve fixtures** from `meterly-pipeline-test/.pipeline/` (gitignored,
   session-fragile) into `tests/fixtures/m3/`: all three runs' `test-results.json` +
   `security-status.json` + `security-report.md`, `run-log.jsonl`, `acceptance.md` (×3,
   with frontmatter), feature-2 + feature-3 `plan.md` (U-03 replay inputs),
   `checkov.json` / `trivy-config.json` / `osv.json` / `semgrep.json` / `gitleaks.json`
   (U-09 formula calibration), `design-spec.md` + `design-approved` (U-23 corpus),
   `dast.env` + `dast-server.log` + `dast-review.json` (U-14 failing fixture),
   `test-quality.json` (×2).
2. **Deployment telemetry is missing for runs 2 AND 3** (run 3 branched from `faabe9d`;
   run 2 unmerged; both retrospective deployment addenda unfilled). Before U-06's
   deployment maxTurns number is committed, resolve/observe those deploys and re-run
   `run-summary.sh`.
3. `install-global.sh` round-trip: post-publish sha256 parity repo ↔ `~/.claude/`.

---

# TIER P0 — failed silently

## U-01 — Criteria arithmetic: recompute from `by_id` + `delegated` flag
**Origin: R1** (24/24 recorded while `by_id` said AC20 false; honest marking would have
wedged the loop). Confirmed latent by **R2** (18/18 consistent only because no
out-of-suite criterion existed; honesty lived in unreadable prose reasons) and **R3**
(`criteria_total: 25` frontmatter — the anchor pattern holds on all three runs).
*Was FIX-01/P0-1 (formula per plan self-audit R2).*

**Files:** `global-hooks/deployment-gate.sh` · SKILL.md predicate ·
`tests/suites/{loop-exit-invariant,gate}.sh` · `global-agents/{testing,planning,documentation}.md`.

**Change:** `by_id[]` gains `"delegated": "security"|null` (delegated ⇒
`covered: false`, never counted by testing, never wedges). Gate + loop-exit
(byte-equal, one commit): `covered_tests = [.by_id[]|select(.covered==true)]|length`;
`accounted = [.by_id[]|select(.covered==true or .delegated=="security")]|length`
(single select — no double count). Block if `accounted < (.by_id|length)`, or recorded
`.covered != covered_tests`, or `(.by_id|length) != .total`. Anchors outside testing's
control: `.total` must equal `acceptance.md` frontmatter `criteria_total`, and every
delegated id ∈ planning-owned `delegated_criteria:` frontmatter (human-reviewed at plan
checkpoint — closes self-delegation and denominator truncation). Delegated counts only
because security's clean/`asvs.reconciled` checks are already conjuncts. planning
declares delegation; documentation reports "N test-covered + M delegated"; R2's
reasoned-inherited-coverage phrasing documented as the honest form. Legacy files without
`by_id` → integer-compare fallback.

**Accept:** (a) R1's real file (24/24, AC20 false, no flag) → blocks; (b) + flag +
covered 23 + frontmatter listing AC20 → passes iff security clean; (c) numerator
mismatch → blocks; (d) delegated id not in frontmatter → blocks; (e) no by_id → legacy.
**Known limitation (v2.1 audit, stated so it can't widen silently):** the schema
hardcodes the single delegate `"security"` because its deterministic checks are already
gate conjuncts. Any future delegate target (e.g. a design/frontend stage) is NOT valid
until that stage has its own gate-conjunct-backed status file — extending the enum
without that backing would let a criterion delegate to an unverified stage. The gate
rejects any `delegated` value other than `"security"` (not just missing-from-frontmatter).
**Risk:** low-medium; tightens only.

## U-02 — Security-stage efficacy questions (four missed classes) + enabling-condition conventions
**Origin: R1** (3× clean over 10 inspection-checkable bugs; reconciliations verify
presence, not efficacy — plan drew the ALB yet keyed Tier-1 on `request.client.host`;
"append-only" with UPDATE/DELETE granted; ENABLE-not-FORCE RLS with owner role;
presence checks structurally unable to fail on D1/E1/R1/I3). *Was FIX-02/P0-2 + its
report-§6-D/E amendment.*

**Files:** `global-agents/security.md` (6d) · `global-skills/api-edge-conventions` +
`data-protection-conventions` + `stride-threat-model-template` ·
`global-agents/testing.md` / test-conventions · `tests/suites/static.sh`.

**Change:** 6d = presence **and** per-category efficacy answer: *topology* (proxy/LB
declared ⇒ client-IP trust configured? probe paths exempt from pre-auth throttles?),
*DB privilege* (RLS owner ⇒ FORCE? append-only ⇒ REVOKE/trigger?), *async runtime*
(KDF / blocking SDK off the event loop?), *contract drift* (each facade promise: name
the consumer, verify it honors it — rotation re-resolve; scrubber covers
query_string/url). Conventions require plans to state each mechanism's **enabling
conditions** so there is something falsifiable to check. Testing: a declared backstop
needs a bypass-the-primary test or a structural assert on its enabling condition (kills
the vacuous RLS pass).

**Accept:** replay vs the shipped R1 tree flags ≥ findings #1/#2/#9/#10; static.sh
guards the prompt; full acceptance = U-23 eval. **Risk:** medium (prompt-level, bounded
by U-23); watch security turn usage next run.

## U-03 — Semantic verification layer: proof-claims + cross-feature data-flow + production-shaped fixtures (+ M4 pilot)
**Origin: R2 + R3 — merged** (same blind-spot class, same plan-audit surface, one
commit). *Was FIX-03/F2-N1 (R2) + FIX-23/PD-N1 (R3).* R2: gates GREEN over a
silent-data-loss bug planning claimed "provably implied" (plan line 186; invariant
`window_start == floor(event_time)` enforced nowhere; aligned-clock fixtures
structurally couldn't catch it). R3: gates GREEN over a non-functional feature — the
dashboard's populated tests ingest with the same `dashboard_reader_key` fixture the
BFF reads with (direct proof, test signature line 133) and the cross-tenant test
asserts the production topology as `state=="empty"` PASS. /code-review is **3-for-3**
sole catcher of each run's deepest bug.

**Files:** `global-agents/plan-audit.md` · `global-agents/testing.md` +
test-conventions + test-quality adversarial prompts · SKILL.md (pilot step, M4 only) ·
`tests/suites/static.sh` · U-23 corpus.

**Change:**
1. **[R2] Proof-claim dimension** in plan-audit: every "provably / guaranteed /
   invariant / cannot happen / always" claim must name the invariant AND locate its
   enforcement point (constraint / single code path / test that would fail); enforced
   nowhere ⇒ **material**.
2. **[R3] Cross-feature data-flow trace** in plan-audit: when a plan reads data an
   existing feature writes, trace the scope/join key end-to-end (writer principal vs
   reader principal); **material** if the reading principal can never own the rows.
   R3's plan fails this trace immediately.
3. **[R3] Production-shaped fixture rule** (testing.md + conventions, planning-time
   criteria too): read-path integration fixtures must be produced by a **different
   principal** than the reader, unless isolation is the explicit assertion; a
   reader-is-its-own-producer fixture requires a one-line stated justification.
   Adversarial-review prompt: "which fixtures would a production topology falsify?"
4. **[R2+R3] M4 correctness pilot** (advisory, data-gathering, never a gate): one
   scoped review post-implementation / pre-loop over data-path queries + state-changing
   logic in the diff. Measured in M4, then kept or dropped. (Narrows, does not
   overturn, the standing recommend-against on promoting full /code-review.)

**Accept:** replay — upgraded plan-audit flags R2's line-186 claim AND R3's reader-key
trace as material (both plans preserved in pre-flight); testing-rule greps; U-23
planted fixtures red on the pre-fix agents. **Risk:** medium — prompt-level (bounded by
U-23); false-material flags cost one planning revision and force enforcement points to
be written down.

---

# TIER P1 — cost real money/time

## U-04 — Smoke wiring: `bash -c` + `exec` + bootstrap validation
**Origin: R1** (bootstrap's own usage example emits the nested-quote form
`smoke-check.sh:51` word-splits; bare `python` ≠ venv; cost one implementation resume
cycle). *Was FIX-04/P1-1 (R2-corrected).* **Files:** `global-hooks/smoke-check.sh` ·
`templates/bootstrap-project.sh`. **Change:** `bash -c "$SMOKE_BUILD_CMD"`;
`bash -c "exec $START_CMD" &` (exec is load-bearing — otherwise the EXIT-trap kills the
wrapper and the orphaned server holds the port); resolve the greenfield default into a
variable before the call; bootstrap warns/refuses on embedded quotes and rewrites its
usage examples to the venv-explicit `-m` form that survived R1. **Accept:** dry-run
matrix (old fatal form / `-m` form / default) all correct + server dead after trap.
**Risk:** low.

## U-05 — Marker guard: de-self-break the templates
**Origin: R1** (guard tripped on its own scaffold; in-run rewording stranded in the
project; templates still self-breaking — verified only `pipeline-ci.yml:194` + the
guard's own prose match). *Was FIX-05/P1-2.* **Files:** `templates/ci/pipeline-ci.yml`
· `global-hooks/guard-source-markers.sh` · `tests/suites/marker-guard.sh`. **Change:**
rename the step (meterly-proven circumlocution); port the reworded comments; EXCLUDE →
`(^|/)(tests/|.*\.pipeline/|(global-hooks|scripts/ci)/guard-source-markers\.sh)`;
MARKERS byte-identical. **Accept:** clean-scaffold sim → 0; planted marker in
`src/x.py` and `scripts/ci/other.sh` → 2; step name → 0. **Risk:** low.

## U-06 — maxTurns + warm-resume progress files (+ the documentation-model test)
**Origin: R1** (7/20 caps, 35% tax; implementation 3×40) **re-scoped by R2** (caps 7→2
on small scope — cap storm was scope-size; documentation capped on a trivial update)
**and R3** (documentation capped a THIRD straight run ~50 s from done; new cap-driver
class = environment setup e.g. Playwright install; R3 tax 4/12 = 33% despite small
scope — cap *cost* matters as much as count). *Was FIX-06/P1-3 + F2-X1 + PD-X3.*

**Files:** `global-agents/{implementation,documentation,deployment,testing}.md` · SKILL.md.
**Change:** implementation 40→60; deployment 15→25 (recheck once pre-flight 2 lands the
missing deploy telemetry); testing stays 50 + progress-file contract; **documentation:
run the model hypothesis FIRST** — one run on sonnet at unchanged maxTurns; if the cap
disappears the budget was never the problem, else 25→35. Implementation + testing
append `.pipeline/<stage>-progress.md` every ~15 turns; SKILL resume prompt reads it.
**Sequencing (v2.1 audit clarification):** batch 5 commits implementation 60 /
deployment 25 / the progress contract **and sets documentation `model: sonnet` at
maxTurns 25 as the M4 experiment condition**; the M4 result then decides the follow-up
commit — cap gone ⇒ keep sonnet (or trial haiku@35 for cost), cap persists ⇒ revert to
haiku and raise to 35. One variable changed per observation; no blind double-change.
**Accept:** M4 cap tax <10%; progress file exists post-implementation. **Risk:** medium
(worst-case spend; loop budgets unchanged bound it). Numbers = three-run calibration,
tunable.

## U-07 — k6 perf recipe into test-conventions
**Origin: R1** (AC-PERF punted until the orchestrator supplied the recipe) **confirmed
R2** (recipe upfront ⇒ first-try real measurement + honest scale disclosure). *Was
FIX-07/P1-4 + F2-X4.* **Files:** `templates/project-skills/test-conventions/` ·
testing.md pointer. **Change:** default recipe (grafana/k6 via Docker,
constant-arrival-rate, host.docker.internal, warm-up excluded, nearest-rank p95,
required `.perf.scenario` fields) + two worked examples: R1's scenario block and R2's
below-ceiling disclosure ("directional measurement at this scale…"). **Accept:** M4
perf AC populated unprompted; gate untouched. **Risk:** low.

## U-08 — Tree-hygiene Stop hook
**Origin: R1** (scanner output leaked into the repo tree while the prose rule already
existed in security.md — prose demonstrably insufficient). *Was FIX-08/P1-5
(R2-repatterned: NTFS forbids `:`, so pattern the class not the name).* **Files:** new
`global-hooks/guard-tree-hygiene.sh` · Stop wiring on security+debugging ·
bootstrap .gitignore. **Change:** exit 2 on untracked `(^|/)scratchpad(/|$)`,
`(^|/)scratch_`, non-ignored `(^|/)reports/`, top-level `Users/`; patterns in one
variable. **Accept:** planted junk → 2; clean → 0; gitignored → 0. **Risk:** low.

## U-09 — Scan evidence: stamps + wrappers + reconciliation + archiving + `.pipeline`-only routing
**Origin: R1** (report claimed OSV/Semgrep "executed"; artifacts contradicted OSV,
Semgrep evidence unrecoverable; per-pass reports overwritten). **Recurred R3 — now
3-for-3:** run-3 report claims Semgrep (40 targets incl. js/html) / OSV / Checkov
executions — Checkov's row cites the NEW `dashboard_reader` resource — while on-disk
artifacts are run-2's semgrep.json and run-1's osv.json/checkov.json; outputs likely
went to OS temp, which current wording PERMITS, and evaporated. R2 confirmed the
disclosure habit works when prompted (Checkov/Trivy skip disclosed). *Was FIX-09/P1-6
in full R3+R4 form.*

**Files:** `global-hooks/{semgrep-scan,gitleaks-scan,trivy-scan}.sh` · **new**
`osv-scan.sh` + `checkov-scan.sh` (none exist today — why R1/R3 claims were
uncheckable) · **new** `reconcile-scans.sh` (security Stop hook) ·
`templates/project-settings.json` (swap raw `osv-scanner:*`/`checkov:*` permissions for
wrapper paths) · security.md (steps 8/9, **E4 wording tightened to `.pipeline/` ONLY —
delete the "or OS temp" allowance R3 exploited**) · gate + SKILL predicate +
`loop-exit-invariant.sh` (one commit) · fixtures from pre-flight.

**Change:** every wrapper stamps `.pipeline/scan-log.jsonl`
`{tool, ran_at, args, exit_code, output_path, output_sha256}` (args = ruleset floor).
Report rows say "executed" only with a this-pass stamp, else "carried forward
(justification)". `security-status.json` gains `scan_artifacts:{tool:<sha>}`;
`reconcile-scans.sh` verifies stamps, **recounts** with the artifact-validated formulas
— semgrep `.results|length`; OSV `[.results[].packages[].vulnerabilities[].id]|unique|length`
(=1 on R1 ✓); Trivy `[.Results[]|(.Misconfigurations//[])[]]|length` (=27 ✓, severity
convention pinned); Checkov `[.[].summary.failed]|add` (top-level ARRAY — `.summary.failed`
errors; =59 on R1 while the agent recorded 58, reproducible by NO formula — the hook's
formula IS the convention, documented in security.md; first post-fix run legitimately
re-counts). Gitleaks excluded (in-scope filtering = triage judgment). Scope check:
every code-shaped change-set file ∈ union of this-run semgrep `paths.scanned`
(deterministic exclusion list). Writes `scan-reconciliation.json {count_mismatches,
scope_gaps, reconciled}`; exit 2 on mismatch; gate + loop-exit gain ONE conjunct
(`.reconciled == false` blocks); legacy no-op without scan-log. Plus per-attempt report
archiving → `.pipeline/archive/security-report.<attempt>.md` (R1's pass-1/2 and R3's
predecessors are unrecoverable today). Freshness and triage deliberately stay
non-gating.

**Accept:** double-run → two stamps; count-mismatch fixture → blocks; sha-without-stamp
→ blocks; unscanned `.py` → blocks; `.png`/lockfile → passes; no scan-log → legacy
pass; R1 replay forces "OSV: carried forward"; R3 replay forces stamps-or-carried on
all three stale tools. **Risk:** low-medium (recount jq tracks scanner schemas —
pinned images + captured fixtures mitigate).

## U-10 — Finding ledger (the mechanism that grows the net)
**Origin: R1 roadmap, seeded by all three runs.** *Was FIX-10/P1-7.* **Files:**
`docs/finding-ledger.md` · SKILL post-ship step · retrospective template ·
static.sh. **Change:** every verifier-CONFIRMED finding/incident → one row
`{finding, class, escaped-because, action}`; action ∈ {new efficacy question (U-02),
new planted eval defect (U-23), new deterministic check, recorded "accepted, no
check"}. **Seed with all 30 findings (10+10+10).** **Accept:** static.sh row/action
check; M4's audit verifies M4's escapes became rows. **Risk:** low.

## U-11 — Bootstrap-integration CI suite
**Origin: R1 audit of the engine week** (both engine regressions were cross-PR
interactions between individually-green PRs). *Was FIX-11/P1-8.* **Files:** new
`tests/suites/bootstrap-integration.sh`. **Change:** temp-dir bootstrap from current
templates → git init + stub → run every ambient hook a fresh project meets → all
green. **Accept:** MUST fail against today's templates (live U-05 defect), pass after
U-05 — same PR, red-then-green. **Risk:** low.

## U-12 — Prompt-carried lessons → definitions (standing rule)
**Origin: R2** (all three R1 lessons worked when prompt-delivered; none live anywhere
durable). *Was FIX-12/F2-N2.* **Files:** testing.md · SKILL.md · static.sh.
**Change:** delegated/inherited-marking prose into testing.md now (machine flag = U-01);
the rule: *"a lesson that worked in a prompt moves into the agent definition the same
week — prompts are for experiments, definitions are for keeps."* (Temp-routing and k6
homes are U-09/U-07.) **Accept:** greps; M4 runs with a bare orchestrator prompt, all
three behaviors persist. **Risk:** low.

## U-13 — Documentation identifiers: exist AND match (warn-first)
**Origin: R2** (invented `create_or_replay_event` / `window_start_utc` — real function
is `floor_to_hour_utc`; zero .py occurrences) **+ R3, now 2-for-2 with a harder
variant** (wrong signature on a RESOLVABLE name — README's
`get_usage_series(principal, params)` vs real `(*, customer_id, metric, granularity)` —
plus a false "service validates" behavioral claim). *Was FIX-13/F2-N3 + PD-X1.*

**Files:** documentation.md · new `global-hooks/check-doc-identifiers.sh`
(documentation Stop hook) · fixtures. **Change:** copy-from-tree-never-recall rule;
hook extracts code-formatted project-symbol identifiers from CHANGED markdown, checks
(1) existence (definition/occurrence in non-doc files) and (2) for names resolving to a
`def`/`class` documented with a signature: argument-name compare against the def site.
Behavioral claims ("validates", "caches") are prose → routed to a U-23 planted-README
fixture, never the hook. **Warn-only one run; promote to exit 2 after M4 calibration.**
Small allowlist variable. Never a deploy-gate conjunct. **Accept:** `floor_to_hour_utc`
→ pass; `window_start_utc` (R2 tree) → flagged; `get_usage_series(principal, params)`
(R3 tree) → flagged by signature compare; allowlisted external → pass. **Risk:** medium
(heuristic extraction) — contained by warn-first + doc-stage-only.

## U-14 — Opt-in advisory stages: wire-or-disclose (DAST target + design-review skip)
**Origin: R3 — merged, same silent-skip class.** *Was FIX-24/PD-N2 + FIX-26/PD-N5
(self-audit-corrected mechanism).* (a) DAST ran against `DAST_TARGET_URL` = bare root
(page at `/dashboard`): server log = 4×404 + 2 health-probe 200s, **zero** `/dashboard`
requests — "within budget" certified a scan of nothing. (b) The design-review stage
(FE Layer 4) never fired on the first design-source run — no `ui.env`, no artifacts,
no record of the skip; the built UI's fidelity to the Claude Design export was
machine-checked by nothing.

**Files:** `templates/dast.env` + `templates/ui.env` + `templates/bootstrap-project.sh`
(comments) · `global-hooks/dast-capture.sh` + `dast-review.sh` · SKILL 4d +
documentation.md · fixtures. **Change:** (a) web-target comment: set the served route
(or new optional `DAST_SPIDER_SEEDS` list); **`target_reached` = direct probe of
`DAST_TARGET_URL` status (<400) at capture time** (self-audit correction — not all-4xx
log parsing, which health-probe 200s would confuse); `target_reached: false` surfaces
as a WARN in dast-review.json and the PR. (b) deterministic PR-description line —
"design-review (FE Layer 4): skipped — ui.env not wired" — whenever a design source was
used (design-approved or design-spec.md exists) without `ui.env`; file-existence check
only. **The design-review/a11y workstream itself stays DEFERRED per Brett's standing
decision** — this only makes skips visible. Both advisory; no gate, no loop-exit
change. **Accept:** (a) 404-target fixture (R3's own dast.env/log) → WARN; real route →
none. (b) design-approved present + ui.env absent → PR line required; ui.env present →
none. **Risk:** low.

---

# TIER P2 — polish

## U-15 — Marker actor story + deletion policy (docs; D1 + D3)
**Origin: R1** (four documents disagree on who writes plan/diff markers; the `touch`
denial mechanism unverified) **+ R2** (stale-marker deletion friction, 2nd occurrence;
"guard denies rm" contradicted — `rm` absent from the pattern) **+ R3** (the
design-approved flow completed un-blocked with a verified currency hash — mechanism
proven; **actor attested, not evidenced**). *Was FIX-14/P2-1 + F2-N5 + PD-X5.*
**Files:** SKILL.md (0b/1c/Bootstrap) · guard-approval-markers.sh header (+ rm comment
iff D3=allow) · bootstrap memory template · session memory
`checkpoint-approval-in-session.md` · static.sh + marker-guard.sh. **Change:** one
consistent actor story per D1 across all four sources; deletion per D3 (package with
D1: in-session flow ⇒ allow-rm; terminal flow ⇒ docs-say-human). Creation stays blocked
either way. **Accept:** actor-consistency grep; creation-block regression; if
D3=allow, an rm case passes. **Risk:** none at runtime.

## U-16 — Telemetry correctness bundle
**Origin: R1 + R2 + R3.** *Was FIX-15/P2-2+P2-5 + F2-N6 + FIX-25/PD-N3 + PD-X4.*
**Files:** `global-hooks/log-run.sh` · `templates/state.json` · testing.md (Stop
order + schema) · stamp-ran-at.sh comment · SKILL.md · replay fixtures (all three runs).
**Change:**
a. [R1] `feature` from `state.json .feature` (branch fallback; `branch` recorded) —
   attempt counters contiguous across branch creation.
b. [R2] SKILL codifies **branch-before-planning** (verified working in R2/R3).
c. [R1] deployment lines: clean tree + HEAD ⇒ `files_changed` from `git show --stat HEAD`.
d. [R2, recurred ×2 in R3 incl. a partial-mid-write variant] capped-status lines skip
   artifact-derived notes/extras entirely (`notes:"capped"`) — covers both stale
   (R2's 142/142; R3's 142/142) and interim (R3's 65/65) variants; the 65/65 line joins
   the fixtures.
e. [R1, recurred R2+R3] SKILL step 6b: re-run `run-summary.sh` post-deployment.
f. [R1] testing Stop order → `stamp-ran-at, log-run, record-clean` (final clean line
   records the cycle's real retries; verified uncoupled).
g. [R3] schema gains `skipped: {count, tests: []}` — **names, not just a count**
   (R3: 161/160/0 with the skipped test's identity unrecoverable from the artifact);
   log-run note renders "160 passed / 1 skipped / 161"; soft consistency
   `total == passed+failed+skipped.count` in the suite (telemetry check, never a gate).
**Accept:** replay all three run-logs — single feature identity, real deployment stat,
no capped-line extras, `retries:2` on R1's final testing line, R3's skip named.
**Risk:** low; legacy fallbacks throughout.

## U-17 — Loop budget documentation (wall clock + single-cycle compute)
**Origin: R1** (wall clock 86% at cycle 3 while compute sat at 68% — backstop working
as designed) **+ R3** (`compute_s: 0` on a 1-cycle loop — single-tick loops accumulate
nothing; not a defect, needs a sentence). *Was FIX-16/P2-3 + PD-N4.* **Change:**
loop-guard.sh header + SKILL: compute = primary bound (excludes human-wait by design),
wall = absolute backstop absorbing cap-resume latency, `LOOP_MAX_WALL_S` exists for
cap-heavy projects; raise the 7200 s default only if U-06 doesn't cut the tax (measure
first); single-cycle `compute_s: 0` is legitimate. **Risk:** none.

## U-18 — Loop route for "clean but predicate-failing"
**Origin: R1** (security clean + starlette 7.5: no written route exists; the
orchestrator improvised security→debugging at 19:01Z). *Was FIX-17/P2-4.* **Change:**
one SKILL line — clean but any GREEN security conjunct failing ⇒ route the failing
conjunct to debugging, continue. Predicate untouched. **Accept:** static.sh grep.
**Risk:** none.

## U-19 — Gating dependency-CVE ownership (docs; D2)
**Origin: R1** (security's description says it fixes exploitable vulns directly; the
gating starlette CVE was routed to debugging). *Was FIX-18/P2-6.* **Change:** per D2 in
security.md step 7 + debugging-escalation-protocol (recommended: debugging-as-
remediation — keeps security scan-focused and `fixed_count` honest). **Risk:** none.

## U-20 — Dangling `docs/pipeline-deployment-targets.md` reference
**Origin: R1 plan self-audit** (two template files reference a doc that never exists in
a scaffolded project; /code-review flagged it in R1). *Was FIX-19/P2-7.* **Change:**
reword both refs (`templates/CLAUDE.md:35`, bootstrap memory template) to the engine
repo / ci-conventions skill. **Accept:** scaffold-references-no-nonexistent-files grep
(joins U-11's suite). **Risk:** none.

## U-21 — Test-scaffolding rule-of-two
**Origin: R2** (275-line duplicated k6 harness; seed block ×5; `"ingest"` tag coupling)
**confirmed R3 — recurrence 3-for-3** (third harness fork, rationale docstring dropped,
tag propagated). **Justification correction folded in:** the R3 retro's "math
measurably diverged" was CONTRADICTED (f1↔f3 rank functions byte-identical; R2's copy
not comparable on that checkout) — cite recurrence, never realized divergence. *Was
FIX-20/F2-N4 + PD-X2.* **Change:** test-conventions rule — second use of a
fixture/seed/harness moves to conftest/shared helper; perf harnesses parameterize
scenario names; one testing.md pointer. Advisory (review/simplify remain enforcement).
**Accept:** M4 diff imports shared fixtures; ledger tracks recurrence. **Risk:** none.

## U-22 — Mutation testing runs in CI, not on the Windows host
**Origin: R2** (mutmut-needs-WSL honest skip, 2nd occurrence; R1 had the same
`quality_ok:false`). *Was FIX-21/F2-N7 (precision note folded: pipeline-ci.yml has NO
existing mutation placeholder — job + opt-in condition are new work).* **Change:**
opt-in advisory `mutation` job (ubuntu-latest, mutmut over configured scope, reports
score, never fails the gate); local honest-skip behavior and the WS3-1 deploy-side
honesty check untouched. **Accept:** CI job green with a real score; win32 fixture
still writes `quality_ok:false`. **Risk:** low.

---

# ROADMAP TIER

## U-23 — Agent-eval fixtures (planted-defect golden trees)
**Origin: R1 roadmap, corpus extended by R2 + R3.** *Was FIX-22/P0-3 + extensions.*
`tests/agent-evals/` in the engine repo; deterministic grep-assertions over real agent
runs; triggered by changes to audited agents/conventions/models; engine CI only.
**Corpus:** [R1] the four security classes (ALB-IP throttle key, ENABLE-not-FORCE RLS
w/ owner role, append-only + UPDATE/DELETE, sync KDF in async, unscrubbed query_string)
+ one crash-class control · [R2] a plan with an unenforced "provably implied" claim
(plan-audit eval) · [R3] a fixture-masks-production testing eval (reader-is-producer)
and a planted README with a wrong-signature-on-real-name + false behavioral claim
(documentation eval). First runs double as U-02/U-03/U-13 acceptance tests.
**Isolation rule (v2.1 — restored from the R1 entry, dropped in the merge):** the
planted trees contain real vulnerability shapes and must NEVER enter a bootstrapped
pipeline project — they live only under `tests/agent-evals/`, are excluded from
`install-global.sh` publishing and from every template path, and the eval runner
operates on read-only copies.
**Risk:** medium (token cost — smallest trees, targeted triggers, retry-once).

## U-24 — Proof gate (definition of done; no engine change)
**Origin: R1 roadmap + rows from all three runs.** 2–3 consecutive clean runs starting
with M4 (brownfield): cap tax <10% · 0 improvised interventions · ≥1 efficacy-class
catch pre-review (or review confirms zero escapes) · every executed/covered/verified
claim artifact-backed · run reconstructable post-teardown · every escape has a ledger
row · [R3] documentation identifiers resolve AND match (warn-count 0) · [R3] DAST
target reached · [R3] no undisclosed opt-in-stage skips. Failed criterion resets the
count after its fixes land. A 10/10 run's audit is boring.

---

# EXECUTION ORDER (commit-batched)

| Batch | Entries | Note |
|---|---|---|
| 0 | Pre-flight 1–3 | fixtures (3 runs), deploy telemetry resolved, install parity |
| 1 | U-01 | gate+predicate+invariant, one commit |
| 2 | U-05 + U-11 | U-11 red pre-fix, green post — same PR |
| 3 | U-04 | smoke matrix |
| 4 | U-02 + U-03 + U-07 + U-12 + U-21 | agent/skill prose wave |
| 5 | U-08 + U-13 (warn) + U-06 + U-14 | hooks + frontmatter + templates |
| 6 | U-09 | largest; its conjunct + invariant in one commit; formulas calibrated on pre-flight fixtures |
| 7 | U-16 + U-17 + U-18 + U-20 + U-22 | telemetry bundle + docs + CI job |
| 8 | U-15 + U-19 | after D1/D2/D3 |
| 9 | U-23 + U-10 (seed 30) | evals + ledger |
| 10 | **M4 proof run** | brownfield; U-03 pilot + U-13 promotion decision ride along |

Each batch: repo-of-record → suites green → `install-global.sh` → sha parity.

# RECOMMENDED AGAINST (consolidated, all three runs)
Redefining the wall clock [R1] · promoting full /code-review earlier — U-03's pilot is
the whole concession [R1+R2+R3] · splitting implementation into sub-passes [R1] ·
gating the perf verdict [R1] · pipeline-side mutmut install [R1; superseded by U-22] ·
gating stamp freshness [R1] · deterministic gate on doc identifiers [R2] ·
clone-detector gate [R2] · any new injection-defense machinery — the control just
passed a live adversarial eval [R3] · gating DAST / `target_reached` [R3] · further
documentation maxTurns raises before the model test [R3] · deciding D1–D3 unilaterally.

# KNOWN-UNVERIFIABLE / CONTRADICTED (do not restate as fact)
[R1] original smoke.env bytes · temp-leak path (class-patterned in U-08) · AC-PERF punt
dialogue · marker-denial mechanism (settle deliberately in M4) · per-stage token counts
· "security reported clean twice" (log: three).
[R2] "~3 caps" (log: 2 pre-deploy) · "guard denies rm" (**contradicted by source**) ·
"~30 tool-uses" · review-angle internals · seed "6×" (measured 5×) · JS-side "ingest".
[R3] "k6 math measurably diverged" (**contradicted:** f1↔f3 byte-identical) · DAST
"66 pass / 1 low WARN" (review file: 3 informational) · cap-cause attributions ·
design-approved **actor** (path proven; actor attested) · the skipped test's identity
(the U-16g defect demonstrating itself).

# v2.1 — PLAN SELF-AUDIT RECORD (audit of the unified plan itself)

Completeness: every item in the layered audit trail (R1–R4 entries, F2 + Phase D
appendices, all four self-audit correction sets) traced to a U-entry — no orphans; all
folded corrections verified present (checkov array formula + 58/59 convention, smoke
`exec` + default-var hazard, DAST direct-probe mechanism, skipped-names schema,
actor-attested distinction, `.pipeline`-only routing, warn-first promotion path).
Consistency: tier counts (3/11/8/2 = 24) verified; both new gate conjuncts (U-01, U-09)
pair with `loop-exit-invariant.sh` in single commits; D1–D3 nowhere pre-decided; all
recommend-againsts and unverifiable/contradicted tables carried per run.

Three defects found and patched in place:
1. **U-06 sequencing was ambiguous** (which documentation change ships in batch 5 vs
   waits on M4) — now explicit: sonnet@25 is the committed M4 experiment condition; the
   result decides the single follow-up change.
2. **U-23 dropped the R1 isolation rule in the merge** — planted-defect trees must never
   enter a bootstrapped project / template path / `install-global.sh` publish set;
   restored verbatim in intent.
3. **U-01's single-delegate design was implicit** — now stated: `delegated` accepts only
   `"security"` (rejected otherwise), and the enum may not widen until the new delegate
   stage has its own gate-conjunct-backed status file.

# OLD-ID → UNIFIED MAP
FIX-01→U-01 · FIX-02→U-02 · FIX-03+FIX-23→U-03 · FIX-04→U-04 · FIX-05→U-05 ·
FIX-06→U-06 · FIX-07→U-07 · FIX-08→U-08 · FIX-09→U-09 · FIX-10→U-10 · FIX-11→U-11 ·
FIX-12→U-12 · FIX-13→U-13 · FIX-24+FIX-26→U-14 · FIX-14→U-15 · FIX-15+FIX-25→U-16 ·
FIX-16→U-17 · FIX-17→U-18 · FIX-18→U-19 · FIX-19→U-20 · FIX-20→U-21 · FIX-21→U-22 ·
FIX-22→U-23 · proof gate→U-24. (P/PD/F2 designators map through their FIX numbers; see
`pipeline-fix-plan.md` for the full audit trail.)
